import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';

import 'platform_support.dart';

/// 系统主题色支持探测，结果带缓存。
///
/// dynamic_color 的 [DynamicColorBuilder] 每次探测失败都会打印一行
/// "Dynamic color not detected on this device."；设置页那种会随搜索 / 滚动
/// 重建的地方不能直接用，否则日志会被刷屏。这里只在首次（或 refresh）探测。
class DynamicColorSupport {
  DynamicColorSupport._();

  static bool? _supported;

  /// 设备是否支持动态取色；[refresh] 为 true 时重新探测。
  static Future<bool> isSupported({bool refresh = false}) async {
    if (!refresh && _supported != null) return _supported!;
    // 当前只适配 Windows 桌面端；它没有 Android 的完整 CorePalette，
    // 但插件可返回系统强调色，DynamicColorBuilder 会据此生成完整色板。
    if (PlatformSupport.isDesktop && !PlatformSupport.isWindows) {
      _supported = false;
      return false;
    }
    var supported = false;
    try {
      if (PlatformSupport.isWindows) {
        supported = await DynamicColorPlugin.getAccentColor() != null;
      } else {
        supported = await DynamicColorPlugin.getCorePalette() != null;
        if (!supported) {
          supported = await DynamicColorPlugin.getAccentColor() != null;
        }
      }
    } on PlatformException {
      supported = false;
    } on MissingPluginException {
      supported = false;
    }
    _supported = supported;
    return supported;
  }
}
