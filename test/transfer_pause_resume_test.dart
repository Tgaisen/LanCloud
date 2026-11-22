import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/notifications.dart';
import 'package:lancloud/core/transfer/transfer_dependencies.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_settings_port.dart';
import 'package:path/path.dart' as p;

import 'support/transfer_manager_test_support.dart';

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
      final downloader = PausingDownloader(payload);
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

      await waitForTransferCondition(() => task.status == TransferStatus.done);
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
        downloader: ImmediateDownloader(payload),
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

      await waitForTransferCondition(() => task.status == TransferStatus.done);
      expect(task.url, 'https://cdn.example/archive.zip');
      expect(await File(task.savedPath!).readAsBytes(), payload);
    });
  });
}
