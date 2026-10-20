import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// 全局系统栏样式：状态栏、导航栏都透明，图标明暗随主题，
/// 并关掉系统给透明导航栏垫的半透明遮罩（否则看着不是真透明）。
///
/// 主界面由 app.dart 挂在 `MaterialApp.builder` 上；不经过主界面的页面
/// （比如首次启动的欢迎页）自己用 [AnnotatedRegion] 套同一份样式，
/// 否则导航栏会退回系统默认的不透明底色（不沉浸）。
SystemUiOverlayStyle systemUiOverlayStyleFor(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}

/// edge-to-edge 页面使用的系统安全区。
///
/// [MediaQuery.padding] 会被 Scaffold / 键盘等父级清除，而 `viewPadding`
/// 保留窗口原始的刘海、状态栏与导航栏尺寸。取两者较大值，既不会重复留白，
/// 也能避免在 Scaffold 内部拿到已经被清空的 padding 后让内容钻到状态栏下面。
EdgeInsets systemUiSafeInsets(BuildContext context) {
  final media = MediaQuery.of(context);
  return EdgeInsets.fromLTRB(
    math.max(media.padding.left, media.viewPadding.left),
    math.max(media.padding.top, media.viewPadding.top),
    math.max(media.padding.right, media.viewPadding.right),
    math.max(media.padding.bottom, media.viewPadding.bottom),
  );
}
