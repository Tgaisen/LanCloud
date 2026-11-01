import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/notifications.dart';

void main() {
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

    test('should 忽略未知或损坏的 payload', () {
      expect(NotificationAction.decode(null), isNull);
      expect(NotificationAction.decode(''), isNull);
      expect(NotificationAction.decode('{bad json'), isNull);
      expect(NotificationAction.decode('{"action":"openFile"}'), isNull);
      expect(NotificationAction.decode('{"action":"unknown"}'), isNull);
    });
  });
}
