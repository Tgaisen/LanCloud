import 'dart:async';

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
import 'package:lancloud/core/transfer/upload_rename.dart';
import 'package:lancloud/core/upload_policy.dart';

class _MemoryStore implements TransferStore {
  _MemoryStore([Iterable<Map<String, Object?>> initial = const []]) {
    for (final row in initial) {
      rows['${row['id']}'] = Map<String, Object?>.from(row);
    }
  }

  final Map<String, Map<String, Object?>> rows = {};

  @override
  Future<List<Map<String, Object?>>> loadTransfers() async =>
      rows.values.toList(growable: false);

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
    String referer = '',
    String pwd = '',
    String localPath = '',
    String account = '',
  }) async {
    rows[id] = {
      'kind': kind,
      'name': name,
      'status': status,
      'total': total,
      'error': error,
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

class _UploadAccountPort implements TransferAccountPort {
  _UploadAccountPort(this.client);

  final LanzouClient client;

  @override
  String? get activeUid => 'u1';

  @override
  bool hasAccount(String uid) => uid == 'u1';

  @override
  LanzouClient clientFor(String uid) => client;

  @override
  LanzouClient get publicClient => client;
}

class _FixedPolicyClient extends LanzouClient {
  _FixedPolicyClient(this.policy) : super(uid: 'u1');

  final LanzouUploadPolicy policy;

  @override
  LanzouUploadPolicy get uploadPolicy => policy;
}

TransferManager _manager({
  required SettingsStore settings,
  required TransferStore store,
  required LanzouUploadPolicy policy,
}) {
  return TransferManager.withDependencies(
    TransferDependencies(
      store: store,
      accounts: _UploadAccountPort(_FixedPolicyClient(policy)),
      download: _NoDownload(),
      settings: StoreTransferSettingsPort(settings),
    ),
  );
}

void main() {
  test('上传筛选保留超限和不支持类型的任务为被跳过状态', () async {
    final store = _MemoryStore();
    final settings = SettingsStore()..maxUploads = 0;
    final manager = _manager(
      settings: settings,
      store: store,
      policy: const LanzouUploadPolicy(
        maxFileBytes: 10,
        allowedExtensions: {'zip'},
      ),
    );
    addTearDown(manager.dispose);

    expect(
      manager.addUpload(name: 'large.zip', folderId: 'f', size: 11),
      UploadAddResult.skippedOversize,
    );
    expect(
      manager.addUpload(name: 'photo.bin', folderId: 'f', size: 1),
      UploadAddResult.skippedUnsupported,
    );

    expect(manager.tasks, hasLength(2));
    expect(
      manager.tasks.map((task) => task.status),
      everyElement(TransferStatus.skipped),
    );
    final oversize = TransferIssue.decode(manager.tasks.first.error);
    expect(oversize?.code, TransferIssueCode.skippedOversize);
    expect(oversize?.detail, '10 B');
    expect(
      TransferIssue.decode(manager.tasks.last.error)?.code,
      TransferIssueCode.skippedUnsupported,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      store.rows.values.map((row) => row['status']),
      everyElement('skipped'),
    );
  });

  test('仍然上传会绕过筛选进入队列，清空只删除被跳过记录', () async {
    final settings = SettingsStore()..maxUploads = 0;
    final manager = _manager(
      settings: settings,
      store: _MemoryStore(),
      policy: const LanzouUploadPolicy(
        maxFileBytes: 100,
        allowedExtensions: {'txt'},
      ),
    );
    addTearDown(manager.dispose);

    expect(
      manager.addUpload(
        name: 'data.csv',
        folderId: 'f',
        streamFactory: () => Stream<List<int>>.value(const <int>[1]),
        size: 1,
      ),
      UploadAddResult.skippedUnsupported,
    );
    final skipped = manager.tasks.single;
    expect(await manager.uploadSkipped(skipped.id), isNull);
    expect(skipped.status, TransferStatus.queued);
    expect(skipped.error, isNull);

    expect(
      manager.addUpload(
        name: 'large.txt',
        folderId: 'f',
        streamFactory: () => Stream<List<int>>.value(const <int>[1]),
        size: 101,
      ),
      UploadAddResult.skippedOversize,
    );
    expect(manager.clearSkippedUploads(), hasLength(1));
    expect(manager.tasks, hasLength(1));
    expect(manager.tasks.single, same(skipped));
  });

  test('被跳过任务重新上传时，文件授权或源文件失效会转为失败', () async {
    final store = _MemoryStore();
    final settings = SettingsStore()..maxUploads = 0;
    final manager = _manager(
      settings: settings,
      store: store,
      policy: const LanzouUploadPolicy(
        maxFileBytes: 100,
        allowedExtensions: {'txt'},
      ),
    );
    addTearDown(manager.dispose);

    expect(
      manager.addUpload(
        name: 'shared.bin',
        folderId: 'f',
        path: 'content://shared/document/1',
        size: 1,
      ),
      UploadAddResult.skippedUnsupported,
    );
    expect(
      manager.addUpload(
        name: 'missing.bin',
        folderId: 'f',
        path: '/definitely/missing/lancloud-upload.bin',
        size: 1,
      ),
      UploadAddResult.skippedUnsupported,
    );
    final shared = manager.tasks[0];
    final missing = manager.tasks[1];

    expect(await manager.uploadSkipped(shared.id), '文件访问授权已过期，请重新选择文件上传');
    expect(shared.status, TransferStatus.failed);
    expect(
      TransferIssue.decode(shared.error)?.code,
      TransferIssueCode.uploadPermissionExpired,
    );

    expect(await manager.uploadSkipped(missing.id), '源文件已不存在，请重新选择文件上传');
    expect(missing.status, TransferStatus.failed);
    expect(
      TransferIssue.decode(missing.error)?.code,
      TransferIssueCode.uploadSourceMissing,
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      store.rows.values.map((row) => row['status']),
      everyElement('failed'),
    );
  });

  test('关闭筛选后任务直接进入队列', () {
    final settings = SettingsStore()
      ..maxUploads = 0
      ..skipOversizeUploads = false
      ..skipUnsupportedUploads = false;
    final manager = _manager(
      settings: settings,
      store: _MemoryStore(),
      policy: const LanzouUploadPolicy(
        maxFileBytes: 1,
        allowedExtensions: {'txt'},
      ),
    );
    addTearDown(manager.dispose);

    expect(
      manager.addUpload(name: 'large.csv', folderId: 'f', size: 2),
      UploadAddResult.queued,
    );
    expect(manager.tasks.single.status, TransferStatus.queued);
  });

  test('关闭自动开始后新任务进入待开始，手动上传后进入队列', () async {
    final store = _MemoryStore();
    final settings = SettingsStore()
      ..maxUploads = 0
      ..autoStartUploads = false;
    final manager = _manager(
      settings: settings,
      store: store,
      policy: const LanzouUploadPolicy(
        maxFileBytes: 100,
        allowedExtensions: {'txt'},
      ),
    );
    addTearDown(manager.dispose);

    expect(
      manager.addUpload(
        name: 'data.txt',
        folderId: 'f',
        streamFactory: () => Stream<List<int>>.value(const <int>[1]),
        size: 1,
      ),
      UploadAddResult.pending,
    );
    final task = manager.tasks.single;
    expect(task.status, TransferStatus.pending);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(store.rows[task.id]?['status'], 'pending');

    expect(manager.startUploads([task.id]), 1);
    expect(task.status, TransferStatus.queued);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(store.rows[task.id]?['status'], 'queued');
  });

  test('改名后会按当前筛选重新决定待开始或被跳过', () async {
    final store = _MemoryStore();
    final settings = SettingsStore()..maxUploads = 0;
    final manager = _manager(
      settings: settings,
      store: store,
      policy: const LanzouUploadPolicy(
        maxFileBytes: 100,
        allowedExtensions: {'txt'},
      ),
    );
    addTearDown(manager.dispose);

    expect(
      manager.addUpload(
        name: 'data.csv',
        folderId: 'f',
        streamFactory: () => Stream<List<int>>.value(const <int>[1]),
        size: 1,
      ),
      UploadAddResult.skippedUnsupported,
    );
    expect(
      manager.addUpload(
        name: 'large.txt',
        folderId: 'f',
        streamFactory: () => Stream<List<int>>.value(const <int>[1]),
        size: 101,
      ),
      UploadAddResult.skippedOversize,
    );
    final unsupported = manager.tasks[0];
    final oversize = manager.tasks[1];

    expect(
      manager.renameUploads([
        UploadRenameChange(
          id: unsupported.id,
          originalName: unsupported.name,
          newName: 'data.txt',
        ),
        UploadRenameChange(
          id: oversize.id,
          originalName: oversize.name,
          newName: 'renamed.txt',
        ),
      ]),
      2,
    );
    expect(unsupported.name, 'data.txt');
    expect(unsupported.status, TransferStatus.pending);
    expect(unsupported.error, isNull);
    expect(oversize.name, 'renamed.txt');
    expect(oversize.status, TransferStatus.skipped);
    expect(
      TransferIssue.decode(oversize.error)?.code,
      TransferIssueCode.skippedOversize,
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(store.rows[unsupported.id]?['name'], 'data.txt');
    expect(store.rows[unsupported.id]?['status'], 'pending');
    expect(store.rows[oversize.id]?['status'], 'skipped');
  });

  test('重启恢复时待开始保持为待开始', () async {
    final store = _MemoryStore([
      {
        'id': 'u1',
        'kind': 'upload',
        'name': 'pending.txt',
        'status': 'pending',
        'account': 'u1',
        'total': 1,
      },
    ]);
    final manager = _manager(
      settings: SettingsStore(),
      store: store,
      policy: LanzouUploadPolicy.fallback,
    );
    addTearDown(manager.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(manager.tasks.single.status, TransferStatus.pending);
  });
}
