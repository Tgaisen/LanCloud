import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_permissions.dart';
import 'package:lancloud/core/platform_capabilities.dart';

class _FakeSystemSettingsTransport implements SystemSettingsTransport {
  Map<Object?, Object?>? statusValue = {
    'install': 'denied',
    'battery': 'granted',
  };
  bool? installResult = true;
  bool? batteryResult = true;
  bool? localNetworkResult = true;
  bool? appSettingsResult = true;
  bool? defaultLinkResult = true;
  Object? error;
  final List<String> calls = [];

  @override
  Future<Map<Object?, Object?>?> status() async {
    calls.add('status');
    _throwIfNeeded();
    return statusValue;
  }

  @override
  Future<bool?> openInstallSettings() async {
    calls.add('install');
    _throwIfNeeded();
    return installResult;
  }

  @override
  Future<bool?> requestBattery() async {
    calls.add('battery');
    _throwIfNeeded();
    return batteryResult;
  }

  @override
  Future<bool?> requestLocalNetwork() async {
    calls.add('localNetwork');
    _throwIfNeeded();
    return localNetworkResult;
  }

  @override
  Future<bool?> openAppSettings() async {
    calls.add('appSettings');
    _throwIfNeeded();
    return appSettingsResult;
  }

  @override
  Future<bool?> openDefaultLinkSettings() async {
    calls.add('defaultLinks');
    _throwIfNeeded();
    return defaultLinkResult;
  }

  void _throwIfNeeded() {
    final currentError = error;
    if (currentError != null) throw currentError;
  }
}

void main() {
  group('AppPermissions', () {
    test('Android 应该解析状态并转发全部设置动作', () async {
      final transport = _FakeSystemSettingsTransport();
      final permissions = AppPermissions(
        capabilities: PlatformCapabilities.android,
        transport: transport,
      );

      expect(
        await permissions.status(),
        isA<PermissionSnapshot>()
            .having(
              (snapshot) => snapshot.install,
              'install',
              PermissionState.denied,
            )
            .having(
              (snapshot) => snapshot.battery,
              'battery',
              PermissionState.granted,
            ),
      );
      expect(await permissions.openInstallSettings(), isTrue);
      expect(await permissions.requestBattery(), isTrue);
      expect(await permissions.requestLocalNetwork(), isTrue);
      expect(await permissions.openAppSettings(), isTrue);
      expect(await permissions.openDefaultLinkSettings(), isTrue);
      expect(transport.calls, [
        'status',
        'install',
        'battery',
        'localNetwork',
        'appSettings',
        'defaultLinks',
      ]);
    });

    test('Windows 与 iOS 应该在进入 transport 前 fail closed', () async {
      for (final (:name, :capabilities) in [
        (name: 'Windows', capabilities: PlatformCapabilities.windows),
        (name: 'iOS', capabilities: PlatformCapabilities.ios),
      ]) {
        final transport = _FakeSystemSettingsTransport();
        final permissions = AppPermissions(
          capabilities: capabilities,
          transport: transport,
        );

        expect(await permissions.status(), PermissionSnapshot.unknown);
        expect(await permissions.openInstallSettings(), isFalse);
        expect(await permissions.requestBattery(), isFalse);
        expect(await permissions.openAppSettings(), isFalse);
        expect(await permissions.openDefaultLinkSettings(), isFalse);
        expect(transport.calls, isEmpty, reason: name);
      }
    });

    test('本地网络权限应该保留 null/异常时的兼容语义', () async {
      final transport = _FakeSystemSettingsTransport()
        ..localNetworkResult = null;
      final permissions = AppPermissions(
        capabilities: PlatformCapabilities.android,
        transport: transport,
      );
      expect(await permissions.requestLocalNetwork(), isTrue);

      transport.error = MissingPluginException();
      expect(await permissions.requestLocalNetwork(), isTrue);

      transport.error = PlatformException(code: 'denied');
      expect(await permissions.requestLocalNetwork(), isFalse);
    });

    test('状态未知值和 transport 异常应该返回 conservative fallback', () async {
      final transport = _FakeSystemSettingsTransport()
        ..statusValue = {'install': 'unexpected', 'battery': null};
      final permissions = AppPermissions(
        capabilities: PlatformCapabilities.android,
        transport: transport,
      );

      final unknownStatus = await permissions.status();
      expect(unknownStatus.install, PermissionState.unknown);
      expect(unknownStatus.battery, PermissionState.unknown);

      transport.error = StateError('transport failed');
      final failedStatus = await permissions.status();
      expect(failedStatus.install, PermissionState.unknown);
      expect(failedStatus.battery, PermissionState.unknown);
      expect(await permissions.openAppSettings(), isFalse);
    });
  });
}
