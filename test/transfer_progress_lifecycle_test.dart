import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/download_target.dart';
import 'package:lancloud/core/notifications.dart';
import 'package:lancloud/core/transfer/transfer_dependencies.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_settings_port.dart';

import 'support/transfer_manager_test_support.dart';

void main() {
  group('TransferManager 暂停与继续', () {
    test('should 将高频进度限制为每秒一次且完成时保留最终值', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'lancloud-transfer-progress',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final payload = List<int>.generate(128, (index) => index);
      final downloader = BurstProgressDownloader(payload);
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: FakeTransferStore(),
          accounts: FakeTransferAccountPort(),
          download: FakeTransferDownloadPort(tempDir.path),
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

      expect(task.received, 1);
      expect(notifications, beforeBurst + 1);

      downloader.finish.complete();
      await waitForTransferCondition(() => task.status == TransferStatus.done);
      expect(task.received, payload.length);
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
      final downloader = ExpiredLinkDownloader(payload);
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: FakeTransferStore(),
          accounts: FakeTransferAccountPort(),
          download: FakeTransferDownloadPort(tempDir.path),
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

      await waitForTransferCondition(() => task.status == TransferStatus.done);
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
          store: FakeTransferStore(),
          accounts: FakeTransferAccountPort(),
          download: FakeTransferDownloadPort(tempDir.path),
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
      final shared = BlockingSharedDownloads(payload.length);
      final notifications = RecordingNotificationSink();
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: FakeTransferStore(),
          accounts: FakeTransferAccountPort(),
          download: FakeTransferDownloadPort(
            tempDir.path,
            mode: DownloadTargetMode.sharedDownloads,
          ),
          settings: StoreTransferSettingsPort(SettingsStore()),
        ),
        notifications: notifications,
        downloader: ImmediateDownloader(payload),
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
      await waitForTransferCondition(() => task.received == 256);
      manager.pause(task.id);
      expect(task.status, TransferStatus.saving);

      shared.release.complete();
      await waitForTransferCondition(() => task.status == TransferStatus.done);
      expect(task.savedPath, 'content://saved/archive.zip');
    });
  });
}
