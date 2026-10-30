import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifications.dart';

/// 应用通知服务的 Riverpod 入口。
///
/// 通知插件在创建 ProviderContainer 前初始化，入口固定暴露已初始化单例；
/// 应用级服务常驻，不使用 `autoDispose`。
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService.instance,
);
