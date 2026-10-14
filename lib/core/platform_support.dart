import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  /// Android：SAF（系统目录授权）等能力只有这里有。
  static bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// 移动端：前台服务、分享接收、APK 安装等都只有这里才有。
  static bool get isMobile => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };

  /// 相机拍照入口（扫码里的「拍一张」）：只有移动端有。
  static bool get hasCameraCapture => isMobile;

  /// Android SDK（API）级别；非 Android 或读取失败时为 null。
  static int? _androidSdkInt;
  static bool _androidSdkIntLoaded = false;

  /// 已缓存的 Android SDK 级别（启动时预热，见 [loadAndroidSdkInt]）。
  static int? get androidSdkIntCached => _androidSdkInt;

  /// 读取并缓存 Android SDK 级别（整个进程只读一次）。
  static Future<int?> loadAndroidSdkInt() async {
    if (_androidSdkIntLoaded) return _androidSdkInt;
    _androidSdkIntLoaded = true;
    if (!isAndroid) return null;
    try {
      _androidSdkInt = await const MethodChannel('lancloud/system')
          .invokeMethod<int>('androidSdkInt');
    } catch (_) {
      // 测试环境 / 通道不可用：保持 null，调用方按默认行为处理
      _androidSdkInt = null;
    }
    return _androidSdkInt;
  }

  /// WebView 是否用 Hybrid Composition（仅 Android 生效）。
  ///
  /// 插件文档（inappwebview 5 更新日志）：Hybrid Composition 在 Android 10+
  /// 才能明显提升性能并解决键盘相关问题；低于 Android 10 时动画会掉帧，
  /// 官方建议只在 Android 10+ 的正式版里启用。这里按同一判定：
  /// API 29（Android 10）及以上启用，更低版本回退插件老的合成方式；
  /// 读不到版本时保持启用（与插件默认值一致）。
  static bool get useHybridComposition {
    final sdkInt = _androidSdkInt;
    return sdkInt == null || sdkInt >= 29;
  }
}
