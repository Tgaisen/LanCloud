import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_cache.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/notifications.dart';
import 'package:lancloud/core/transfer/transfer_dependencies.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_settings_port.dart';
import 'package:path/path.dart' as p;

import 'support/transfer_manager_test_support.dart';

void main() {
  group('TransferManager 暂停与继续', () {
    test('should 上传完成后删除临时源副本并保留普通文件', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final cacheDir = Directory.systemTemp.createTempSync(
        'lancloud-upload-cache',
      );
      final originalDir = Directory.systemTemp.createTempSync(
        'lancloud-upload-original',
      );
      AppCache.directoryProvider = () async => cacheDir;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        AppCache.directoryProvider = null;
        for (final dir in [cacheDir, originalDir]) {
          try {
            dir.deleteSync(recursive: true);
          } catch (_) {}
        }
      });
      final cached = File(
        p.join(cacheDir.path, 'file_picker', 'picked', 'cached.zip'),
      )..createSync(recursive: true);
      final original = File(p.join(originalDir.path, 'original.zip'))
        ..writeAsStringSync('original');
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: FakeTransferStore(),
          accounts: ImmediateUploadAccountPort(),
          download: const FakeTransferDownloadPort(''),
          settings: StoreTransferSettingsPort(SettingsStore()),
        ),
      );
      addTearDown(manager.dispose);

      manager.addUpload(
        name: 'cached.zip',
        folderId: '-1',
        path: cached.path,
        size: 1,
      );
      await waitForTransferCondition(
        () =>
            manager.tasks.single.status == TransferStatus.done &&
            !cached.existsSync(),
      );

      manager.addUpload(
        name: 'original.zip',
        folderId: '-1',
        path: original.path,
        size: original.lengthSync(),
      );
      await waitForTransferCondition(
        () =>
            manager.tasks.length == 2 &&
            manager.tasks.last.status == TransferStatus.done,
      );

      expect(cached.existsSync(), isFalse);
      expect(original.existsSync(), isTrue);
    });

    test('should 删除失败上传记录时释放临时源副本', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final cacheDir = Directory.systemTemp.createTempSync(
        'lancloud-upload-cache',
      );
      AppCache.directoryProvider = () async => cacheDir;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        AppCache.directoryProvider = null;
        try {
          cacheDir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final cached = File(p.join(cacheDir.path, 'picked', 'failed.zip'))
        ..createSync(recursive: true);
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: FakeTransferStore(),
          accounts: FakeTransferAccountPort(),
          download: const FakeTransferDownloadPort(''),
          settings: StoreTransferSettingsPort(SettingsStore()),
        ),
      );
      addTearDown(manager.dispose);
      manager.tasks.add(
        TransferTask(
          id: 'failed-upload',
          kind: TransferKind.upload,
          name: 'failed.zip',
          accountUid: '',
          localFilePath: cached.path,
        )..status = TransferStatus.failed,
      );

      manager.removeTask('failed-upload');
      await waitForTransferCondition(() => !cached.existsSync());

      expect(manager.tasks, isEmpty);
      expect(cached.existsSync(), isFalse);
    });

    test('should 上传中取消后等待请求停止并释放临时源副本', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final cacheDir = Directory.systemTemp.createTempSync(
        'lancloud-upload-cancel',
      );
      AppCache.directoryProvider = () async => cacheDir;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        AppCache.directoryProvider = null;
        try {
          cacheDir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final cached = File(p.join(cacheDir.path, 'picked', 'cancel.zip'))
        ..createSync(recursive: true);
      final accounts = BlockingUploadAccountPort();
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: FakeTransferStore(),
          accounts: accounts,
          download: const FakeTransferDownloadPort(''),
          settings: StoreTransferSettingsPort(SettingsStore()),
        ),
      );
      addTearDown(manager.dispose);

      manager.addUpload(
        name: 'cancel.zip',
        folderId: '-1',
        path: cached.path,
        size: 1,
      );
      final task = manager.tasks.single;
      await accounts.client.started.future;
      expect(cached.existsSync(), isTrue);

      manager.removeTask(task.id);
      await waitForTransferCondition(() => !cached.existsSync());

      expect(task.status, TransferStatus.canceled);
      expect(manager.tasks, isEmpty);
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
        downloader: const FailingDownloader(),
      );
      addTearDown(manager.dispose);

      manager.addDownload(url: 'https://cdn.example/file', name: 'archive.zip');
      final task = manager.tasks.single;
      await waitForTransferCondition(
        () => task.status == TransferStatus.failed,
      );

      final failed = notifications.snapshots.last;
      expect(failed.taskId, task.id);
      expect(failed.state, TransferNotificationState.failed);
      expect(failed.error, isNotEmpty);
    });
  });
}
