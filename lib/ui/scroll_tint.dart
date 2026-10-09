import 'package:material_ui/material_ui.dart';

/// 顶栏滚动变色的公共实现：离开顶部即触发，50ms 过渡。
/// 用法：页面外层包 [ScrollTint]，页面 AppBar 里读 [ScrollTint.of] 作为渐变进度。
class ScrollTint extends StatefulWidget {
  const ScrollTint({
    super.key,
    required this.child,
    this.onBarsHidden,
    this.readBarsHidden,
    this.hideDistance = 80,
  });

  final Widget child;

  /// 滚动时按距离通知底栏隐藏进度 0..1（0 显示，1 完全隐藏）。
  final void Function(double progress)? onBarsHidden;

  /// 读取外部真实的收起进度：每次开始拖动时对齐，
  /// 避免程序化显示/隐藏之后累计值漂移导致下一次滑动瞬间跳变。
  final double Function()? readBarsHidden;

  /// 完全收起所需的滚动距离，与底栏高度一致可实现 1:1 跟随。
  final double hideDistance;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TintScope>()?.value ?? 0;

  @override
  State<ScrollTint> createState() => _ScrollTintState();
}

class _ScrollTintState extends State<ScrollTint>
    with SingleTickerProviderStateMixin {
  double _lastPixels = 0;
  double _hide = 0;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 50),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onNotification(ScrollNotification notification) {
    final axis = notification.metrics.axisDirection;
    if (axis != AxisDirection.down && axis != AxisDirection.up) {
      // 忽略横向滚动（例如切换视图的 PageView）
      return false;
    }
    if (widget.onBarsHidden != null) {
      final pixels = notification.metrics.pixels;
      final delta = pixels - _lastPixels;
      _lastPixels = pixels;
      if (notification is ScrollStartNotification) {
        _hide = widget.readBarsHidden?.call() ?? _hide;
      }
      var hide = _hide;
      if (pixels <= 0) {
        hide = 0;
      } else if (delta != 0) {
        hide = (hide + delta / widget.hideDistance).clamp(0.0, 1.0);
      }
      if (hide != _hide) {
        _hide = hide;
        widget.onBarsHidden!(hide);
      }
    }
    if (notification.metrics.pixels > 0) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) =>
            _TintScope(value: _controller.value, child: child!),
        child: widget.child,
      ),
    );
  }
}

class _TintScope extends InheritedWidget {
  const _TintScope({required this.value, required super.child});

  final double value;

  @override
  bool updateShouldNotify(_TintScope oldWidget) => oldWidget.value != value;
}

/// 顶栏隐藏的动画宿主：把 hidden 状态转成 0→1 的进度交给 builder，
/// 页面用它包住 Scaffold，就能让顶栏插槽高度逐帧变化（不留白）。
class CollapsibleTopBarHost extends StatefulWidget {
  const CollapsibleTopBarHost({
    super.key,
    required this.hidden,
    required this.builder,
  });

  final bool hidden;
  final Widget Function(BuildContext context, double t) builder;

  @override
  State<CollapsibleTopBarHost> createState() => _CollapsibleTopBarHostState();
}

class _CollapsibleTopBarHostState extends State<CollapsibleTopBarHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: widget.hidden ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant CollapsibleTopBarHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hidden != oldWidget.hidden) {
      if (widget.hidden) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => widget.builder(context, _controller.value),
  );
}

/// 高度可动画的顶栏包装：t=0 完全展开，t=1 完全收起且不占空间。
PreferredSizeWidget? collapsibleAppBar({
  required double t,
  required PreferredSizeWidget child,
  double height = kToolbarHeight,
}) {
  if (t >= 0.999) return null;
  final currentHeight = height * (1 - t);
  return PreferredSize(
    preferredSize: Size.fromHeight(currentHeight),
    child: ClipRect(
      child: SizedBox(
        height: currentHeight,
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: height,
          maxHeight: height,
          child: child,
        ),
      ),
    ),
  );
}
