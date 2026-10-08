import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 系统是否要求「移除动画」。
///
/// Flutter 的 [MediaQueryData.disableAnimations] 在 Android 上只跟
/// `transition_animation_scale` 走，而部分 ROM（例如华为）的无障碍开关
/// 「移除动画」只改 `window_animation_scale` / `animator_duration_scale`，
/// 引擎那边读不到，于是页面转场、列表入场照播。
///
/// 这里直接问原生要三个动画缩放的合并结果，并在开关变化时由原生推送，
/// 与 [MediaQueryData.disableAnimations] 是「或」的关系
/// （见 `ui/reduce_motion.dart`）。
class SystemMotion {
  SystemMotion._();

  static const MethodChannel _channel = MethodChannel('lancloud/system');

  /// 原生报告的「系统要求少动效」，变化时触发全局重建（见 `LanCloudApp`）。
  static final ValueNotifier<bool> reduceMotion = ValueNotifier<bool>(false);

  static bool _initialized = false;

  /// 启动时调用一次：注册原生推送 + 立刻读一次当前状态。
  static void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'reduceMotionChanged') {
        final value = call.arguments;
        if (value is bool) reduceMotion.value = value;
      }
      return null;
    });
    WidgetsBinding.instance.addObserver(_LifecycleObserver());
    unawaited(refresh());
  }

  /// 重新读一次（启动 / 回到前台；非 Android 平台没有这个通道，保持默认）。
  static Future<void> refresh() async {
    try {
      final value = await _channel.invokeMethod<bool>('reduceMotion');
      if (value != null) reduceMotion.value = value;
    } catch (_) {
      // 通道不可用（桌面 / Web / 测试环境）：维持 MediaQuery 那一套判断
    }
  }
}

/// 回到前台时重新读一次：用户可能刚从系统设置里改了「移除动画」。
class _LifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(SystemMotion.refresh());
  }
}
