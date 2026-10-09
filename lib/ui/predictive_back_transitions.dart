import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoPageTransitionsBuilder;
import 'package:flutter/services.dart' show PredictiveBackEvent;
import 'package:material_ui/material_ui.dart';

import 'reduce_motion.dart';

/// 各平台二级页面进出的转场（不含「系统要求少动效」包装，便于测试断言）：
///
/// * PC（Windows / Linux）：Flutter 默认的 [ZoomPageTransitionsBuilder]，
///   淡入 + 轻微缩放，保持原样；
/// * Android / iOS（以及 macOS）：[CupertinoPageTransitionsBuilder]，即 iOS 式
///   视差——进入时新页面从右侧滑入、旧页面以约 1/3 的速度让位，返回时反向；
///   Android 上额外保留「返回手势跟手」，见
///   [CupertinoPredictiveBackPageTransitionsBuilder]。
const Map<TargetPlatform, PageTransitionsBuilder>
kLanCloudPageTransitionBuilders = <TargetPlatform, PageTransitionsBuilder>{
  TargetPlatform.android: CupertinoPredictiveBackPageTransitionsBuilder(),
  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
  TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
  TargetPlatform.windows: ZoomPageTransitionsBuilder(),
  TargetPlatform.linux: ZoomPageTransitionsBuilder(),
};

/// 应用统一的转场表：在 [kLanCloudPageTransitionBuilders] 外统一套一层
/// 「系统要求少动效时直接跳过转场」的处理（见 [_ReduceMotionBuilder]）。
final PageTransitionsTheme kLanCloudPageTransitionsTheme = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    for (final MapEntry<TargetPlatform, PageTransitionsBuilder> entry
        in kLanCloudPageTransitionBuilders.entries)
      entry.key: _ReduceMotionBuilder(entry.value),
  },
);

/// 系统开了「移除动画」/「减弱动态效果」（或读屏接管交互）时，
/// 页面转场直接返回原样的子树——新页面立即到位，不做位移 / 缩放 / 淡入。
class _ReduceMotionBuilder extends PageTransitionsBuilder {
  const _ReduceMotionBuilder(this.delegate);

  final PageTransitionsBuilder delegate;

  @override
  Duration get transitionDuration => delegate.transitionDuration;

  @override
  Duration get reverseTransitionDuration => delegate.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition {
    final delegated = delegate.delegatedTransition;
    if (delegated == null) return null;
    return (context, animation, secondaryAnimation, allowSnapshotting, child) {
      if (reduceMotionOf(context)) return child;
      return delegated(
        context,
        animation,
        secondaryAnimation,
        allowSnapshotting,
        child,
      );
    };
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotionOf(context)) return child;
    return delegate.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

/// iOS 视差转场 + Android 返回手势跟手。
///
/// 框架自带的 [PredictiveBackPageTransitionsBuilder] 把「手势检测」和它的
/// Android 共享元素转场写死在一起：直接换成 [CupertinoPageTransitionsBuilder]
/// 的话，就没有人再处理 `flutter/backgesture` 事件、驱动路由动画，侧滑返回会
/// 退化成「手指拖动时页面不动、松手才整页播放动画」。这里用公开的
/// [PredictiveBackRoute] 接口复刻那份手势检测
/// （见 [_CupertinoBackGestureDetector]），视觉仍然交给 Cupertino，
/// 于是 Android 也能一边跟手一边播放 iOS 视差。
class CupertinoPredictiveBackPageTransitionsBuilder
    extends PageTransitionsBuilder {
  const CupertinoPredictiveBackPageTransitionsBuilder();

  static const CupertinoPageTransitionsBuilder _cupertino =
      CupertinoPageTransitionsBuilder();

  @override
  Duration get transitionDuration => _cupertino.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      _cupertino.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      _cupertino.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _CupertinoBackGestureDetector(
      route: route,
      routeDuration: transitionDuration,
      child: _cupertino.buildTransitions<T>(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      ),
    );
  }
}

/// 把 Android 的预测性返回事件翻译成「驱动当前路由的动画」。
///
/// 与框架内的同名实现保持一致：只有顶层、且允许返回手势
/// （[PredictiveBackRoute.popGestureEnabled]）的路由才接管事件；返回 false 时
/// 框架会按普通返回兜底——提交手势时走 `handlePopRoute`，一样能出栈。
/// 硬件返回键（[PredictiveBackEvent.isButtonEvent]）不跟手，也交给框架兜底。
///
/// 这里只负责把事件翻译成路由动画（跟手、提交时补完剩余行程），
/// 具体的位移 / 视差画面由 [CupertinoPageTransitionsBuilder] 按动画值渲染。
class _CupertinoBackGestureDetector extends StatefulWidget {
  const _CupertinoBackGestureDetector({
    required this.route,
    required this.routeDuration,
    required this.child,
  });

  final PageRoute<dynamic> route;

  /// 转场总时长：松手后补完「剩余行程」按它等比缩放。
  final Duration routeDuration;

  final Widget child;

  @override
  State<_CupertinoBackGestureDetector> createState() =>
      _CupertinoBackGestureDetectorState();
}

class _CupertinoBackGestureDetectorState
    extends State<_CupertinoBackGestureDetector>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 松手提交时补完剩余行程用的动画（见 [handleCommitBackGesture]）。
  AnimationController? _finish;

  bool get _isEnabled =>
      widget.route.isCurrent && widget.route.popGestureEnabled;

  /// 系统给的是「往回走了多远」（0 → 1），路由动画要的是「当前页还剩多少」
  /// （1 → 0），所以要反过来。
  double _routeProgress(PredictiveBackEvent event) => 1 - event.progress;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent || !_isEnabled) {
      return false;
    }
    _finish?.dispose();
    _finish = null;
    widget.route.handleStartBackGesture(progress: _routeProgress(backEvent));
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    widget.route.handleUpdateBackGestureProgress(
      progress: _routeProgress(backEvent),
    );
  }

  @override
  void handleCancelBackGesture() => widget.route.handleCancelBackGesture();

  /// 提交手势：先把没走完的那段行程补完，再交给框架出栈。
  ///
  /// 直接调 [PredictiveBackRoute.handleCommitBackGesture] 的话，框架会
  /// pop（路由动画从当前值 reverse 到 0）之后又 `reverse(from: 1.0)` 把整段
  /// 退场动画重播一遍——对只按动画值渲染的 Cupertino 转场来说，就是「手指
  /// 拖出去大半、一松手先弹回原位再滑走」。这里先把路由动画线性推到 0
  /// （速度 = 整屏行程 / 默认转场时长，与跟手时一致），框架随后 pop 时动画
  /// 已经在终点，会跳过重播（源码注释：the popping may have finished inline
  /// if already at the target destination），页面从松手的位置继续滑出。
  @override
  void handleCommitBackGesture() {
    final double remaining = widget.route.animation?.value ?? 0;
    if (remaining <= 0) {
      widget.route.handleCommitBackGesture();
      return;
    }
    _finish?.dispose();
    final AnimationController finish = AnimationController(
      vsync: this,
      duration: Duration(
        microseconds: math.max(
          const Duration(milliseconds: 100).inMicroseconds,
          (widget.routeDuration.inMicroseconds * remaining).round(),
        ),
      ),
    );
    _finish = finish;
    finish.addListener(() {
      widget.route.handleUpdateBackGestureProgress(
        progress: remaining * (1 - finish.value),
      );
    });
    finish.addStatusListener((AnimationStatus status) {
      if (status != AnimationStatus.completed || !mounted) return;
      widget.route.handleCommitBackGesture();
    });
    finish.forward();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _finish?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
