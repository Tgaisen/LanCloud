import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_log.dart';

/// 应用运行日志的 Riverpod 入口。
///
/// 日志初始化早于 ProviderContainer，因此入口固定暴露已初始化单例；
/// 应用级服务常驻，不使用 `autoDispose`。
final appLogProvider = Provider<AppLog>((ref) => AppLog.instance);
