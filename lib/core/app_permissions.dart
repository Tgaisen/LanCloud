import 'package:flutter/services.dart';

import 'platform_capabilities.dart';

/// 权限状态。
enum PermissionState {
  /// 已授权 / 已允许。
  granted,

  /// 未授权，可以再次弹系统请求。
  denied,

  /// 已被系统记住拒绝，只能到系统设置里手动开启。
  blocked,

  /// 当前平台不支持（非 Android）。
  unknown,
}

/// 安装应用 / 电池优化两项权限的状态快照。
///
/// 相机权限已不再需要：扫码改为从相册选图识别（见 ui/scan_page.dart）。
class PermissionSnapshot {
  const PermissionSnapshot({required this.install, required this.battery});

  final PermissionState install;
  final PermissionState battery;

  static const unknown = PermissionSnapshot(
    install: PermissionState.unknown,
    battery: PermissionState.unknown,
  );
}

/// Android 原生权限与系统设置通道。
abstract interface class SystemSettingsTransport {
  Future<Map<Object?, Object?>?> status();

  Future<bool?> openInstallSettings();

  Future<bool?> requestBattery();

  Future<bool?> requestLocalNetwork();

  Future<bool?> openAppSettings();

  Future<bool?> openDefaultLinkSettings();
}

final class _ChannelSystemSettingsTransport implements SystemSettingsTransport {
  const _ChannelSystemSettingsTransport();

  static const _channel = MethodChannel('lancloud/permissions');

  @override
  Future<Map<Object?, Object?>?> status() =>
      _channel.invokeMethod<Map<Object?, Object?>>('status');

  @override
  Future<bool?> openInstallSettings() =>
      _channel.invokeMethod<bool>('openInstallSettings');

  @override
  Future<bool?> requestBattery() =>
      _channel.invokeMethod<bool>('requestBattery');

  @override
  Future<bool?> requestLocalNetwork() =>
      _channel.invokeMethod<bool>('requestLocalNetwork');

  @override
  Future<bool?> openAppSettings() =>
      _channel.invokeMethod<bool>('openAppSettings');

  @override
  Future<bool?> openDefaultLinkSettings() =>
      _channel.invokeMethod<bool>('openDefaultLinksSettings');
}

/// 权限管理：查询状态并发起系统设置动作。
///
/// Android 原生能力由静态平台矩阵控制；测试中可以替换 [instance] 或注入
/// [SystemSettingsTransport]。
class AppPermissions {
  AppPermissions({
    PlatformCapabilities? capabilities,
    SystemSettingsTransport? transport,
  }) : capabilities = capabilities ?? PlatformCapabilities.current,
       _transport = transport ?? const _ChannelSystemSettingsTransport();

  static AppPermissions instance = AppPermissions();

  final PlatformCapabilities capabilities;
  final SystemSettingsTransport _transport;

  Future<PermissionSnapshot> status() async {
    if (!capabilities.supportsPermissionManagement) {
      return PermissionSnapshot.unknown;
    }
    try {
      final raw = await _transport.status();
      if (raw == null) return PermissionSnapshot.unknown;
      return PermissionSnapshot(
        install: _parse(raw['install']),
        battery: _parse(raw['battery']),
      );
    } on PlatformException {
      return PermissionSnapshot.unknown;
    } on MissingPluginException {
      return PermissionSnapshot.unknown;
    } catch (_) {
      return PermissionSnapshot.unknown;
    }
  }

  /// 打开「安装未知应用」设置页。
  Future<bool> openInstallSettings() {
    if (!capabilities.supportsPermissionManagement) {
      return Future<bool>.value(false);
    }
    return _invokeBool(_transport.openInstallSettings);
  }

  /// 请求忽略电池优化（系统弹窗）。
  Future<bool> requestBattery() {
    if (!capabilities.supportsPermissionManagement) {
      return Future<bool>.value(false);
    }
    return _invokeBool(_transport.requestBattery);
  }

  /// 请求「本地网络」权限：Android 17（API 37）/ targetSdk 37 起访问局域网必需。
  /// 低版本 Android 与桌面平台没有这个限制，视为已授权。
  Future<bool> requestLocalNetwork() async {
    try {
      return await _transport.requestLocalNetwork() ?? true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 打开应用详情设置页。
  Future<bool> openAppSettings() {
    if (!capabilities.supportsAppSettingsPage) {
      return Future<bool>.value(false);
    }
    return _invokeBool(_transport.openAppSettings);
  }

  /// 打开系统的「默认打开链接」设置页（把蓝奏云分享链接交给本应用）。
  Future<bool> openDefaultLinkSettings() {
    if (!capabilities.supportsDefaultLinkSettings) {
      return Future<bool>.value(false);
    }
    return _invokeBool(_transport.openDefaultLinkSettings);
  }

  Future<bool> _invokeBool(Future<bool?> Function() invoke) async {
    try {
      return await invoke() ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static PermissionState _parse(Object? raw) => switch (raw) {
    'granted' => PermissionState.granted,
    'denied' => PermissionState.denied,
    'blocked' => PermissionState.blocked,
    _ => PermissionState.unknown,
  };
}
