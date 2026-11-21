import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';

import 'platform_capabilities.dart';

/// 动态色插件的运行时可用性探测端口。
abstract interface class DynamicColorProbe {
  Future<bool> hasCorePalette();

  Future<bool> hasAccentColor();
}

final class DynamicColorPluginProbe implements DynamicColorProbe {
  const DynamicColorPluginProbe();

  @override
  Future<bool> hasCorePalette() async {
    return await DynamicColorPlugin.getCorePalette() != null;
  }

  @override
  Future<bool> hasAccentColor() async {
    return await DynamicColorPlugin.getAccentColor() != null;
  }
}

/// 系统主题色支持探测，结果带缓存。
///
/// dynamic_color 的 [DynamicColorBuilder] 每次探测失败都会打印一行
/// "Dynamic color not detected on this device."；设置页那种会随搜索 / 滚动
/// 重建的地方不能直接用，否则日志会被刷屏。这里只在首次（或 refresh）探测。
class DynamicColorSupport {
  DynamicColorSupport._();

  static DynamicColorSource? _cachedSource;
  static bool? _supported;

  /// 设备是否支持动态取色；[refresh] 为 true 时重新探测。
  static Future<bool> isSupported({
    bool refresh = false,
    PlatformCapabilities? capabilities,
    DynamicColorProbe probe = const DynamicColorPluginProbe(),
  }) async {
    final source =
        (capabilities ?? PlatformCapabilities.current).dynamicColorSource;
    if (!refresh && _cachedSource == source && _supported != null) {
      return _supported!;
    }
    var supported = false;
    try {
      switch (source) {
        case DynamicColorSource.none:
          supported = false;
        case DynamicColorSource.systemAccent:
          supported = await probe.hasAccentColor();
        case DynamicColorSource.wallpaper:
          supported =
              await probe.hasCorePalette() || await probe.hasAccentColor();
      }
    } on PlatformException {
      supported = false;
    } on MissingPluginException {
      supported = false;
    } catch (_) {
      supported = false;
    }
    _cachedSource = source;
    _supported = supported;
    return supported;
  }
}
