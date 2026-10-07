import 'package:flutter/services.dart';

import 'platform_support.dart';

/// 窗口边框 / 标题栏明暗：Windows 默认跟随系统，浅色应用跑在深色系统上时
/// 会有一圈深色 1px 边框（看着像多了一条滚动条轨道）。这里由应用把当前
/// 主题的明暗告诉 Windows，让窗口框跟着应用走。
class WindowFrame {
  WindowFrame._();

  static const _channel = MethodChannel('lancloud/window');

  /// 上一次同步过的值，避免每次 build 都发消息。
  static bool? _lastDark;

  static Future<void> setDark(bool dark) async {
    if (!PlatformSupport.isWindows || _lastDark == dark) return;
    _lastDark = dark;
    try {
      await _channel.invokeMethod<void>('setDarkFrame', dark);
    } catch (_) {
      // 通道不可用（测试环境等）时忽略：只是窗口边框颜色不同而已
    }
  }
}
