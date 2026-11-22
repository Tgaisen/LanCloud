import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/notifications.dart';
import 'package:lancloud/core/transfer/transfer_dependencies.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_settings_port.dart';

import 'support/transfer_manager_test_support.dart';

void main() {
  group('TransferManager 暂停与继续', () {
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
      final notifications = RecordingNotificationSink();
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: FakeTransferStore(),
          accounts: FakeTransferAccountPort(),
          download: FakeTransferDownloadPort(tempDir.path),
          settings: StoreTransferSettingsPort(
            SettingsStore()
              ..maxDownloads = 1
              ..notifyProgress = false
              ..notifyDone = true,
          ),
        ),
        notifications: notifications,
        downloader: ImmediateDownloader(payload),
      );
      addTearDown(manager.dispose);

      manager.addDownload(
        url: 'https://cdn.example/file',
        name: 'archive.zip',
        size: payload.length,
      );
      final task = manager.tasks.single;
      await waitForTransferCondition(() => task.status == TransferStatus.done);

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
      final notifications = RecordingNotificationSink();
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: FakeTransferStore(),
          accounts: FakeTransferAccountPort(),
          download: FakeTransferDownloadPort(tempDir.path),
          settings: StoreTransferSettingsPort(
            SettingsStore()
              ..maxDownloads = 1
              ..notifyProgress = true
              ..notifyDone = false,
          ),
        ),
        notifications: notifications,
        downloader: ImmediateDownloader(payload),
      );
      addTearDown(manager.dispose);

      manager.addDownload(
        url: 'https://cdn.example/file',
        name: 'archive.zip',
        size: payload.length,
      );
      final task = manager.tasks.single;
      await waitForTransferCondition(() => task.status == TransferStatus.done);

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
      final downloader = PausingDownloader(payload);
      final notifications = RecordingNotificationSink();
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: FakeTransferStore(),
          accounts: FakeTransferAccountPort(),
          download: FakeTransferDownloadPort(tempDir.path),
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
      final notifications = RecordingNotificationSink();
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: FakeTransferStore(),
          accounts: ImmediateUploadAccountPort(),
          download: const FakeTransferDownloadPort(''),
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
      await waitForTransferCondition(() => task.status == TransferStatus.done);

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
  });
}
