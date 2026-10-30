import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/notifications.dart';
import 'package:lancloud/core/notifications_provider.dart';

void main() {
  test('notificationServiceProvider 暴露应用唯一通知服务', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final first = container.read(notificationServiceProvider);
    final second = container.read(notificationServiceProvider);

    expect(identical(first, NotificationService.instance), isTrue);
    expect(identical(first, second), isTrue);
  });
}
