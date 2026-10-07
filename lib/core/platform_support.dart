import 'package:flutter/foundation.dart';

/// 平台能力判断。
///
/// 桌面端（Windows）没有 Android 的那套原生通道（前台服务、分享接收、
/// 系统保存面板等），各处的差异判断集中在这里，业务代码只问能力，
/// 不再到处散落 `Platform.isXXX`。
///
/// 统一用 [defaultTargetPlatform]：真机/真桌面按实际平台取值，
/// 而 `flutter test` 里固定为 Android（Flutter 的约定），
/// 现有测试的移动端行为不受影响。
class PlatformSupport {
  PlatformSupport._();

  /// 桌面端：Windows（当前唯一适配目标，顺带覆盖 macOS / Linux）。
  static bool get isDesktop => switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => true,
    _ => false,
  };

  static bool get isWindows => defaultTargetPlatform == TargetPlatform.windows;

  /// 移动端：前台服务、分享接收、APK 安装等都只有这里才有。
  static bool get isMobile => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };

  /// 相机拍照入口（扫码里的「拍一张」）：只有移动端有。
  static bool get hasCameraCapture => isMobile;
}
