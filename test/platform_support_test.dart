import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/platform_support.dart';

void main() {
  test('平台语义 getter 应该显式映射 TargetPlatform', () {
    for (final (:name, :platform, :desktop, :windows, :android, :mobile) in [
      (
        name: 'Android',
        platform: TargetPlatform.android,
        desktop: false,
        windows: false,
        android: true,
        mobile: true,
      ),
      (
        name: 'Windows',
        platform: TargetPlatform.windows,
        desktop: true,
        windows: true,
        android: false,
        mobile: false,
      ),
      (
        name: 'iOS',
        platform: TargetPlatform.iOS,
        desktop: false,
        windows: false,
        android: false,
        mobile: true,
      ),
      (
        name: 'macOS',
        platform: TargetPlatform.macOS,
        desktop: true,
        windows: false,
        android: false,
        mobile: false,
      ),
      (
        name: 'Linux',
        platform: TargetPlatform.linux,
        desktop: true,
        windows: false,
        android: false,
        mobile: false,
      ),
      (
        name: 'Fuchsia',
        platform: TargetPlatform.fuchsia,
        desktop: false,
        windows: false,
        android: false,
        mobile: false,
      ),
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        expect(PlatformSupport.isDesktop, desktop, reason: name);
        expect(PlatformSupport.isWindows, windows, reason: name);
        expect(PlatformSupport.isAndroid, android, reason: name);
        expect(PlatformSupport.isMobile, mobile, reason: name);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });
}
