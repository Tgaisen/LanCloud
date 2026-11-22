import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/transfer/transfer_dependencies.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_settings_port.dart';

import 'support/transfer_manager_test_support.dart';

void main() {
  group('TransferManager 暂停与继续', () {
    test('should 批量暂停下载且忽略上传、已暂停和保存中的任务', () {
      final settings = SettingsStore()..maxDownloads = 0;
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: FakeTransferStore(),
          accounts: FakeTransferAccountPort(),
          download: const FakeTransferDownloadPort(''),
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
          store: FakeTransferStore(),
          accounts: FakeTransferAccountPort(),
          download: const FakeTransferDownloadPort(''),
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

    test('should 分别只清空指定类型的已完成与失败任务', () {
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: FakeTransferStore(),
          accounts: FakeTransferAccountPort(),
          download: const FakeTransferDownloadPort(''),
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

      final completed = manager.clearCompleted(TransferKind.upload);

      expect(completed.map((task) => task.id), ['u-done']);
      expect(manager.tasks.map((task) => task.id), [
        'u-failed',
        'u-active',
        'd-done',
      ]);

      final failed = manager.clearFailed(TransferKind.upload);

      expect(failed.map((task) => task.id), ['u-failed']);
      expect(manager.tasks.map((task) => task.id), ['u-active', 'd-done']);
    });
  });
}
