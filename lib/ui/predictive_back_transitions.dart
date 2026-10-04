import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// 预测性返回时盖在「上一页」上的遮罩 key（便于测试定位）。
const ValueKey<String> kPredictiveBackScrimKey = ValueKey<String>(
  'predictive-back-scrim',
);

/// 与 Flutter 默认一致的全平台转场表，只把 Android 换成
/// [AospPredictiveBackPageTransitionsBuilder]。
const PageTransitionsTheme kLanCloudPageTransitionsTheme =
    PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: AospPredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
      },
    );

/// 仿 AOSP 设置应用的预测性返回动效。
///
/// Flutter 自带的 [PredictiveBackPageTransitionsBuilder] 只让当前页跟手缩放 /
/// 位移，被露出的上一页是原样显示的。这里在它的基础上给上一页盖一层黑色遮罩：
/// 手势刚开始（上一页只露出一个边）时最深，随手指继续滑动逐渐透明，滑到底时
/// 上一页完全清晰；中途松手取消，遮罩会随页面回位重新变深。
class AospPredictiveBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const AospPredictiveBackPageTransitionsBuilder({
    this.scrimColor = Colors.black,
    this.scrimOpacity = 0.32,
  });

  /// 遮罩颜色，默认黑色。
  final Color scrimColor;

  /// 手势刚开始时遮罩的不透明度（0~1）；0.32 与 Material 的 scrim 一致。
  final double scrimOpacity;

  @override
  Duration get transitionDuration =>
      const PredictiveBackPageTransitionsBuilder().transitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Widget inner = const PredictiveBackPageTransitionsBuilder()
        .buildTransitions<T>(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
    // 注意：必须保持组件结构恒定——始终包一层 PredictiveBackScrim，只用
    // enabled 控制画不画。预测性返回的 phase（start/update/commit/cancel）
    // 记在 Flutter 的 _PredictiveBackGestureDetector State 里，如果手势开始
    // 或提交时在这里增删包装层，它的 State 会被重建，commit 阶段丢失，
    // 松手后页面就会「直接消失」而不是播放返回动画。
    //
    // 被露出的「上一页」用 secondaryAnimation 判定：它正是上方路由的动画值
    // （手势开始 1 → 滑到底 0），被拖动的那一页自身 secondaryAnimation 是
    // dismissed，所以只有上一页会画遮罩；非手势返回不加。
    return PredictiveBackScrim(
      progress: secondaryAnimation,
      color: scrimColor,
      maxOpacity: scrimOpacity,
      enabled: route.popGestureInProgress && !secondaryAnimation.isDismissed,
      child: inner,
    );
  }
}

/// 盖在上一页上的遮罩：不透明度 = [maxOpacity] × [progress] × [enabled]。
///
/// 无论 [enabled] 与否，组件结构都保持不变（只增删最上层的 [ColoredBox]），
/// 避免重建子树导致预测性返回的手势状态丢失。
class PredictiveBackScrim extends StatelessWidget {
  const PredictiveBackScrim({
    super.key,
    required this.progress,
    required this.color,
    required this.maxOpacity,
    required this.enabled,
    required this.child,
  });

  /// 手势剩余进度：手势开始 1 → 滑到底 0。
  final Animation<double> progress;

  final Color color;
  final double maxOpacity;

  /// 当前是否处于「被预测性返回手势露出」的状态。
  final bool enabled;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (BuildContext context, Widget? child) {
        final double alpha = enabled
            ? (maxOpacity * progress.value).clamp(0.0, 1.0)
            : 0.0;
        return Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            child!,
            if (alpha > 0.004)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    key: kPredictiveBackScrimKey,
                    color: color.withValues(alpha: alpha),
                  ),
                ),
              ),
          ],
        );
      },
      child: child,
    );
  }
}
