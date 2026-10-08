import 'package:flutter/widgets.dart';

import '../core/system_motion.dart';

/// 系统是否要求「少动效」：
///
/// - 平台无障碍里的「移除动画」（Android）/「减弱动态效果」（iOS）
///   → [MediaQueryData.disableAnimations]
/// - 读屏软件（TalkBack / VoiceOver）接管交互
///   → [MediaQueryData.accessibleNavigation]
/// - 原生侧读到的三个动画缩放（华为等 ROM 的「移除动画」只改其中两个，
///   引擎看不到）→ [SystemMotion.reduceMotion]
///
/// 两者任一开启时，页面转场、列表入场这类装饰性动画都应该直接跳过：
/// 大面积位移 / 缩放会让前庭敏感的用户不适。跟手的拖拽与滚动不在此列
/// （那是用户自己直接操作的）。
bool reduceMotionOf(BuildContext context) {
  if (SystemMotion.reduceMotion.value) return true;
  final data = MediaQuery.maybeOf(context);
  if (data == null) return false;
  return data.disableAnimations || data.accessibleNavigation;
}
