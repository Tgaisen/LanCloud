import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/platform_support.dart';

/// 全局滚动行为：所有滚动视图默认使用网盘页同款的 BouncingScrollPhysics，
/// 并叠加 AlwaysScrollableScrollPhysics，内容不足一屏时也能拖出回弹。
///
/// 同时关闭 Android 的拉伸/发光 overscroll 指示器：BouncingScrollPhysics
/// 自己就有回弹位移，再叠加系统指示器会出现“双重动效”。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  /// 桌面端滚动条尺寸：与移动端的 FastScrollbar 保持一致。
  static const ScrollPhysics physics = BouncingScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => physics;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // 桌面端由这里统一提供滚动条：所有页面同一套厚度 / 圆角 / 动画，
    // 不会出现「某个页面的滚动条长得不一样」，也不需要各页面自己挂。
    // 轨道上下留白读的是 MediaQuery.padding：页面把浮层顶栏 / 底栏高度
    // 通过 FastScrollbar 传下来，滑块因此不会被顶栏截断。
    if (!PlatformSupport.isDesktop) return child;
    return ScrollbarTheme(
      // 不画轨道：只剩一条圆角滑块，避免和窗口边框 / 卡片边缘混在一起像两条
      data: const ScrollbarThemeData(
        trackColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      child: Scrollbar(
        controller: details.controller,
        thickness: 6,
        radius: const Radius.circular(3),
        interactive: true,
        child: child,
      ),
    );
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// 下拉刷新与滚动物理共享的**手势记账**：本次手势还欠刷新组件多少位移。
///
/// 下拉时物理层把位移交给刷新组件（[addPull] 记一笔），回拉时先还账
/// （[takeBack]，小球收回去），还完剩下的位移才滚列表。
///
/// 为什么不直接读刷新组件内部的拉出进度：甩动（惯性）这类非拖拽路径会把
/// 组件内部状态搞脏（组件不再处理后续通知、进度停在中途），物理层就会一直
/// 以为小球还在，把列表夹在顶部不动——表现为顶部卡出一层空白、且滚不动。
/// 记在本手势里、手势开始/结束清零（[reset]），就不会跨手势残留。
class PullToRefreshGesture {
  double _pullDebt = 0;
  bool _dragging = false;

  /// 是否还欠刷新组件位移（小球没收回）。
  bool get isPulling => _pullDebt > 0;

  /// 当前是不是「手指按住」的拖拽（惯性甩动、回弹不算）。
  ///
  /// 只有真实拖拽才记账：否则甩回顶部时的过冲会被当成「用户下拉」记成欠账，
  /// 紧接着的回弹又被当成「还账」吃掉，列表就停在顶部越界处动不了。
  bool get isDragging => _dragging;

  /// 手指按下、开始一次拖拽。
  void beginDrag() {
    _dragging = true;
    _pullDebt = 0;
  }

  /// 手指抬起 / 拖拽结束。
  void endDrag() {
    _dragging = false;
    _pullDebt = 0;
  }

  /// 下拉：物理层把 [fingerPx]（手指位移）交给了刷新组件。
  void addPull(double fingerPx) {
    if (fingerPx > 0) _pullDebt += fingerPx;
  }

  /// 回拉 [fingerPx]：先还账，返回本次仍应交给刷新组件的位移。
  double takeBack(double fingerPx) {
    if (fingerPx <= 0 || _pullDebt <= 0) return 0;
    final double consumed = math.min(fingerPx, _pullDebt);
    _pullDebt -= consumed;
    return consumed;
  }

  /// 手势开始 / 结束：一笔勾销（跨手势不继承欠账）。
  void reset() => _pullDebt = 0;
}

/// 下拉刷新专用滚动物理：**顶部下拉时列表自身不回弹**。
///
/// 用 Bouncing 物理时，下拉会同时产生两份位移——列表自己在 overscroll 里
/// 下滑一段，下拉刷新组件又把 header 区域插在滚动视图上方，于是「刷新小球」
/// 和第一条列表项之间会多出一层回弹留白。这里把顶部下拉的位移全部吃掉
/// （返回非零 overscroll 交给 `OverscrollNotification`），位移只由刷新组件
/// 表现；底部回弹、惯性、下滑手感仍是全局的 Bouncing。
///
/// 顶部**回拉**时按 [PullToRefreshGesture] 的欠账先收小球，收完剩下的位移
/// 才滚列表（不会出现「小球没收回列表就滚」或「小球卡住不收」）。
class PullToRefreshScrollPhysics extends ScrollPhysics {
  const PullToRefreshScrollPhysics({required this.gesture, super.parent});

  /// 与刷新组件共享的手势记账，见 [PullToRefreshGesture]。
  final PullToRefreshGesture gesture;

  @override
  PullToRefreshScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      PullToRefreshScrollPhysics(
        gesture: gesture,
        parent: buildParent(ancestor),
      );

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (position.pixels <= position.minScrollExtent &&
        value != position.pixels) {
      final double delta = value - position.pixels;
      // 位置已经越界（负值）时不再拦截：那是甩动的过冲 / 回弹过程，
      // 交给 Bouncing 自己弹回去；继续认领会把列表永久停在越界位置。
      final bool atRestTop = position.pixels >= position.minScrollExtent;
      if (delta < 0) {
        // 顶部下拉：只有手指按住的拖拽才交给刷新组件（列表自身不动）并记账；
        // 惯性甩动的过冲走原来的 Bouncing，留给它自己回弹。
        if (gesture.isDragging && atRestTop) {
          gesture.addPull(-delta);
          return delta;
        }
        return super.applyBoundaryConditions(position, value);
      }
      // 顶部回拉：拖拽时先还账（收小球），还完剩下的位移才滚列表。
      if (gesture.isDragging && atRestTop) {
        final double consumed = gesture.takeBack(delta);
        if (consumed > 0) return consumed;
      }
    }
    return super.applyBoundaryConditions(position, value);
  }
}

/// 只关掉「框架自动追加的滚动条」，其它滚动行为与全局保持一致。
///
/// 用在已经自带滚动条的容器（[FastScrollbar]）或自己接管滚动的包装层里：
/// 否则框架会在 Windows 上额外塞一条样式不同的 RawScrollbar，看起来就是
/// 同一个页面出现了两条滚动条。
class NoAutoScrollbarBehavior extends AppScrollBehavior {
  const NoAutoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
