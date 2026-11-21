import 'package:flutter/foundation.dart';

/// 是否检测到鼠标。悬停事件只来自鼠标 / 触控板，触摸屏不会触发，
/// 所以用它给桌面端交互做运行时开关：Android 插上鼠标也能用，纯触摸时
/// 行为保持不变。
class PointerSupport {
  PointerSupport._();

  static final ValueNotifier<bool> hasMouse = ValueNotifier<bool>(false);
}
