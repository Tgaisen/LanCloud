import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/platform_capabilities.dart';

void main() {
  group('PlatformCapabilities', () {
    test('应该为 Android 暴露当前真实能力', () {
      _expectCapabilities(
        PlatformCapabilities.forPlatform(TargetPlatform.android),
        const PlatformCapabilities(
          formFactor: PlatformFormFactor.mobile,
          inputStyle: PlatformInputStyle.touchFirst,
          supportsCameraCapture: true,
          supportsDocumentProviderUpload: true,
          supportsIncomingShare: true,
          supportsForegroundTask: true,
          supportsLocalNotifications: true,
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
        ),
      );
    });

    test('应该为 Windows 只开启已实现的桌面能力', () {
      _expectCapabilities(
        PlatformCapabilities.forPlatform(TargetPlatform.windows),
        const PlatformCapabilities(
          formFactor: PlatformFormFactor.desktop,
          inputStyle: PlatformInputStyle.pointerFirst,
          supportsCameraCapture: false,
          supportsDocumentProviderUpload: false,
          supportsIncomingShare: false,
          supportsForegroundTask: false,
          supportsLocalNotifications: true,
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
        ),
      );
    });

    test('应该为 iOS 开启已实现的文件另存为并关闭其余可选能力', () {
      _expectCapabilities(
        PlatformCapabilities.forPlatform(TargetPlatform.iOS),
        const PlatformCapabilities(
          formFactor: PlatformFormFactor.mobile,
          inputStyle: PlatformInputStyle.touchFirst,
          supportsCameraCapture: false,
          supportsDocumentProviderUpload: false,
          supportsIncomingShare: false,
          supportsForegroundTask: false,
          supportsLocalNotifications: false,
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
        ),
      );
    });

    test('应该为 macOS 保守关闭所有可选能力', () {
      _expectCapabilities(
        PlatformCapabilities.forPlatform(TargetPlatform.macOS),
        const PlatformCapabilities(
          formFactor: PlatformFormFactor.desktop,
          inputStyle: PlatformInputStyle.pointerFirst,
          supportsCameraCapture: false,
          supportsDocumentProviderUpload: false,
          supportsIncomingShare: false,
          supportsForegroundTask: false,
          supportsLocalNotifications: false,
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
        ),
      );
    });

    test('应该为 Linux 保守关闭所有可选能力', () {
      _expectCapabilities(
        PlatformCapabilities.forPlatform(TargetPlatform.linux),
        const PlatformCapabilities(
          formFactor: PlatformFormFactor.desktop,
          inputStyle: PlatformInputStyle.pointerFirst,
          supportsCameraCapture: false,
          supportsDocumentProviderUpload: false,
          supportsIncomingShare: false,
          supportsForegroundTask: false,
          supportsLocalNotifications: false,
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
        ),
      );
    });

    test('应该对未知平台 fail closed', () {
      _expectCapabilities(
        PlatformCapabilities.forPlatform(TargetPlatform.fuchsia),
        const PlatformCapabilities(
          formFactor: PlatformFormFactor.unknown,
          inputStyle: PlatformInputStyle.unknown,
          supportsCameraCapture: false,
          supportsDocumentProviderUpload: false,
          supportsIncomingShare: false,
          supportsForegroundTask: false,
          supportsLocalNotifications: false,
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
        ),
      );
    });

    test('应该显式映射动态色来源和更新产物', () {
      expect(
        PlatformCapabilities.android.dynamicColorSource,
        DynamicColorSource.wallpaper,
      );
      expect(
        PlatformCapabilities.windows.dynamicColorSource,
        DynamicColorSource.systemAccent,
      );
      expect(
        PlatformCapabilities.ios.dynamicColorSource,
        DynamicColorSource.none,
      );
      expect(
        PlatformCapabilities.macOS.dynamicColorSource,
        DynamicColorSource.none,
      );
      expect(
        PlatformCapabilities.linux.dynamicColorSource,
        DynamicColorSource.none,
      );
      expect(
        PlatformCapabilities.unsupported.dynamicColorSource,
        DynamicColorSource.none,
      );

      expect(
        PlatformCapabilities.android.updateArtifact,
        UpdateArtifact.androidApk,
      );
      expect(
        PlatformCapabilities.windows.updateArtifact,
        UpdateArtifact.windowsPortable,
      );
      expect(PlatformCapabilities.ios.updateArtifact, UpdateArtifact.none);
      expect(PlatformCapabilities.macOS.updateArtifact, UpdateArtifact.none);
      expect(PlatformCapabilities.linux.updateArtifact, UpdateArtifact.none);
      expect(
        PlatformCapabilities.unsupported.updateArtifact,
        UpdateArtifact.none,
      );
    });

    test('应该是可复用的 const 只读对象', () {
      const capabilities = PlatformCapabilities.android;

      expect(
        identical(
          capabilities,
          PlatformCapabilities.forPlatform(TargetPlatform.android),
        ),
        isTrue,
      );
      expect(capabilities.formFactor, PlatformFormFactor.mobile);
    });

    test('current 应该跟随 debugDefaultTargetPlatformOverride', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        identical(
          PlatformCapabilities.current,
          PlatformCapabilities.forPlatform(TargetPlatform.windows),
        ),
        isTrue,
      );
    });

    test('Riverpod provider 应该支持测试覆盖', () {
      final capabilities = PlatformCapabilities.forPlatform(TargetPlatform.iOS);
      final container = ProviderContainer(
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(capabilities),
        ],
      );
      addTearDown(container.dispose);

      expect(
        identical(container.read(platformCapabilitiesProvider), capabilities),
        isTrue,
      );
    });
  });
}

void _expectCapabilities(
  PlatformCapabilities actual,
  PlatformCapabilities expected,
) {
  expect(actual.formFactor, expected.formFactor);
  expect(actual.inputStyle, expected.inputStyle);
  expect(actual.supportsCameraCapture, expected.supportsCameraCapture);
  expect(
    actual.supportsDocumentProviderUpload,
    expected.supportsDocumentProviderUpload,
  );
  expect(actual.supportsIncomingShare, expected.supportsIncomingShare);
  expect(actual.supportsForegroundTask, expected.supportsForegroundTask);
  expect(
    actual.supportsLocalNotifications,
    expected.supportsLocalNotifications,
  );
  expect(
    actual.supportsEdgeToEdgeSystemUi,
    expected.supportsEdgeToEdgeSystemUi,
  );
  expect(actual.supportsSystemShare, expected.supportsSystemShare);
  expect(actual.supportsSystemFileSave, expected.supportsSystemFileSave);
  expect(actual.supportsSafDirectory, expected.supportsSafDirectory);
  expect(
    actual.supportsPermissionManagement,
    expected.supportsPermissionManagement,
  );
  expect(
    actual.supportsDefaultLinkSettings,
    expected.supportsDefaultLinkSettings,
  );
  expect(actual.supportsAppSettingsPage, expected.supportsAppSettingsPage);
  expect(actual.supportsDesktopDrop, expected.supportsDesktopDrop);
  expect(
    actual.usesPrivateMobileTemporaryDirectory,
    expected.usesPrivateMobileTemporaryDirectory,
  );
  expect(actual.usesMobileWebUserAgent, expected.usesMobileWebUserAgent);
  expect(actual.dynamicColorSource, expected.dynamicColorSource);
  expect(actual.updateArtifact, expected.updateArtifact);
}
