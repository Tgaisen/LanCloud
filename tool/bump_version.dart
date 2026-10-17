// ignore_for_file: avoid_print
// 开发构建版本号：把当前版本的 Seq +1，并同步写回 pubspec.yaml 与
// lib/core/app_info.dart。
//
// 用法（在仓库根目录）：
//   dart run tool/bump_version.dart            # Seq +1（每次安装 / 分发前跑）
//   dart run tool/bump_version.dart --dry-run  # 只打印结果，不写文件
//   dart run tool/bump_version.dart --set 26.2.0-pre.1   # 换内容更新序号
//
// 规则（README「版本号规范」）：每次要安装 / 分发的构建都换一个新版本名，
// versionCode 由分段公式推出、天然只增不减，就不会出现需要降级安装的情况。
// 同一版本号重复构建只适合本机覆盖调试，不要用来分发。
import 'dart:io';

import 'package:lancloud/core/update/release_info.dart';

void main(List<String> args) {
  var dryRun = false;
  String? explicitName;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg == '--set') {
      if (i + 1 >= args.length) {
        _fail('--set 后面要跟版本名，例如 26.2.0-pre.1');
      }
      explicitName = args[++i];
    } else if (arg == '--help' || arg == '-h') {
      _usage();
      return;
    } else {
      _fail('未知参数：$arg（--help 查看用法）');
    }
  }

  final pubspec = File('pubspec.yaml');
  final info = File('lib/core/app_info.dart');
  if (!pubspec.existsSync() || !info.existsSync()) {
    _fail('请在仓库根目录运行（找不到 pubspec.yaml / lib/core/app_info.dart）');
  }

  final pubspecText = pubspec.readAsStringSync();
  final match = RegExp(
    r'^version:\s*(\S+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspecText);
  if (match == null) {
    _fail('pubspec.yaml 里的 version 需要写成 版本名+versionCode');
  }
  final currentName = match.group(1)!;
  final currentCode = int.parse(match.group(2)!);
  final expectedCurrent = versionCodeOf(currentName);
  if (expectedCurrent == null) _fail('当前版本名不符合规范：$currentName');
  if (expectedCurrent != currentCode) {
    _fail(
      '当前 versionCode 与公式不一致：应为 $expectedCurrent，'
      'pubspec 写的是 $currentCode',
    );
  }

  final nextName = explicitName ?? _nextName(currentName);
  final nextCode = versionCodeOf(nextName);
  if (nextCode == null) _fail('新版本名不符合规范：$nextName');
  if (nextCode <= currentCode) {
    _fail(
      '新版本 versionCode($nextCode) 必须大于当前($currentCode)：'
      '$currentName → $nextName',
    );
  }

  print('$currentName ($currentCode)  →  $nextName ($nextCode)');
  if (dryRun) {
    print('（dry-run：未写文件）');
    return;
  }

  pubspec.writeAsStringSync(
    pubspecText.replaceFirst(
      RegExp(r'^version:.*$', multiLine: true),
      'version: $nextName+$nextCode',
    ),
  );
  var infoText = info.readAsStringSync();
  infoText = infoText.replaceFirst(
    RegExp(r"const String appVersion = '[^']*';"),
    "const String appVersion = '$nextName';",
  );
  infoText = infoText.replaceFirst(
    RegExp(r'const int appBuild = \d+;'),
    'const int appBuild = $nextCode;',
  );
  info.writeAsStringSync(infoText);
  print('已更新 pubspec.yaml 与 lib/core/app_info.dart');
}

/// 下一个版本名：当前阶段的 Seq +1；正式版之后进入下一个热修号的 pre.1。
String _nextName(String name) {
  final match = RegExp(
    r'^(\d{2})\.(\d+)\.(\d+)(?:-(snapshot|pre|beta|rc)\.(\d+))?$',
  ).firstMatch(name);
  if (match == null) _fail('版本名不符合规范：$name');
  final stage = match.group(4);
  if (stage == null) {
    final hotfix = int.parse(match.group(3)!) + 1;
    return '${match.group(1)}.${match.group(2)}.$hotfix-pre.1';
  }
  final seq = int.parse(match.group(5)!);
  if (seq >= 999) {
    _fail(
      '$stage.$seq 已经是该阶段最后一个序号：请手动进入下一阶段'
      '（snapshot → pre → rc → 正式版），或换下一个内容更新版本',
    );
  }
  return '${match.group(1)}.${match.group(2)}.${match.group(3)}'
      '-$stage.${seq + 1}';
}

void _usage() {
  print('''用法：
  dart run tool/bump_version.dart               # Seq +1（安装 / 分发前）
  dart run tool/bump_version.dart --dry-run     # 只打印结果
  dart run tool/bump_version.dart --set <版本名> # 指定版本名（换内容更新序号）

会同步更新 pubspec.yaml 与 lib/core/app_info.dart，并按 README 的分段公式
重新计算 versionCode。''');
}

Never _fail(String message) {
  stderr.writeln('错误：$message');
  exit(1);
}
