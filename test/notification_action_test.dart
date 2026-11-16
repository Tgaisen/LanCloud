import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/favorites/favorite_monitor_reporter.dart';
import 'package:lancloud/core/favorites/favorite_monitor_reporter_adapter.dart';
import 'package:lancloud/core/notifications.dart';
import 'package:lancloud/l10n/l10n.dart';
import 'package:lancloud/l10n/app_localizations_zh.dart';

void main() {
  test('收藏检测进度通知区分更新与失效项目', () {
    final strings = AppLocalizationsZh();
    expect(
      favoriteCheckProgressTitle(FavoriteCheckOperation.folderUpdates, strings),
      '正在检测收藏夹更新',
    );
    expect(
      favoriteCheckProgressTitle(FavoriteCheckOperation.shareAccess, strings),
      '正在检测收藏夹失效项目',
    );
  });

  group('NotificationAction', () {
    test('should 保持旧版 transfers payload 兼容', () {
      final action = NotificationAction.decode('transfers');

      expect(action, isNotNull);
      expect(action!.kind, NotificationActionKind.transfers);
      expect(action.encode(), 'transfers');
    });

    test('should 原样还原 Windows 路径和中文文件名', () {
      final action = NotificationAction.openFile(
        path: r'C:\Users\Potato\Downloads\蓝云 报告.docx',
        name: '蓝云 报告.docx',
      );

      final decoded = NotificationAction.decode(action.encode());

      expect(decoded, isNotNull);
      expect(decoded!.kind, NotificationActionKind.openFile);
      expect(decoded.path, r'C:\Users\Potato\Downloads\蓝云 报告.docx');
      expect(decoded.name, '蓝云 报告.docx');
    });

    test('should 原样还原 Android content URI', () {
      final action = NotificationAction.openFile(
        path: 'content://doc/primary%3ADownload%2Fapp.apk',
        name: 'app.apk',
      );

      final decoded = NotificationAction.decode(action.encode());

      expect(decoded?.path, 'content://doc/primary%3ADownload%2Fapp.apk');
      expect(decoded?.name, 'app.apk');
    });

    test('should 还原收藏文件夹点击动作', () {
      final action = NotificationAction.favoriteFolder(
        ref: 'https://share.example/folder',
      );

      final decoded = NotificationAction.decode(action.encode());

      expect(decoded, isNotNull);
      expect(decoded!.kind, NotificationActionKind.favoriteFolder);
      expect(decoded.ref, 'https://share.example/folder');
    });

    test('should 忽略未知或损坏的 payload', () {
      expect(NotificationAction.decode(null), isNull);
      expect(NotificationAction.decode(''), isNull);
      expect(NotificationAction.decode('{bad json'), isNull);
      expect(NotificationAction.decode('{"action":"openFile"}'), isNull);
      expect(NotificationAction.decode('{"action":"unknown"}'), isNull);
    });
  });

  test('任务通知 ID 对同一任务稳定，不同任务相互独立', () {
    final first = NotificationService.notificationIdFor('d1760000000000_1');
    final again = NotificationService.notificationIdFor('d1760000000000_1');
    final second = NotificationService.notificationIdFor('d1760000000000_2');

    expect(first, again);
    expect(first, isNot(second));
    expect(first, greaterThanOrEqualTo(10000));
  });

  test('收藏更新通知 ID 对同一分享稳定，不同分享相互独立', () {
    final first = NotificationService.favoriteFolderNotificationIdFor(
      'https://share.example/a',
    );
    final again = NotificationService.favoriteFolderNotificationIdFor(
      'https://share.example/a',
    );
    final second = NotificationService.favoriteFolderNotificationIdFor(
      'https://share.example/b',
    );

    expect(first, again);
    expect(first, isNot(second));
    expect(first, inInclusiveRange(1100000000, 1139999999));
    expect(
      first,
      isNot(NotificationService.favoriteCheckProgressNotificationId),
    );
  });

  test('失败通知区分上传下载且不重复失败前缀', () {
    final zh = lookupAppLocalizations(const Locale('zh'));
    final en = lookupAppLocalizations(const Locale('en'));

    expect(
      NotificationService.failureBodyFor(
        kind: TransferNotificationKind.upload,
        error: '失败：上传失败：server busy',
        strings: zh,
      ),
      '上传失败：server busy',
    );
    expect(
      NotificationService.failureBodyFor(
        kind: TransferNotificationKind.download,
        error: '失败：获取下载地址失败：HTTP 403',
        strings: zh,
      ),
      '下载失败：HTTP 403',
    );
    expect(
      NotificationService.failureBodyFor(
        kind: TransferNotificationKind.upload,
        error: 'Failed: Upload failed: server busy',
        strings: en,
      ),
      'Upload failed: server busy',
    );
  });
}
