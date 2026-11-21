import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/notifications.dart';
import 'package:lancloud/core/platform_capabilities.dart';

void main() {
  group('NotificationService', () {
    test('应该按平台能力暴露静态通知支持', () {
      for (final (:name, :capabilities, :supported) in [
        (
          name: 'Android',
          capabilities: PlatformCapabilities.android,
          supported: true,
        ),
        (
          name: 'Windows',
          capabilities: PlatformCapabilities.windows,
          supported: true,
        ),
        (name: 'iOS', capabilities: PlatformCapabilities.ios, supported: false),
        (
          name: 'macOS',
          capabilities: PlatformCapabilities.macOS,
          supported: false,
        ),
        (
          name: 'Linux',
          capabilities: PlatformCapabilities.linux,
          supported: false,
        ),
        (
          name: 'unknown',
          capabilities: PlatformCapabilities.unsupported,
          supported: false,
        ),
      ]) {
        final service = NotificationService(capabilities: capabilities);
        expect(service.supported, supported, reason: name);
      }
    });

    test('不支持的平台应该在接触插件前 fail closed', () async {
      final service = NotificationService(
        capabilities: PlatformCapabilities.ios,
      );

      await service.init(null);
      await service.consumeLaunchDetails();
      expect(service.ready, isFalse);
      expect(await service.hasPermission(), isFalse);
      expect(await service.requestPermission(), isFalse);

      service.showTransferTask(
        const TransferNotificationSnapshot(
          taskId: 'task',
          name: 'file.zip',
          kind: TransferNotificationKind.download,
          state: TransferNotificationState.downloading,
          received: 1,
          total: 2,
        ),
      );
      service.cancelTransferTask('task');
      await service.showFavoriteCheckProgress(
        title: '检测',
        completed: 1,
        total: 2,
        name: '收藏夹',
      );
      await service.showFavoriteFolderUpdate(
        ref: 'https://share.example/folder',
        name: '收藏夹',
        time: '刚刚',
      );
      await service.showWebdavBackupProgress();
    });
  });
}
