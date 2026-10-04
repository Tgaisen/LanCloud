import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_info.dart';

/// 版本号规范（README「版本号规范」）：
/// versionName = 年份.内容更新序号.热修号，
/// versionCode = YY * 10000 + 内容更新序号 * 100 + 热修号（26.1.0 → 260100）。
void main() {
  test('pubspec 与 app_info 的版本号一致', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .map((l) => l.trim())
        .firstWhere((l) => l.startsWith('version:'));
    final match = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)$',
    ).firstMatch(line);
    expect(match, isNotNull, reason: 'pubspec.yaml 的 version 需要写成 x.y.z+build');
    expect(match!.group(1), appVersion);
    expect(int.parse(match.group(2)!), appBuild);
  });

  test('正式版的 versionCode 按公式推算（过渡版本不受约束）', () {
    // 0.8.x 等正式版之前的版本号跳过；26.1.0 这类正式版必须符合公式。
    final match = RegExp(r'^(\d{2})\.(\d+)\.(\d+)$').firstMatch(appVersion);
    if (match == null) return;
    final expected = int.parse(match.group(1)!) * 10000 +
        int.parse(match.group(2)!) * 100 +
        int.parse(match.group(3)!);
    expect(
      appBuild,
      expected,
      reason: 'versionCode 应为 YY * 10000 + 内容更新序号 * 100 + 热修号',
    );
  });
}
