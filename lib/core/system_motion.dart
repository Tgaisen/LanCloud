import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 系统是否要求「移除动画」/「少动效」，由原生侧读系统设置报告。
///
/// 两项依据：
/// - `reduceMotion`：`transition_animation_scale` / `window_animation_scale` /
///   `animator_duration_scale` 任一为 0。Flutter 的
///   [MediaQueryData.disableAnimations] 在 Android 上只跟
///   `transition_animation_scale` 走，而部分 ROM（例如华为）的无障碍开关
///   「移除动画」只改另外两个，引擎那边读不到，于是页面转场、列表入场照播。
/// - `touchExploration`：真正的读屏软件（TalkBack / 屏幕朗读）接管了触摸探索。
///   **不能**用引擎的 [MediaQueryData.accessibleNavigation]：那个标志是「有
///   无障碍服务查过一次语义树」就会被置位（自动记账 / 自动填表这类服务也会），
///   拿它当少动效会让「随便开个无障碍服务 = 全应用没有动画」。
///
/// 两者变化时由原生推送，Dart 侧不需要轮询。
class SystemMotion {
  SystemMotion._();

  static const MethodChannel _channel = MethodChannel('lancloud/system');

  /// 动画缩放表明「系统要求移除动画」，变化时触发全局重建（见 `LanCloudApp`）。
  static final ValueNotifier<bool> reduceMotion = ValueNotifier<bool>(false);

  /// 读屏软件接管交互（触摸探索开启），同样应该少动效。
  static final ValueNotifier<bool> touchExploration = ValueNotifier<bool>(
    false,
  );

  static bool _initialized = false;

  /// 启动时调用一次：注册原生推送 + 立刻读一次当前状态。
  static void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'motionStateChanged') {
        _apply(call.arguments);
      }
      return null;
    });
    WidgetsBinding.instance.addObserver(_LifecycleObserver());
    unawaited(refresh());
  }

  /// 重新读一次（启动 / 回到前台；非 Android 平台没有这个通道，保持默认）。
  static Future<void> refresh() async {
    try {
      _apply(await _channel.invokeMethod<dynamic>('motionState'));
    } catch (_) {
      // 通道不可用（桌面 / Web / 测试环境）：维持 MediaQuery 那一套判断
    }
  }

  static void _apply(dynamic state) {
    if (state is! Map) return;
    final reduce = state['reduceMotion'];
    final touch = state['touchExploration'];
    if (reduce is bool) reduceMotion.value = reduce;
    if (touch is bool) touchExploration.value = touch;
  }
}

/// 回到前台时重新读一次：用户可能刚从系统设置里改了「移除动画」。
class _LifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(SystemMotion.refresh());
  }
}
