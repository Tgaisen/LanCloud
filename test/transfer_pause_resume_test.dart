import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/download_target.dart';
import 'package:lancloud/core/transfer/resumable_downloader.dart';
import 'package:lancloud/core/transfer/transfer_account_port.dart';
import 'package:lancloud/core/transfer/transfer_dependencies.dart';
import 'package:lancloud/core/transfer/transfer_download_port.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_settings_port.dart';
import 'package:lancloud/core/transfer/transfer_store.dart';
import 'package:path/path.dart' as p;

void main() {
  group('TransferManager 暂停与继续', () {
    test('should 保留断点文件并在继续后完成下载', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'lancloud-transfer-pause',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final payload = List<int>.generate(2048, (index) => index % 197);
      final downloader = _PausingDownloader(payload);
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: _FakeTransferStore(),
          accounts: _FakeTransferAccountPort(),
          download: _FakeTransferDownloadPort(tempDir.path),
          settings: StoreTransferSettingsPort(
            SettingsStore()..maxDownloads = 1,
          ),
        ),
        downloader: downloader,
      );
      addTearDown(manager.dispose);

      manager.addDownload(
        url: 'https://cdn.example/file',
        name: 'archive.zip',
        size: payload.length,
      );
      final task = manager.tasks.single;
      await downloader.started.future;
      final partialPath = p.join(tempDir.path, '${task.id}.part');
      expect(await File(partialPath).length(), payload.length ~/ 2);

      manager.pause(task.id);
      expect(task.status, TransferStatus.paused);
      await downloader.paused.future;

      expect(await File(partialPath).exists(), isTrue);
      expect(task.received, payload.length ~/ 2);
      final message = await manager.resume(task.id);
      expect(message, isNull);

      await _waitFor(() => task.status == TransferStatus.done);
      final savedPath = task.savedPath;
      expect(savedPath, isNotNull);
      expect(await File(savedPath!).readAsBytes(), payload);
      expect(await File(partialPath).exists(), isFalse);
      expect(downloader.calls, 2);
    });

    test('should 在直链失效后重新解析并继续原临时文件', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'lancloud-transfer-refresh',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final payload = List<int>.generate(1536, (index) => index % 181);
      final downloader = _ExpiredLinkDownloader(payload);
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: _FakeTransferStore(),
          accounts: _FakeTransferAccountPort(),
          download: _FakeTransferDownloadPort(tempDir.path),
          settings: StoreTransferSettingsPort(SettingsStore()),
        ),
        downloader: downloader,
      );
      addTearDown(manager.dispose);
      var resolved = 0;
      manager.debugResolveShare = (url, pwd) async {
        resolved += 1;
        return DirectFile(name: 'archive.zip', url: 'https://cdn.example/new');
      };

      manager.addDownload(
        url: 'https://cdn.example/expired',
        name: 'archive.zip',
        referer: 'https://example.com/share',
        size: payload.length,
      );
      final task = manager.tasks.single;

      await _waitFor(() => task.status == TransferStatus.done);
      expect(resolved, 1);
      expect(downloader.urls, [
        'https://cdn.example/expired',
        'https://cdn.example/new',
      ]);
      expect(task.url, 'https://cdn.example/new');
      expect(await File(task.savedPath!).readAsBytes(), payload);
    });

    test('should 在重新解析期间取消后保持取消状态', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'lancloud-transfer-cancel-resume',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: _FakeTransferStore(),
          accounts: _FakeTransferAccountPort(),
          download: _FakeTransferDownloadPort(tempDir.path),
          settings: StoreTransferSettingsPort(SettingsStore()),
        ),
      );
      addTearDown(manager.dispose);
      final resolving = Completer<DirectFile>();
      final resolvingStarted = Completer<void>();
      manager.debugResolveShare = (url, pwd) {
        resolvingStarted.complete();
        return resolving.future;
      };
      final task = TransferTask(
        id: 'd1',
        kind: TransferKind.download,
        name: 'archive.zip',
        accountUid: '',
        referer: 'https://example.com/share',
      )..status = TransferStatus.paused;
      manager.tasks.add(task);

      final resumeFuture = manager.resume(task.id);
      await resolvingStarted.future;
      manager.cancel(task.id);
      resolving.complete(
        DirectFile(name: 'archive.zip', url: 'https://cdn.example/file'),
      );

      expect(await resumeFuture, isNull);
      expect(task.status, TransferStatus.canceled);
    });
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('等待传输状态超时');
}

class _PausingDownloader implements TransferDownloader {
  _PausingDownloader(this.payload);

  final List<int> payload;
  final Completer<void> started = Completer<void>();
  final Completer<void> paused = Completer<void>();
  int calls = 0;

  @override
  Future<TransferDownloadResult> download({
    required Dio dio,
    required String url,
    required String partialPath,
    required int expectedTotal,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required TransferDownloadProgress onProgress,
  }) async {
    calls += 1;
    final file = File(partialPath);
    if (calls == 1) {
      final firstPart = payload.sublist(0, payload.length ~/ 2);
      await file.writeAsBytes(firstPart);
      onProgress(firstPart.length, payload.length);
      started.complete();
      await cancelToken.whenCancel;
      paused.complete();
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: url),
        reason: cancelToken.cancelError,
      );
    }

    final existing = await file.exists() ? await file.length() : 0;
    final remaining = payload.sublist(existing);
    await file.writeAsBytes(remaining, mode: FileMode.append);
    onProgress(payload.length, payload.length);
    return TransferDownloadResult(total: payload.length, resumed: existing > 0);
  }
}

class _ExpiredLinkDownloader implements TransferDownloader {
  _ExpiredLinkDownloader(this.payload);

  final List<int> payload;
  final List<String> urls = <String>[];

  @override
  Future<TransferDownloadResult> download({
    required Dio dio,
    required String url,
    required String partialPath,
    required int expectedTotal,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required TransferDownloadProgress onProgress,
  }) async {
    urls.add(url);
    if (urls.length == 1) {
      final firstPart = payload.sublist(0, 256);
      await File(partialPath).writeAsBytes(firstPart);
      onProgress(firstPart.length, payload.length);
      final request = RequestOptions(path: url);
      throw DioException.badResponse(
        statusCode: 403,
        requestOptions: request,
        response: Response<void>(requestOptions: request, statusCode: 403),
      );
    }
    final file = File(partialPath);
    final existing = await file.exists() ? await file.length() : 0;
    await file.writeAsBytes(payload.sublist(existing), mode: FileMode.append);
    onProgress(payload.length, payload.length);
    return TransferDownloadResult(total: payload.length, resumed: existing > 0);
  }
}

class _FakeTransferStore implements TransferStore {
  @override
  Future<List<Map<String, Object?>>> loadTransfers() async =>
      const <Map<String, Object?>>[];

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
  }) async {}

  @override
  Future<void> deleteTransfer(String id) async {}

  @override
  Future<void> deleteTransfers(List<String> ids) async {}

  @override
  Future<void> markDownloaded({
    required String ref,
    required String name,
    String path = '',
  }) async {}
}

class _FakeTransferAccountPort implements TransferAccountPort {
  @override
  String? get activeUid => 'u1';

  @override
  bool hasAccount(String uid) => uid == 'u1';

  @override
  LanzouClient clientFor(String uid) =>
      throw UnimplementedError('暂停恢复测试不需要账号客户端');

  @override
  LanzouClient get publicClient => throw UnimplementedError('本会话内已有直链，不需要重新解析');
}

class _FakeTransferDownloadPort implements TransferDownloadPort {
  const _FakeTransferDownloadPort(this.directory);

  final String directory;

  @override
  Future<String> partialFilePath(
    String taskId,
    String name, {
    required bool staged,
  }) async => p.join(directory, '$taskId.part');

  @override
  String? get safTreeUri => null;

  @override
  Future<DownloadTargetMode> targetMode() async =>
      DownloadTargetMode.fixedDirectory;

  @override
  Future<String> uniqueSavePath(String name) async => p.join(directory, name);
}
