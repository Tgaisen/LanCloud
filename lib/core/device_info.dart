import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

import 'platform_support.dart';

/// 反馈用的设备 / 系统信息（「关于 - 相关信息」弹窗）。
///
/// Android 走 `lancloud/system` 的原生通道取 `Build.*` 字段（厂商 / 型号 /
/// 系统版本 / API 级别 / 系统构建号 / 支持的 ABI）；其它平台退回 `dart:io`
/// 的 [Platform] 信息。读取失败时返回空字段，弹窗里显示「—」。
class DeviceInfo {
  const DeviceInfo({
    required this.device,
    required this.system,
    required this.systemBuild,
    required this.architectures,
    this.versionCode,
  });

  /// 厂商 + 型号（Android：`HUAWEI NOH-AN00`；Windows：计算机名）。
  final String device;

  /// 系统版本（Android：`Android 12 (31)`）。
  final String system;

  /// 系统构建号（Android：`Build.DISPLAY`；其它平台为空）。
  final String systemBuild;

  /// 支持的 CPU 架构（`arm64-v8a, armeabi-v7a, armeabi` / `x64`）。
  final String architectures;

  /// Android 上系统里实际安装的 versionCode（拆分包按 ABI 加过偏移）；
  /// 其它平台没有 Android versionCode，为 null。
  final int? versionCode;

  static Future<DeviceInfo> load() async {
    if (PlatformSupport.isAndroid) {
      try {
        final map = await const MethodChannel('lancloud/system')
            .invokeMapMethod<String, Object?>('deviceInfo');
        if (map != null) {
          final manufacturer = '${map['manufacturer'] ?? ''}'.trim();
          final model = '${map['model'] ?? ''}'.trim();
          final abis =
              (map['abis'] as List?)?.map((e) => '$e').toList() ??
              const <String>[];
          return DeviceInfo(
            device: [manufacturer, model].where((s) => s.isNotEmpty).join(' '),
            system: 'Android ${map['release'] ?? ''} (${map['sdkInt'] ?? '?'})',
            systemBuild: '${map['display'] ?? ''}',
            architectures: abis.join(', '),
            versionCode: (map['versionCode'] as num?)?.toInt(),
          );
        }
      } catch (_) {
        // 通道不可用（测试 / 异常）：走下面的通用信息
      }
    }
    if (Platform.isWindows) {
      final manufacturer = _regString(_winBios, 'SystemManufacturer');
      final model = _regString(_winBios, 'SystemProductName');
      final device = [
        manufacturer,
        model,
      ].whereType<String>().where((s) => s.isNotEmpty).join(' ');

      final product = _regString(
        _winCurrentVersion,
        'ProductName',
      )?.replaceAll('"', '');
      final build = _regString(_winCurrentVersion, 'CurrentBuild');
      final major =
          _regDword(_winCurrentVersion, 'CurrentMajorVersionNumber') ?? 10;
      final minor =
          _regDword(_winCurrentVersion, 'CurrentMinorVersionNumber') ?? 0;
      final buildNumber = int.tryParse(build ?? '');
      // Windows 11 的 ProductName 仍可能沿用 "Windows 10 …"：按 build ≥ 22000
      // 把显示名纠正成 Windows 11（系统信息面板的版本也是这么显示的）。
      var systemName = product;
      if (systemName != null &&
          buildNumber != null &&
          buildNumber >= 22000 &&
          systemName.startsWith('Windows 10')) {
        systemName = systemName.replaceFirst('Windows 10', 'Windows 11');
      }
      final system = [
        ?systemName,
        if (build != null) '$major.$minor (Build $build)',
      ].join(' ');
      return DeviceInfo(
        device: device.isEmpty ? Platform.localHostname : device,
        system: system.isEmpty
            ? Platform.operatingSystemVersion.replaceAll('"', '').trim()
            : system,
        systemBuild: '',
        architectures: 'x64',
      );
    }
    return DeviceInfo(
      device: Platform.isWindows || Platform.isMacOS || Platform.isLinux
          ? Platform.localHostname
          : Platform.operatingSystem,
      // Windows 的 operatingSystemVersion 已经带系统名（`"Windows 10 …"`），
      // 不再重复前缀；其它平台按「系统 + 版本」拼接。
      system: Platform.isWindows
          ? Platform.operatingSystemVersion
          : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      systemBuild: '',
      // 桌面端只发 x64 构建；移动端非 Android 只做兜底展示
      architectures: Platform.isWindows ? 'x64' : Platform.operatingSystem,
    );
  }
}

const String _winCurrentVersion =
    r'SOFTWARE\Microsoft\Windows NT\CurrentVersion';
const String _winBios = r'HARDWARE\DESCRIPTION\System\BIOS';

/// 读注册表字符串值（REG_SZ）；读不到返回 null。
String? _regString(String subKey, String valueName) {
  final sub = subKey.toNativeUtf16();
  final name = valueName.toNativeUtf16();
  final size = calloc<Uint32>()..value = 1024;
  final buffer = calloc<Uint8>(size.value);
  try {
    final status = RegGetValue(
      HKEY_LOCAL_MACHINE,
      sub,
      name,
      RRF_RT_REG_SZ,
      nullptr,
      buffer,
      size,
    );
    if (status != ERROR_SUCCESS) return null;
    final text = buffer.cast<Utf16>().toDartString().trim();
    return text.isEmpty ? null : text;
  } finally {
    calloc.free(buffer);
    calloc.free(size);
    calloc.free(name);
    calloc.free(sub);
  }
}

/// 读注册表 DWORD 值；读不到返回 null。
int? _regDword(String subKey, String valueName) {
  final sub = subKey.toNativeUtf16();
  final name = valueName.toNativeUtf16();
  final size = calloc<Uint32>()..value = 4;
  final buffer = calloc<Uint32>();
  try {
    final status = RegGetValue(
      HKEY_LOCAL_MACHINE,
      sub,
      name,
      RRF_RT_REG_DWORD,
      nullptr,
      buffer,
      size,
    );
    if (status != ERROR_SUCCESS) return null;
    return buffer.value;
  } finally {
    calloc.free(buffer);
    calloc.free(size);
    calloc.free(name);
    calloc.free(sub);
  }
}
