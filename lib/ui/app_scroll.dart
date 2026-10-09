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

/// 下拉刷新专用滚动物理：**顶部下拉时列表自身不回弹**。
///
/// 用 Bouncing 物理时，下拉会同时产生两份位移——列表自己在 overscroll 里
/// 下滑一段，下拉刷新组件又把 header 区域插在滚动视图上方，于是「刷新小球」
/// 和第一条列表项之间会多出一层回弹留白。这里把顶部下拉的位移全部吃掉
/// （返回非零 overscroll 交给 `OverscrollNotification`），位移只由刷新组件
/// 表现；底部回弹、惯性、下滑手感仍是全局的 Bouncing。
///
/// 用法：`CustomScrollView(physics: PullToRefreshScrollPhysics(parent: AppScrollBehavior.physics))`
class PullToRefreshScrollPhysics extends ScrollPhysics {
  const PullToRefreshScrollPhysics({super.parent});

  @override
  PullToRefreshScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      PullToRefreshScrollPhysics(parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // 已在顶部（或越过顶部）还要继续往下拉：整段位移都算 overscroll，
    // 由下拉刷新组件消费，列表自身不动。
    if (position.pixels <= position.minScrollExtent &&
        value <= position.pixels) {
      return value - position.pixels;
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
