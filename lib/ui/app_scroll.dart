import 'package:flutter/material.dart';

/// 全局滚动行为：所有滚动视图默认使用网盘页同款的 BouncingScrollPhysics，
/// 并叠加 AlwaysScrollableScrollPhysics，内容不足一屏时也能拖出回弹。
///
/// 同时关闭 Android 的拉伸/发光 overscroll 指示器：BouncingScrollPhysics
/// 自己就有回弹位移，再叠加系统指示器会出现“双重动效”。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  static const ScrollPhysics physics = BouncingScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => physics;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
