import 'package:flutter/widgets.dart';

import '../core/system_motion.dart';

/// 系统是否要求「少动效」：
///
/// - 平台无障碍里的「移除动画」（Android）/「减弱动态效果」（iOS）
///   → [MediaQueryData.disableAnimations]
/// - 原生侧读到的三个动画缩放（华为等 ROM 的「移除动画」只改其中两个，
///   引擎看不到）→ [SystemMotion.reduceMotion]
/// - 原生侧读到的触摸探索 = 真的读屏软件（TalkBack / 屏幕朗读）在接管交互
///   → [SystemMotion.touchExploration]
///
/// 任一开启时，页面转场、列表入场这类装饰性动画都应该直接跳过：
/// 大面积位移 / 缩放会让前庭敏感的用户不适。跟手的拖拽与滚动不在此列
/// （那是用户自己直接操作的）。
///
/// 注意这里**不看** [MediaQueryData.accessibleNavigation]：引擎在「任何一个
/// 无障碍服务查过一次语义树」时就会把它置位（自动记账、自动填表这类与读屏
/// 无关的服务也会触发），拿它当少动效等于「开了任意无障碍服务 = 全应用没有
/// 动画」。是否真的读屏交给原生判断（见 [SystemMotion.touchExploration]）。
bool reduceMotionOf(BuildContext context) {
  if (SystemMotion.reduceMotion.value || SystemMotion.touchExploration.value) {
    return true;
  }
  final data = MediaQuery.maybeOf(context);
  if (data == null) return false;
  return data.disableAnimations;
}
