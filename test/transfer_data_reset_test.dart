import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/transfer/transfer_dependencies.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_settings_port.dart';

import 'support/transfer_manager_test_support.dart';

void main() {
  test('删除所有数据会取消运行中与排队中的全部传输', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'lancloud-transfer-reset',
    );
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
    final downloader = PausingDownloader(List<int>.filled(1024, 7));
    final notifications = RecordingNotificationSink();
    final manager = TransferManager.withDependencies(
      TransferDependencies(
        store: FakeTransferStore(),
        accounts: FakeTransferAccountPort(),
        download: FakeTransferDownloadPort(tempDir.path),
        settings: StoreTransferSettingsPort(SettingsStore()..maxDownloads = 1),
      ),
      notifications: notifications,
      downloader: downloader,
    );
    addTearDown(manager.dispose);

    manager.addDownload(
      url: 'https://cdn.example/first.zip',
      name: 'first.zip',
    );
    manager.addDownload(
      url: 'https://cdn.example/second.zip',
      name: 'second.zip',
    );
    await downloader.started.future;
    expect(manager.hasActiveTransfers, isTrue);
    expect(manager.tasks, hasLength(2));
    final ids = manager.tasks.map((task) => task.id).toList();

    await manager.cancelAllForDataReset();

    expect(manager.hasActiveTransfers, isFalse);
    expect(manager.tasks, isEmpty);
    expect(notifications.cancellations, containsAll(ids));
  });
}
