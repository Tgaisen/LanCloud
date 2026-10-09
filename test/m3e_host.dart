import 'package:flutter/material.dart';
import 'package:lancloud/ui/m3e.dart';

/// 与正式应用一致的宿主装饰：M3E 组件级样式 + material_ui 桥接，
/// 挂在 Navigator 之上。
///
/// 凡是要打开 MD3E 底部弹窗（[showAppSheet] 等）或渲染 MD3E 控件的测试，
/// 都要给 `MaterialApp` 配上这个 builder——正式应用里由
/// `MaterialApp.builder` 统一挂（见 app.dart）。
Widget m3eTestBuilder(BuildContext context, Widget? child) =>
    M3eRoot(child: child ?? const SizedBox.shrink());
