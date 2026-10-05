import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';

/// 动态取色（Android 12+ 壁纸取色）支持探测，结果带缓存。
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
    var supported = false;
    try {
      supported = await DynamicColorPlugin.getCorePalette() != null;
      if (!supported) {
        supported = await DynamicColorPlugin.getAccentColor() != null;
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
