import 'dart:ffi';

import 'package:flutter/foundation.dart';

/// 应用信息：发版时与 pubspec.yaml 的 version 一起更新（版本号规范见 README）。
const String appVersion = '26.1.0-pre.30';
const int appBuild = 260100230;

/// 当前构建类型。发布包不显示后缀，Profile / Debug 统一追加构建标记。
enum AppBuildMode { debug, profile, release }

const AppBuildMode currentAppBuildMode = kDebugMode
    ? AppBuildMode.debug
    : kProfileMode
    ? AppBuildMode.profile
    : AppBuildMode.release;

extension AppBuildModeInfo on AppBuildMode {
  String get label => switch (this) {
    AppBuildMode.debug => 'Debug',
    AppBuildMode.profile => 'Profile',
    AppBuildMode.release => 'Release',
  };
}

/// 按构建类型生成应用显示名；Release 保持原来的基础名称。
String appDisplayName(
  String baseName, [
  AppBuildMode mode = currentAppBuildMode,
]) => mode == AppBuildMode.release ? baseName : '$baseName ${mode.label}';

/// 当前进程实际运行的 ABI。Android 的 universal APK 在运行时也会落到这里
/// 选中的具体 ABI，因此「相关信息」能反映真正加载的原生库架构。
String abiLabel(Abi abi) {
  if (abi == Abi.androidArm) return 'armeabi-v7a';
  if (abi == Abi.androidArm64) return 'arm64-v8a';
  if (abi == Abi.androidIA32) return 'x86';
  if (abi == Abi.androidX64) return 'x86_64';
  if (abi == Abi.androidRiscv64) return 'riscv64';
  if (abi == Abi.iosArm) return 'arm';
  if (abi == Abi.iosArm64 || abi == Abi.macosArm64) return 'arm64';
  if (abi == Abi.iosX64 || abi == Abi.macosX64) return 'x64';
  if (abi == Abi.windowsArm64) return 'arm64';
  if (abi == Abi.windowsIA32) return 'x86';
  if (abi == Abi.windowsX64) return 'x64';
  if (abi == Abi.linuxArm) return 'arm';
  if (abi == Abi.linuxArm64 || abi == Abi.linuxRiscv64) {
    return abi == Abi.linuxRiscv64 ? 'riscv64' : 'arm64';
  }
  if (abi == Abi.linuxIA32) return 'x86';
  if (abi == Abi.linuxX64) return 'x64';
  if (abi == Abi.linuxRiscv32) return 'riscv32';
  return abi.toString();
}

/// 开源协议与项目地址。
const String projectUrl = 'https://github.com/Tgaisen/LanCloud';

/// 构建信息：发布脚本（tools/release/build_*.ps1）用 --dart-define 注入；
/// [gitCommit] 是完整 hash（40 位），本地直接运行 / 普通构建时为空，
/// 关于页显示为「—」且不显示「详情」按钮。
const String buildTime = String.fromEnvironment('BUILD_TIME');
const String gitCommit = String.fromEnvironment('GIT_COMMIT');

/// 构建时间的展示文本。
///
/// 发布脚本注入的是带 `Z` 的 UTC 时间（GitHub Actions runner 为 UTC），
/// 显示时转成本机时区；早期构建注入的 `yyyy-MM-dd HH:mm:ss`（无时区）按
/// 本地时间理解，原样显示；解析失败时原样返回。
String buildTimeForDisplay() => formatBuildTimeForDisplay(buildTime);

/// [buildTimeForDisplay] 的纯函数版本（便于单测）。
String formatBuildTimeForDisplay(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return text;
  final local = parsed.isUtc ? parsed.toLocal() : parsed;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

/// 用户协议 / 隐私政策版本：条款有实质修改时 +1，会重新请求用户同意。
const int termsVersion = 1;
