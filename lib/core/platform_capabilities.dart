import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前平台的产品形态。
enum PlatformFormFactor { mobile, desktop, unknown }

/// 当前平台的输入偏好。
enum PlatformInputStyle { touchFirst, pointerFirst, unknown }

/// 动态色的静态来源；实际是否可用仍需运行时探测。
enum DynamicColorSource { none, wallpaper, systemAccent }

/// 当前平台可选择的更新产物。
enum UpdateArtifact { none, androidApk, windowsPortable }

/// 当前 Dart 实现能否安全执行的静态平台能力。
///
/// 这里只描述平台矩阵。通知权限、生物识别硬件、动态色实际可用性等运行时
/// 状态不进入本对象；Android SDK、ABI 等底层探测继续由 `PlatformSupport`
/// 负责。
@immutable
final class PlatformCapabilities {
  const PlatformCapabilities({
    required this.formFactor,
    required this.inputStyle,
    required this.supportsCameraCapture,
    required this.supportsDocumentProviderUpload,
    required this.supportsIncomingShare,
    required this.supportsForegroundTask,
    required this.supportsEdgeToEdgeSystemUi,
    required this.supportsSystemShare,
    required this.supportsSystemFileSave,
    required this.supportsSafDirectory,
    required this.supportsPermissionManagement,
    required this.supportsDefaultLinkSettings,
    required this.supportsAppSettingsPage,
    required this.supportsDesktopDrop,
    required this.usesPrivateMobileTemporaryDirectory,
    required this.usesMobileWebUserAgent,
    required this.dynamicColorSource,
    required this.updateArtifact,
  });

  static const android = PlatformCapabilities(
    formFactor: PlatformFormFactor.mobile,
    inputStyle: PlatformInputStyle.touchFirst,
    supportsCameraCapture: true,
    supportsDocumentProviderUpload: true,
    supportsIncomingShare: true,
    supportsForegroundTask: true,
    supportsEdgeToEdgeSystemUi: true,
    supportsSystemShare: true,
    supportsSystemFileSave: true,
    supportsSafDirectory: true,
    supportsPermissionManagement: true,
    supportsDefaultLinkSettings: true,
    supportsAppSettingsPage: true,
    supportsDesktopDrop: false,
    usesPrivateMobileTemporaryDirectory: true,
    usesMobileWebUserAgent: true,
    dynamicColorSource: DynamicColorSource.wallpaper,
    updateArtifact: UpdateArtifact.androidApk,
  );

  static const windows = PlatformCapabilities(
    formFactor: PlatformFormFactor.desktop,
    inputStyle: PlatformInputStyle.pointerFirst,
    supportsCameraCapture: false,
    supportsDocumentProviderUpload: false,
    supportsIncomingShare: false,
    supportsForegroundTask: false,
    supportsEdgeToEdgeSystemUi: false,
    supportsSystemShare: false,
    supportsSystemFileSave: true,
    supportsSafDirectory: false,
    supportsPermissionManagement: false,
    supportsDefaultLinkSettings: false,
    supportsAppSettingsPage: false,
    supportsDesktopDrop: true,
    usesPrivateMobileTemporaryDirectory: false,
    usesMobileWebUserAgent: false,
    dynamicColorSource: DynamicColorSource.systemAccent,
    updateArtifact: UpdateArtifact.windowsPortable,
  );

  static const ios = PlatformCapabilities(
    formFactor: PlatformFormFactor.mobile,
    inputStyle: PlatformInputStyle.touchFirst,
    supportsCameraCapture: false,
    supportsDocumentProviderUpload: false,
    supportsIncomingShare: false,
    supportsForegroundTask: false,
    supportsEdgeToEdgeSystemUi: false,
    supportsSystemShare: false,
    supportsSystemFileSave: true,
    supportsSafDirectory: false,
    supportsPermissionManagement: false,
    supportsDefaultLinkSettings: false,
    supportsAppSettingsPage: false,
    supportsDesktopDrop: false,
    usesPrivateMobileTemporaryDirectory: true,
    usesMobileWebUserAgent: true,
    dynamicColorSource: DynamicColorSource.none,
    updateArtifact: UpdateArtifact.none,
  );

  static const macOS = PlatformCapabilities(
    formFactor: PlatformFormFactor.desktop,
    inputStyle: PlatformInputStyle.pointerFirst,
    supportsCameraCapture: false,
    supportsDocumentProviderUpload: false,
    supportsIncomingShare: false,
    supportsForegroundTask: false,
    supportsEdgeToEdgeSystemUi: false,
    supportsSystemShare: false,
    supportsSystemFileSave: false,
    supportsSafDirectory: false,
    supportsPermissionManagement: false,
    supportsDefaultLinkSettings: false,
    supportsAppSettingsPage: false,
    supportsDesktopDrop: false,
    usesPrivateMobileTemporaryDirectory: false,
    usesMobileWebUserAgent: false,
    dynamicColorSource: DynamicColorSource.none,
    updateArtifact: UpdateArtifact.none,
  );

  static const linux = PlatformCapabilities(
    formFactor: PlatformFormFactor.desktop,
    inputStyle: PlatformInputStyle.pointerFirst,
    supportsCameraCapture: false,
    supportsDocumentProviderUpload: false,
    supportsIncomingShare: false,
    supportsForegroundTask: false,
    supportsEdgeToEdgeSystemUi: false,
    supportsSystemShare: false,
    supportsSystemFileSave: false,
    supportsSafDirectory: false,
    supportsPermissionManagement: false,
    supportsDefaultLinkSettings: false,
    supportsAppSettingsPage: false,
    supportsDesktopDrop: false,
    usesPrivateMobileTemporaryDirectory: false,
    usesMobileWebUserAgent: false,
    dynamicColorSource: DynamicColorSource.none,
    updateArtifact: UpdateArtifact.none,
  );

  /// 未知或不支持平台的保守矩阵：所有可选能力保持关闭。
  static const unsupported = PlatformCapabilities(
    formFactor: PlatformFormFactor.unknown,
    inputStyle: PlatformInputStyle.unknown,
    supportsCameraCapture: false,
    supportsDocumentProviderUpload: false,
    supportsIncomingShare: false,
    supportsForegroundTask: false,
    supportsEdgeToEdgeSystemUi: false,
    supportsSystemShare: false,
    supportsSystemFileSave: false,
    supportsSafDirectory: false,
    supportsPermissionManagement: false,
    supportsDefaultLinkSettings: false,
    supportsAppSettingsPage: false,
    supportsDesktopDrop: false,
    usesPrivateMobileTemporaryDirectory: false,
    usesMobileWebUserAgent: false,
    dynamicColorSource: DynamicColorSource.none,
    updateArtifact: UpdateArtifact.none,
  );

  final PlatformFormFactor formFactor;
  final PlatformInputStyle inputStyle;
  final bool supportsCameraCapture;
  final bool supportsDocumentProviderUpload;
  final bool supportsIncomingShare;
  final bool supportsForegroundTask;
  final bool supportsEdgeToEdgeSystemUi;
  final bool supportsSystemShare;
  final bool supportsSystemFileSave;
  final bool supportsSafDirectory;
  final bool supportsPermissionManagement;
  final bool supportsDefaultLinkSettings;
  final bool supportsAppSettingsPage;
  final bool supportsDesktopDrop;
  final bool usesPrivateMobileTemporaryDirectory;
  final bool usesMobileWebUserAgent;
  final DynamicColorSource dynamicColorSource;
  final UpdateArtifact updateArtifact;

  /// 按指定平台取得能力矩阵；未知平台返回关闭全部可选能力的矩阵。
  static PlatformCapabilities forPlatform(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.android => android,
        TargetPlatform.windows => windows,
        TargetPlatform.iOS => ios,
        TargetPlatform.macOS => macOS,
        TargetPlatform.linux => linux,
        _ => unsupported,
      };

  /// 当前 Flutter TargetPlatform 对应的能力矩阵。
  static PlatformCapabilities get current => forPlatform(defaultTargetPlatform);
}

/// 应用级静态能力矩阵；测试可通过 Riverpod override 注入替身。
final platformCapabilitiesProvider = Provider<PlatformCapabilities>(
  (_) => PlatformCapabilities.current,
);
