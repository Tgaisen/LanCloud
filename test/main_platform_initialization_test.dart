import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/platform_capabilities.dart';
import 'package:lancloud/main.dart' as app_main;

void main() {
  group('平台启动初始化', () {
    test('Android 应该初始化 edge-to-edge 与前台服务', () async {
      final modes = <SystemUiMode>[];
      var foregroundInitializations = 0;

      await app_main.initializePlatformSystemUi(
        capabilities: PlatformCapabilities.android,
        setSystemUiMode: (mode) async => modes.add(mode),
      );
      app_main.initializePlatformForegroundService(
        capabilities: PlatformCapabilities.android,
        initialize: () => foregroundInitializations += 1,
      );

      expect(modes, [SystemUiMode.edgeToEdge]);
      expect(foregroundInitializations, 1);
    });

    test('Windows 应该跳过移动端启动能力', () async {
      var systemUiCalls = 0;
      var foregroundInitializations = 0;

      await app_main.initializePlatformSystemUi(
        capabilities: PlatformCapabilities.windows,
        setSystemUiMode: (_) async => systemUiCalls += 1,
      );
      app_main.initializePlatformForegroundService(
        capabilities: PlatformCapabilities.windows,
        initialize: () => foregroundInitializations += 1,
      );

      expect(systemUiCalls, 0);
      expect(foregroundInitializations, 0);
    });

    test('iOS 应该跳过未接入的 edge-to-edge 与前台服务', () async {
      var systemUiCalls = 0;
      var foregroundInitializations = 0;

      await app_main.initializePlatformSystemUi(
        capabilities: PlatformCapabilities.ios,
        setSystemUiMode: (_) async => systemUiCalls += 1,
      );
      app_main.initializePlatformForegroundService(
        capabilities: PlatformCapabilities.ios,
        initialize: () => foregroundInitializations += 1,
      );

      expect(systemUiCalls, 0);
      expect(foregroundInitializations, 0);
    });
  });
}
