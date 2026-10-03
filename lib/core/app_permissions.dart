import 'package:flutter/services.dart';

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

/// 相机 / 安装应用 / 电池优化三项权限的状态快照。
class PermissionSnapshot {
  const PermissionSnapshot({
    required this.camera,
    required this.install,
    required this.battery,
  });

  final PermissionState camera;
  final PermissionState install;
  final PermissionState battery;

  static const unknown = PermissionSnapshot(
    camera: PermissionState.unknown,
    install: PermissionState.unknown,
    battery: PermissionState.unknown,
  );
}

/// 权限管理：查询状态与发起请求（Android 原生通道）。
/// 测试中可以替换 [instance] 注入桩实现。
class AppPermissions {
  AppPermissions();

  static AppPermissions instance = AppPermissions();

  static const _channel = MethodChannel('lancloud/permissions');

  Future<PermissionSnapshot> status() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('status');
      if (raw == null) return PermissionSnapshot.unknown;
      return PermissionSnapshot(
        camera: _parse(raw['camera']),
        install: _parse(raw['install']),
        battery: _parse(raw['battery']),
      );
    } on PlatformException {
      return PermissionSnapshot.unknown;
    } on MissingPluginException {
      return PermissionSnapshot.unknown;
    }
  }

  /// 请求相机权限，返回请求后的状态。
  Future<PermissionState> requestCamera() async {
    try {
      return _parse(await _channel.invokeMethod<Object?>('requestCamera'));
    } on PlatformException {
      return PermissionState.unknown;
    } on MissingPluginException {
      return PermissionState.unknown;
    }
  }

  /// 打开「安装未知应用」设置页。
  Future<bool> openInstallSettings() => _invokeBool('openInstallSettings');

  /// 请求忽略电池优化（系统弹窗）。
  Future<bool> requestBattery() => _invokeBool('requestBattery');

  /// 打开应用详情设置页。
  Future<bool> openAppSettings() => _invokeBool('openAppSettings');

  /// 打开系统的「默认打开链接」设置页（把蓝奏云分享链接交给本应用）。
  Future<bool> openDefaultLinkSettings() =>
      _invokeBool('openDefaultLinksSettings');

  Future<bool> _invokeBool(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
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
