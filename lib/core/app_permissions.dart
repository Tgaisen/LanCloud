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
        install: _parse(raw['install']),
        battery: _parse(raw['battery']),
      );
    } on PlatformException {
      return PermissionSnapshot.unknown;
    } on MissingPluginException {
      return PermissionSnapshot.unknown;
    }
  }

  /// 打开「安装未知应用」设置页。
  Future<bool> openInstallSettings() => _invokeBool('openInstallSettings');

  /// 请求忽略电池优化（系统弹窗）。
  Future<bool> requestBattery() => _invokeBool('requestBattery');

  /// 请求「本地网络」权限：Android 17（API 37）/ targetSdk 37 起访问局域网必需。
  /// 低版本 Android 与桌面平台没有这个限制，视为已授权。
  Future<bool> requestLocalNetwork() async {
    try {
      return await _channel.invokeMethod<bool>('requestLocalNetwork') ?? true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return true;
    }
  }

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
