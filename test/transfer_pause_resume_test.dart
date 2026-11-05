import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/download_target.dart';
import 'package:lancloud/core/notifications.dart';
import 'package:lancloud/core/shared_downloads_gateway.dart';
import 'package:lancloud/core/shared_downloads_storage.dart';
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

    test('should 在 TransferManager 内解析缺失直链后开始下载', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'lancloud-transfer-resolve',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final payload = List<int>.generate(512, (index) => index % 191);
      final notifications = _RecordingNotificationSink();
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: _FakeTransferStore(),
          accounts: _FakeTransferAccountPort(),
          download: _FakeTransferDownloadPort(tempDir.path),
          settings: StoreTransferSettingsPort(
            SettingsStore()..maxDownloads = 1,
          ),
        ),
        notifications: notifications,
        downloader: _ImmediateDownloader(payload),
      );
      addTearDown(manager.dispose);
      final resolvingStarted = Completer<void>();
      final resolving = Completer<DirectFile>();
      manager.debugResolveShare = (url, pwd) {
        resolvingStarted.complete();
        return resolving.future;
      };

      manager.addDownload(
        url: '',
        name: 'archive.zip',
        referer: 'https://example.com/share',
      );
      final task = manager.tasks.single;
      await resolvingStarted.future;

      expect(task.status, TransferStatus.resolving);
      expect(
        notifications.snapshots.last.state,
        TransferNotificationState.resolving,
      );
      resolving.complete(
        DirectFile(name: 'archive.zip', url: 'https://cdn.example/archive.zip'),
      );

      await _waitFor(() => task.status == TransferStatus.done);
      expect(task.url, 'https://cdn.example/archive.zip');
      expect(await File(task.savedPath!).readAsBytes(), payload);
    });

    test('should 批量暂停下载且忽略上传、已暂停和保存中的任务', () {
      final settings = SettingsStore()..maxDownloads = 0;
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: _FakeTransferStore(),
          accounts: _FakeTransferAccountPort(),
          download: const _FakeTransferDownloadPort(''),
          settings: StoreTransferSettingsPort(settings),
        ),
      );
      addTearDown(manager.dispose);
      manager.tasks.addAll([
        TransferTask(
          id: 'queued',
          kind: TransferKind.download,
          name: 'queued.zip',
          accountUid: '',
        )..status = TransferStatus.queued,
        TransferTask(
          id: 'running',
          kind: TransferKind.download,
          name: 'running.zip',
          accountUid: '',
        )..status = TransferStatus.running,
        TransferTask(
          id: 'already-paused',
          kind: TransferKind.download,
          name: 'paused.zip',
          accountUid: '',
        )..status = TransferStatus.paused,
        TransferTask(
          id: 'saving',
          kind: TransferKind.download,
          name: 'saving.zip',
          accountUid: '',
        )..status = TransferStatus.saving,
        TransferTask(
          id: 'upload',
          kind: TransferKind.upload,
          name: 'upload.zip',
          accountUid: '',
        )..status = TransferStatus.running,
      ]);
      var notifications = 0;
      manager.addListener(() => notifications += 1);

      manager.pauseDownloads(manager.tasks.map((task) => task.id));

      expect(manager.tasks[0].status, TransferStatus.paused);
      expect(manager.tasks[1].status, TransferStatus.paused);
      expect(manager.tasks[2].status, TransferStatus.paused);
      expect(manager.tasks[3].status, TransferStatus.saving);
      expect(manager.tasks[4].status, TransferStatus.running);
      expect(notifications, 1);
    });

    test('should 批量恢复暂停下载并返回失败数量', () async {
      final settings = SettingsStore()..maxDownloads = 0;
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: _FakeTransferStore(),
          accounts: _FakeTransferAccountPort(),
          download: const _FakeTransferDownloadPort(''),
          settings: StoreTransferSettingsPort(settings),
        ),
      );
      addTearDown(manager.dispose);
      final ready = TransferTask(
        id: 'ready',
        kind: TransferKind.download,
        name: 'ready.zip',
        accountUid: '',
        url: 'https://cdn.example/ready.zip',
      )..status = TransferStatus.paused;
      final unavailable = TransferTask(
        id: 'unavailable',
        kind: TransferKind.download,
        name: 'unavailable.zip',
        accountUid: '',
      )..status = TransferStatus.paused;
      manager.tasks.addAll([ready, unavailable]);

      final failed = await manager.resumeDownloads([ready.id, unavailable.id]);

      expect(failed, 1);
      expect(ready.status, TransferStatus.queued);
      expect(unavailable.status, TransferStatus.paused);
      expect(unavailable.error, isNotEmpty);
    });

    test('should 只清空指定类型的全部已结束任务', () {
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: _FakeTransferStore(),
          accounts: _FakeTransferAccountPort(),
          download: const _FakeTransferDownloadPort(''),
          settings: StoreTransferSettingsPort(SettingsStore()),
        ),
      );
      addTearDown(manager.dispose);
      manager.tasks.addAll([
        TransferTask(
          id: 'u-done',
          kind: TransferKind.upload,
          name: 'done.zip',
          accountUid: '',
        )..status = TransferStatus.done,
        TransferTask(
          id: 'u-failed',
          kind: TransferKind.upload,
          name: 'failed.zip',
          accountUid: '',
        )..status = TransferStatus.failed,
        TransferTask(
          id: 'u-active',
          kind: TransferKind.upload,
          name: 'active.zip',
          accountUid: '',
        )..status = TransferStatus.running,
        TransferTask(
          id: 'd-done',
          kind: TransferKind.download,
          name: 'download.zip',
          accountUid: '',
        )..status = TransferStatus.done,
      ]);

      final removed = manager.clearFinished(TransferKind.upload);

      expect(removed.map((task) => task.id), ['u-done', 'u-failed']);
      expect(manager.tasks.map((task) => task.id), ['u-active', 'd-done']);
    });

    test('should 将高频进度通知限制为每秒一次', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'lancloud-transfer-progress',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final payload = List<int>.generate(128, (index) => index);
      final downloader = _BurstProgressDownloader(payload);
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
        progressUpdateInterval: const Duration(hours: 1),
      );
      addTearDown(manager.dispose);
      var notifications = 0;
      manager.addListener(() => notifications += 1);

      manager.addDownload(
        url: 'https://cdn.example/file',
        name: 'archive.zip',
        size: payload.length,
      );
      final task = manager.tasks.single;
      await downloader.started.future;
      final beforeBurst = notifications;

      downloader.emitProgress.complete();
      await downloader.progressBurst.future;

      expect(task.received, payload.length);
      expect(notifications, beforeBurst + 1);

      downloader.finish.complete();
      await _waitFor(() => task.status == TransferStatus.done);
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
      expect(task.status, TransferStatus.resuming);
      manager.cancel(task.id);
      resolving.complete(
        DirectFile(name: 'archive.zip', url: 'https://cdn.example/file'),
      );

      expect(await resumeFuture, isNull);
      expect(task.removed, isTrue);
      expect(manager.tasks, isEmpty);
    });

    test('should 在中转文件复制期间显示保存状态并禁止暂停', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'lancloud-transfer-saving',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final payload = List<int>.generate(4096, (index) => index % 193);
      final shared = _BlockingSharedDownloads(payload.length);
      final notifications = _RecordingNotificationSink();
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: _FakeTransferStore(),
          accounts: _FakeTransferAccountPort(),
          download: _FakeTransferDownloadPort(
            tempDir.path,
            mode: DownloadTargetMode.sharedDownloads,
          ),
          settings: StoreTransferSettingsPort(SettingsStore()),
        ),
        notifications: notifications,
        downloader: _ImmediateDownloader(payload),
        sharedDownloads: shared,
      );
      addTearDown(manager.dispose);

      manager.addDownload(
        url: 'https://cdn.example/file',
        name: 'archive.zip',
        size: payload.length,
      );
      final task = manager.tasks.single;
      await shared.started.future;

      expect(task.status, TransferStatus.saving);
      expect(
        notifications.snapshots.last.state,
        TransferNotificationState.saving,
      );
      await _waitFor(() => task.received == 256);
      manager.pause(task.id);
      expect(task.status, TransferStatus.saving);

      shared.release.complete();
      await _waitFor(() => task.status == TransferStatus.done);
      expect(task.savedPath, 'content://saved/archive.zip');
    });

    test('should 关闭进度通知时只保留独立完成通知', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'lancloud-transfer-notify-done',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final payload = List<int>.generate(256, (index) => index);
      final notifications = _RecordingNotificationSink();
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: _FakeTransferStore(),
          accounts: _FakeTransferAccountPort(),
          download: _FakeTransferDownloadPort(tempDir.path),
          settings: StoreTransferSettingsPort(
            SettingsStore()
              ..maxDownloads = 1
              ..notifyProgress = false
              ..notifyDone = true,
          ),
        ),
        notifications: notifications,
        downloader: _ImmediateDownloader(payload),
      );
      addTearDown(manager.dispose);

      manager.addDownload(
        url: 'https://cdn.example/file',
        name: 'archive.zip',
        size: payload.length,
      );
      final task = manager.tasks.single;
      await _waitFor(() => task.status == TransferStatus.done);

      expect(notifications.cancellations, contains(task.id));
      expect(
        notifications.snapshots
            .where((snapshot) => snapshot.taskId == task.id)
            .single
            .state,
        TransferNotificationState.done,
      );
    });

    test('should 关闭完成通知时在任务结束后移除进度通知', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'lancloud-transfer-notify-progress',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final payload = List<int>.generate(256, (index) => index);
      final notifications = _RecordingNotificationSink();
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: _FakeTransferStore(),
          accounts: _FakeTransferAccountPort(),
          download: _FakeTransferDownloadPort(tempDir.path),
          settings: StoreTransferSettingsPort(
            SettingsStore()
              ..maxDownloads = 1
              ..notifyProgress = true
              ..notifyDone = false,
          ),
        ),
        notifications: notifications,
        downloader: _ImmediateDownloader(payload),
      );
      addTearDown(manager.dispose);

      manager.addDownload(
        url: 'https://cdn.example/file',
        name: 'archive.zip',
        size: payload.length,
      );
      final task = manager.tasks.single;
      await _waitFor(() => task.status == TransferStatus.done);

      expect(
        notifications.snapshots.map((snapshot) => snapshot.state),
        contains(TransferNotificationState.downloading),
      );
      expect(
        notifications.snapshots.map((snapshot) => snapshot.state),
        isNot(contains(TransferNotificationState.done)),
      );
      expect(notifications.cancellations.last, task.id);
    });

    test('should 暂停时保留当前任务的实际通知进度', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'lancloud-transfer-notify-paused',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final payload = List<int>.generate(1024, (index) => index % 191);
      final downloader = _PausingDownloader(payload);
      final notifications = _RecordingNotificationSink();
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: _FakeTransferStore(),
          accounts: _FakeTransferAccountPort(),
          download: _FakeTransferDownloadPort(tempDir.path),
          settings: StoreTransferSettingsPort(
            SettingsStore()..maxDownloads = 1,
          ),
        ),
        notifications: notifications,
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

      manager.pause(task.id);
      await downloader.paused.future;

      final paused = notifications.snapshots.last;
      expect(paused.taskId, task.id);
      expect(paused.state, TransferNotificationState.paused);
      expect(paused.received, payload.length ~/ 2);
      expect(paused.total, payload.length);
    });

    test('should 上传完成后自动移除任务通知', () async {
      final notifications = _RecordingNotificationSink();
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: _FakeTransferStore(),
          accounts: _ImmediateUploadAccountPort(),
          download: const _FakeTransferDownloadPort(''),
          settings: StoreTransferSettingsPort(SettingsStore()),
        ),
        notifications: notifications,
      );
      addTearDown(manager.dispose);

      manager.addUpload(
        name: 'upload.zip',
        folderId: '-1',
        streamFactory: () => Stream<List<int>>.value(<int>[1, 2]),
        size: 2,
      );
      final task = manager.tasks.single;
      await _waitFor(() => task.status == TransferStatus.done);

      expect(
        notifications.snapshots.map((snapshot) => snapshot.state),
        contains(TransferNotificationState.uploading),
      );
      expect(
        notifications.snapshots.map((snapshot) => snapshot.state),
        isNot(contains(TransferNotificationState.done)),
      );
      expect(notifications.cancellations.last, task.id);
    });

    test('should 失败时显示可关闭的独立失败通知', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'lancloud-transfer-notify-failed',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final notifications = _RecordingNotificationSink();
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: _FakeTransferStore(),
          accounts: _FakeTransferAccountPort(),
          download: _FakeTransferDownloadPort(tempDir.path),
          settings: StoreTransferSettingsPort(
            SettingsStore()..maxDownloads = 1,
          ),
        ),
        notifications: notifications,
        downloader: const _FailingDownloader(),
      );
      addTearDown(manager.dispose);

      manager.addDownload(url: 'https://cdn.example/file', name: 'archive.zip');
      final task = manager.tasks.single;
      await _waitFor(() => task.status == TransferStatus.failed);

      final failed = notifications.snapshots.last;
      expect(failed.taskId, task.id);
      expect(failed.state, TransferNotificationState.failed);
      expect(failed.error, isNotEmpty);
    });

    test('should 将应用中退出时残留的保存状态恢复为失败', () async {
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: _FakeTransferStore([
            {
              'id': 'd1',
              'kind': 'download',
              'name': 'archive.zip',
              'status': 'saving',
            },
          ]),
          accounts: _FakeTransferAccountPort(),
          download: const _FakeTransferDownloadPort(''),
          settings: StoreTransferSettingsPort(SettingsStore()),
        ),
      );
      addTearDown(manager.dispose);

      await _waitFor(() => manager.tasks.isNotEmpty);
      expect(manager.tasks.single.status, TransferStatus.failed);
      expect(manager.tasks.single.error, '应用已退出，任务中断');
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

class _ImmediateDownloader implements TransferDownloader {
  _ImmediateDownloader(this.payload);

  final List<int> payload;

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
    await File(partialPath).writeAsBytes(payload);
    onProgress(payload.length, payload.length);
    return TransferDownloadResult(total: payload.length, resumed: false);
  }
}

class _FailingDownloader implements TransferDownloader {
  const _FailingDownloader();

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
  }) {
    throw DioException.connectionError(
      requestOptions: RequestOptions(path: url),
      reason: 'Connection closed while receiving data',
    );
  }
}

class _ImmediateUploadAccountPort implements TransferAccountPort {
  final LanzouClient _client = _ImmediateUploadClient();

  @override
  String? get activeUid => 'u1';

  @override
  bool hasAccount(String uid) => uid == 'u1';

  @override
  LanzouClient clientFor(String uid) => _client;

  @override
  LanzouClient get publicClient => throw UnimplementedError('上传测试不需要公开客户端');
}

class _ImmediateUploadClient extends LanzouClient {
  _ImmediateUploadClient() : super(uid: 'u1');

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
    final total = size ?? 0;
    onProgress?.call(total, total);
  }
}

class _BurstProgressDownloader implements TransferDownloader {
  _BurstProgressDownloader(this.payload);

  final List<int> payload;
  final Completer<void> started = Completer<void>();
  final Completer<void> emitProgress = Completer<void>();
  final Completer<void> progressBurst = Completer<void>();
  final Completer<void> finish = Completer<void>();

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
    started.complete();
    await emitProgress.future;
    onProgress(1, payload.length);
    onProgress(2, payload.length);
    onProgress(payload.length, payload.length);
    progressBurst.complete();
    await finish.future;
    await File(partialPath).writeAsBytes(payload);
    return TransferDownloadResult(total: payload.length, resumed: false);
  }
}

class _RecordingNotificationSink implements TransferNotificationSink {
  final List<TransferNotificationSnapshot> snapshots =
      <TransferNotificationSnapshot>[];
  final List<String> cancellations = <String>[];

  @override
  void showTransferTask(TransferNotificationSnapshot snapshot) {
    snapshots.add(snapshot);
  }

  @override
  void cancelTransferTask(String taskId) {
    cancellations.add(taskId);
  }
}

class _BlockingSharedDownloads implements SharedDownloadsGateway {
  _BlockingSharedDownloads(this.total);

  final int total;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<String?> defaultDirectoryPath() async => null;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<SharedDownloadedFile> save({
    required String sourcePath,
    required String fileName,
    required String mime,
    String jobId = '',
    void Function(int copied, int total)? onProgress,
  }) async {
    started.complete();
    onProgress?.call(256, total);
    await release.future;
    onProgress?.call(total, total);
    return SharedDownloadedFile(
      uri: 'content://saved/$fileName',
      name: fileName,
    );
  }
}

class _FakeTransferStore implements TransferStore {
  _FakeTransferStore([this.rows = const <Map<String, Object?>>[]]);

  final List<Map<String, Object?>> rows;

  @override
  Future<List<Map<String, Object?>>> loadTransfers() async => rows;

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
  const _FakeTransferDownloadPort(
    this.directory, {
    this.mode = DownloadTargetMode.fixedDirectory,
  });

  final String directory;
  final DownloadTargetMode mode;

  @override
  Future<String> partialFilePath(
    String taskId,
    String name, {
    required bool staged,
  }) async => p.join(directory, '$taskId.part');

  @override
  String? get safTreeUri => null;

  @override
  Future<DownloadTargetMode> targetMode() async => mode;

  @override
  Future<String> uniqueSavePath(String name) async => p.join(directory, name);
}
