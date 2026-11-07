import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/download_target.dart';
import 'package:lancloud/core/transfer/transfer_account_port.dart';
import 'package:lancloud/core/transfer/transfer_dependencies.dart';
import 'package:lancloud/core/transfer/transfer_download_port.dart';
import 'package:lancloud/core/transfer/transfer_issue.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_settings_port.dart';
import 'package:lancloud/core/transfer/transfer_store.dart';

class _MemoryStore implements TransferStore {
  final Map<String, Map<String, Object?>> rows = {};

  @override
  Future<List<Map<String, Object?>>> loadTransfers() async => const [];

  @override
  Future<void> saveTransfer({
    required String id,
    required String kind,
    required String name,
    required String status,
    int total = 0,
    int received = 0,
    String error = '',
    String savedPath = '',
    String ref = '',
    String folderId = '',
    String folderName = '',
    String referer = '',
    String pwd = '',
    String localPath = '',
    String account = '',
  }) async {
    rows[id] = {
      'kind': kind,
      'name': name,
      'status': status,
      'error': error,
      'folder_id': folderId,
      'folder_name': folderName,
      'account': account,
    };
  }

  @override
  Future<void> deleteTransfer(String id) async {
    rows.remove(id);
  }

  @override
  Future<void> deleteTransfers(List<String> ids) async {
    for (final id in ids) {
      rows.remove(id);
    }
  }
}

class _NoDownload implements TransferDownloadPort {
  @override
  Future<DownloadTargetMode> targetMode() async =>
      DownloadTargetMode.fixedDirectory;

  @override
  String? get safTreeUri => null;

  @override
  Future<String> partialFilePath(
    String taskId,
    String name, {
    required bool staged,
  }) async => throw UnimplementedError();

  @override
  Future<String> uniqueSavePath(String name) async =>
      throw UnimplementedError();
}

class _AccountPort implements TransferAccountPort {
  _AccountPort(this.client);

  final LanzouClient client;
  String? activeUidValue = 'a';

  @override
  String? get activeUid => activeUidValue;

  @override
  bool hasAccount(String uid) => uid == 'a' || uid == 'b';

  @override
  LanzouClient clientFor(String uid) => client;

  @override
  LanzouClient get publicClient => client;
}

class _BlockingUploadClient extends LanzouClient {
  _BlockingUploadClient() : super(uid: 'a');

  final Completer<void> started = Completer<void>();

  @override
  Future<void> uploadFile({
    required String name,
    required String folderId,
    String? path,
    Stream<List<int>> Function()? streamFactory,
    int? size,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!started.isCompleted) started.complete();
    await cancelToken!.whenCancel;
  }
}

({TransferManager manager, _MemoryStore store, _AccountPort accounts}) _build({
  required SettingsStore settings,
  LanzouClient? client,
}) {
  final store = _MemoryStore();
  final accounts = _AccountPort(client ?? _BlockingUploadClient());
  final manager = TransferManager.withDependencies(
    TransferDependencies(
      store: store,
      accounts: accounts,
      download: _NoDownload(),
      settings: StoreTransferSettingsPort(settings),
    ),
  );
  addTearDown(manager.dispose);
  return (manager: manager, store: store, accounts: accounts);
}

void main() {
  group('TransferManager 上传账号范围', () {
    test('should only expose uploads for the selected account', () async {
      final setup = _build(
        settings: SettingsStore()
          ..maxUploads = 0
          ..autoStartUploads = false,
      );
      final manager = setup.manager;

      manager.addUpload(name: 'a.zip', folderId: 'fa', size: 1);
      setup.accounts.activeUidValue = 'b';
      manager.addUpload(name: 'b.zip', folderId: 'fb', size: 1);
      manager.addDownload(
        name: 'download.zip',
        url: 'https://example.com/download.zip',
      );

      expect(manager.uploadsForAccount('a').map((task) => task.name), [
        'a.zip',
      ]);
      expect(manager.uploadsForAccount('b').map((task) => task.name), [
        'b.zip',
      ]);
      expect(manager.byKind(TransferKind.download), hasLength(1));
    });

    test('should only clear uploads belonging to the selected account', () {
      final setup = _build(
        settings: SettingsStore()
          ..maxUploads = 0
          ..autoStartUploads = false,
      );
      final manager = setup.manager;

      manager.addUpload(name: 'a.zip', folderId: 'fa', size: 1);
      setup.accounts.activeUidValue = 'b';
      manager.addUpload(name: 'b.zip', folderId: 'fb', size: 1);

      final removed = manager.clearPendingUploads(uploadAccountUid: 'a');

      expect(removed.map((task) => task.name), ['a.zip']);
      expect(manager.tasks.map((task) => task.name), ['b.zip']);
    });

    test(
      'should persist a destination change only for pending same-account tasks',
      () async {
        final setup = _build(
          settings: SettingsStore()
            ..maxUploads = 0
            ..autoStartUploads = false,
        );
        final manager = setup.manager;
        manager.addUpload(name: 'a.zip', folderId: 'old', size: 1);
        final task = manager.tasks.single;

        expect(
          manager.movePendingUploads(
            ids: [task.id],
            folderId: 'new',
            folderName: '新目录',
            accountUid: 'b',
          ),
          0,
        );
        expect(
          manager.movePendingUploads(
            ids: [task.id],
            folderId: 'new',
            folderName: '新目录',
            accountUid: 'a',
          ),
          1,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(task.folderId, 'new');
        expect(task.folderName, '新目录');
        expect(setup.store.rows[task.id]?['folder_id'], 'new');
        expect(setup.store.rows[task.id]?['folder_name'], '新目录');
      },
    );
  });

  group('TransferManager 切换账号中断', () {
    test(
      'should stop a running upload and leave a retryable failed task',
      () async {
        final client = _BlockingUploadClient();
        final settings = SettingsStore()
          ..maxUploads = 1
          ..maxDownloads = 0;
        final setup = _build(settings: settings, client: client);
        final manager = setup.manager;

        manager.addUpload(
          name: 'running.zip',
          folderId: 'a',
          size: 1,
          streamFactory: () => Stream<List<int>>.value(const [1]),
        );
        await client.started.future;
        expect(manager.activeUploadCount, 1);

        expect(await manager.interruptActiveUploads(), 1);

        final task = manager.tasks.single;
        expect(task.status, TransferStatus.failed);
        expect(
          TransferIssue.decode(task.error)?.code,
          TransferIssueCode.uploadInterruptedByAccountSwitch,
        );

        settings.maxUploads = 0;
        expect(await manager.retry(task.id), isNull);
        expect(task.status, TransferStatus.queued);
        expect(task.error, isNull);
        expect(task.interruptedByAccountSwitch, isFalse);
      },
    );

    test(
      'should move queued uploads out of scheduling but keep downloads',
      () async {
        final settings = SettingsStore()
          ..maxUploads = 0
          ..maxDownloads = 0;
        final setup = _build(settings: settings);
        final manager = setup.manager;
        manager.addUpload(name: 'one.zip', folderId: 'a', size: 1);
        setup.accounts.activeUidValue = 'b';
        manager.addUpload(name: 'two.zip', folderId: 'a', size: 1);
        manager.tasks.add(
          TransferTask(
            id: 'download',
            kind: TransferKind.download,
            name: 'download.zip',
            accountUid: 'a',
          )..status = TransferStatus.running,
        );

        expect(await manager.interruptActiveUploads(), 2);
        expect(
          manager.tasks
              .where((task) => task.kind == TransferKind.upload)
              .map((task) => task.status),
          everyElement(TransferStatus.failed),
        );
        expect(manager.tasks.last.status, TransferStatus.running);
      },
    );
  });
}
