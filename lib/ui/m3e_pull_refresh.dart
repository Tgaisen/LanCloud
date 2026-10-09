// 方案 A（Bouncing + M3E overlay 版下拉刷新）。
//
// 和 m3e_core 的 M3EPullToRefreshIndicator 的区别：
// - 内容位移只有一个 writer：滚动 physics。不再用 SizedBox 顶内容、不加改变
//   extent 的 header；iOS 橡皮筋原样保留（顶栏不透明，不需要内容从它下面穿过）。
// - 指示器只有一个 writer：_progress 控制器。拖动阶段直接跟随手指，松手后交给
//   自己的 spring；固定在上边缘的 overlay 里，不参与列表布局、不随回弹移动，
//   于是不会出现「小球 + 一层回弹留白」的双重位移。
// - 手势只有一个 owner：Scrollable。指示器是 IgnorePointer 的纯视觉层。
//
// 为什么不用 M3EPullToRefreshIndicator：它的 header 是 Column 里的一段实体空间，
// 会和 Bouncing 的越界位移叠加；而且它只处理 overscroll < 0（下拉）与
// scrollDelta > 0（靠列表滚动来收小球），反向拖动没法只收小球。

import 'package:flutter/physics.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';

/// 和 [BouncingScrollPhysics] 共存的下拉刷新指示器（MD3E 视觉）。
///
/// 用法（physics 用全局默认的 Bouncing + AlwaysScrollable 即可，短列表也能拉）：
/// ```dart
/// M3ePullToRefresh(
///   onRefresh: _reload,
///   edgeOffset: headerInset,
///   semanticsLabel: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
///   child: CustomScrollView(...),
/// )
/// ```
///
/// 只支持正向的纵向列表（`AxisDirection.down`）。
class M3ePullToRefresh extends StatefulWidget {
  const M3ePullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.enabled = true,
    this.onError,
    this.triggerDistance = 80.0,
    this.indicatorHeight = 70.0,
    this.edgeOffset = 0.0,
    this.maxDragMultiplier = 1.8,
    this.triggerMode = RefreshIndicatorTriggerMode.anywhere,
    this.springMotion = M3EMotion.expressiveSpatialDefault,
    this.cancelMotion = M3EMotion.expressiveEffectsFast,
    this.hapticFeedback = M3EHapticFeedback.medium,
    this.minimumDisplayDuration = const Duration(milliseconds: 200),
    this.semanticsLabel,
    this.semanticsValue,
    this.notificationPredicate,
    this.indicatorBuilder,
  }) : assert(triggerDistance > 0.0),
       assert(maxDragMultiplier >= 1.0);

  /// 刷新回调；Future 完成前指示器保持显示。
  final Future<void> Function() onRefresh;

  /// 纵向滚动的 child（ListView / CustomScrollView / GridView）。
  final Widget child;

  /// 为 false 时不响应新的下拉（页面自己正在加载时用，避免两个指示器同时出现）；
  /// 已经在拉的过程不受影响，照常按松手时机结算。
  final bool enabled;

  /// [onRefresh] 抛错时回调；不传则错误被吞掉。
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// 触发刷新需要的内容位移（px）。数值是设计决策（M3 只要求「有阈值、
  /// 反向超过阈值要取消」）；默认 80，和 m3e 组件一致。
  final double triggerDistance;

  /// 指示器完全露出后占用的高度（px），默认 70，和 m3e 组件一致。
  final double indicatorHeight;

  /// 顶部预留偏移（浮层顶栏 / 路径栏遮挡时用）。
  final double edgeOffset;

  /// 过拉上限 = triggerDistance × maxDragMultiplier。
  final double maxDragMultiplier;

  /// 什么时候接管手势（沿用 `RefreshIndicator` 的语义）：
  /// - [RefreshIndicatorTriggerMode.anywhere]（默认）：手指按住时，只要这次
  ///   拖动到达顶部（`extentBefore == 0`）就接管，列表不在顶部时一路拖回顶部
  ///   并继续下拉也能出小球；
  /// - [RefreshIndicatorTriggerMode.onEdge]：只有起手就在顶部才接管。
  final RefreshIndicatorTriggerMode triggerMode;

  /// 松手吸附到「已就绪」位置的弹簧（位移，允许轻微 overshoot）。
  final M3EMotion springMotion;

  /// 取消 / 刷新结束收回时的弹簧（不 overshoot）。
  final M3EMotion cancelMotion;

  /// 越过阈值瞬间的触觉反馈，默认 medium（和 m3e 组件一致）。
  final M3EHapticFeedback hapticFeedback;

  /// 刷新返回太快时指示器至少再停留一会儿，避免闪一下。
  final Duration minimumDisplayDuration;

  /// 刷新中的无障碍语义（本地化文案）。
  final String? semanticsLabel;
  final String? semanticsValue;

  /// 过滤参与手势的 [ScrollNotification]，默认只认最近一层（depth == 0）。
  final bool Function(ScrollNotification notification)? notificationPredicate;

  /// 自定义指示器视觉；默认 [M3EContainedLoadingIndicator]。
  final Widget Function(BuildContext context, double progress, bool refreshing)?
  indicatorBuilder;

  @override
  State<M3ePullToRefresh> createState() => _M3ePullToRefreshState();
}

enum _Phase { idle, drag, armed, refreshing }

/// 小于该值时认为指示器已经完全收回（spring 不会精确落在 0）。
const double _kHiddenEpsilon = 1e-3;

class _M3ePullToRefreshState extends State<M3ePullToRefresh>
    with SingleTickerProviderStateMixin {
  /// 无界 master：过拉时可以 >1，settle 时用 spring 回到目标值。
  late final AnimationController _progress = AnimationController.unbounded(
    vsync: this,
    value: 0.0,
  );

  _Phase _phase = _Phase.idle;
  double _pull = 0.0;
  bool _hapticFired = false;
  int _animToken = 0;

  bool get _isRefreshing => _phase == _Phase.refreshing;
  bool get _isPulling => _phase == _Phase.drag || _phase == _Phase.armed;
  double get _maxPull => widget.triggerDistance * widget.maxDragMultiplier;

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  bool _accepts(ScrollNotification notification) {
    final predicate = widget.notificationPredicate;
    return predicate != null
        ? predicate(notification)
        : notification.depth == 0;
  }

  bool _startsPull(ScrollNotification notification) {
    if (!widget.enabled || _phase != _Phase.idle) {
      return false;
    }
    final ScrollMetrics metrics = notification.metrics;
    if (metrics.axisDirection != AxisDirection.down ||
        metrics.extentBefore != 0.0) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      return notification.dragDetails != null;
    }
    // anywhere：起手不在顶部，但手指还按着，并且这次拖动已经到达顶部。
    return widget.triggerMode == RefreshIndicatorTriggerMode.anywhere &&
        notification is ScrollUpdateNotification &&
        notification.dragDetails != null;
  }

  /// Bouncing 下越界时 pixels 会小于 minScrollExtent：起手 / 接管的那一刻
  /// 可能已经有越界位移（例如快速拖过顶部只报一帧），直接换算成初始拉力。
  double _initialPull(ScrollMetrics metrics) =>
      (metrics.minScrollExtent - metrics.pixels).clamp(0.0, _maxPull);

  bool _onScroll(ScrollNotification notification) {
    if (!_accepts(notification) || _isRefreshing) {
      return false;
    }

    if (_startsPull(notification)) {
      _hapticFired = false;
      _setPull(_initialPull(notification.metrics));
      return false;
    }

    if (!_isPulling) {
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      // 手指抬起后物理量还会继续跑（iOS 回弹），这里把控制权交给动画。
      if (notification.dragDetails == null) {
        _settleOnRelease();
        return false;
      }
      final double delta = -notification.scrollDelta!;
      if (delta > 0 && notification.metrics.extentBefore > 0) {
        // 回拉过头后（手指还没松、列表已经真的往回滚了一段）再下拉：
        // 「滚回顶部」这段位移不能算进拉力，否则小球会提前出现、
        // 二次下拉比第一次更容易触发（手感变轻）。
        return false;
      }
      // Bouncing：越界拖动走 ScrollUpdate（scrollDelta < 0）；
      // clamping：反向拉回走 ScrollUpdate（scrollDelta > 0）。
      _applyDelta(delta);
      return false;
    }

    if (notification is OverscrollNotification) {
      // clamping 平台（Android 默认）：越界距离在 overscroll 里。
      if (notification.dragDetails == null) {
        _settleOnRelease();
        return false;
      }
      final double delta = -notification.overscroll;
      if (delta > 0 && notification.metrics.extentBefore > 0) {
        // 同上：还没回到顶部，不算拉力。
        return false;
      }
      _applyDelta(delta);
      return false;
    }

    if (notification is ScrollEndNotification) {
      _settleOnRelease();
      return false;
    }

    return false;
  }

  void _applyDelta(double delta) {
    if (delta == 0.0) {
      return;
    }
    final double next = _pull + delta;
    if (next == _pull) {
      return;
    }
    _setPull(next);
  }

  void _setPull(double value) {
    _pull = value.clamp(0.0, _maxPull);
    // 允许 >1（过拉），视觉层再 clamp；这样 settle 时会有 M3E 的轻微回弹。
    _progress.value = _pull / widget.triggerDistance;

    final bool armed = _pull >= widget.triggerDistance;
    if (armed && !_hapticFired) {
      _hapticFired = true;
      applyHaptic(widget.hapticFeedback);
    } else if (!armed) {
      _hapticFired = false;
    }
    _phase = armed ? _Phase.armed : _Phase.drag;
  }

  void _settleOnRelease() {
    switch (_phase) {
      case _Phase.armed:
        _startRefresh();
      case _Phase.drag:
        _cancel();
      case _Phase.idle:
      case _Phase.refreshing:
        break;
    }
  }

  void _cancel() {
    _phase = _Phase.idle;
    _pull = 0.0;
    _hapticFired = false;
    _animateTo(0.0, widget.cancelMotion);
  }

  Future<void> _startRefresh() async {
    setState(() {
      _phase = _Phase.refreshing;
      _pull = widget.triggerDistance;
    });
    _animateTo(1.0, widget.springMotion);

    final Stopwatch watch = Stopwatch()..start();
    try {
      await widget.onRefresh();
    } catch (error, stackTrace) {
      widget.onError?.call(error, stackTrace);
    } finally {
      final Duration remaining = widget.minimumDisplayDuration - watch.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      if (mounted) {
        setState(() {
          _phase = _Phase.idle;
          _pull = 0.0;
          _hapticFired = false;
        });
        _animateTo(0.0, widget.cancelMotion);
      }
    }
  }

  void _animateTo(double target, M3EMotion motion) {
    final int token = ++_animToken;
    _progress
        .animateWith(
          SpringSimulation(
            SpringDescription.withDampingRatio(
              mass: 1.0,
              stiffness: motion.stiffness,
              ratio: motion.damping,
            ),
            _progress.value,
            target,
            0.0,
          ),
        )
        .whenComplete(() {
          // spring 是渐近收敛的，停在 0 附近但不等于 0；这里精确落到目标，
          // 否则「已收回」判定（t <= epsilon）永远不成立，会残留一层指示器。
          if (!mounted || token != _animToken) return;
          _progress.value = target;
        });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
        // 固定在上边缘，绝不随内容滚动 / 回弹；IgnorePointer 保证不抢手势。
        Positioned(
          top: widget.edgeOffset,
          left: 0.0,
          right: 0.0,
          child: IgnorePointer(
            child: ExcludeSemantics(
              excluding: !_isRefreshing,
              child: AnimatedBuilder(
                animation: _progress,
                builder: (BuildContext context, Widget? _) {
                  final double t = _progress.value.clamp(0.0, 1.0);
                  if (t <= _kHiddenEpsilon) {
                    return const SizedBox.shrink();
                  }
                  return SizedBox(
                    height: widget.indicatorHeight,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Opacity(
                        opacity: t,
                        child: Transform.translate(
                          offset: Offset(
                            0.0,
                            (t - 1.0) * widget.indicatorHeight,
                          ),
                          child: Transform.scale(
                            scale: 0.6 + 0.4 * t,
                            child:
                                widget.indicatorBuilder?.call(
                                  context,
                                  t,
                                  _isRefreshing,
                                ) ??
                                M3EContainedLoadingIndicator(
                                  width: 48.0,
                                  height: 48.0,
                                  // 48 − 2×5 = 38，对齐 M3 的 48dp / 38dp 形状容器。
                                  padding: const EdgeInsets.all(5.0),
                                  progress: _isRefreshing ? null : t,
                                  semanticsLabel: _isRefreshing
                                      ? widget.semanticsLabel
                                      : null,
                                  semanticsValue: _isRefreshing
                                      ? widget.semanticsValue
                                      : null,
                                ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
