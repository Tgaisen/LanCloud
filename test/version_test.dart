import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_info.dart';

/// 版本号规范（README「版本号规范」）：
/// versionName = 年份.内容更新序号.热修号[-阶段.序号]，
/// versionCode = YY*10_000_000 + Drop*100_000 + Hotfix*10_000 + Stage*1_000 + Seq
/// 阶段码：snapshot=1 / pre(beta)=2 / rc=3 / 正式版=9（且 Seq 固定 999）。
int _code({
  required int yy,
  required int drop,
  required int hotfix,
  required int stage,
  required int seq,
}) => yy * 10000000 + drop * 100000 + hotfix * 10000 + stage * 1000 + seq;

/// 按规范换算 versionCode；不符合规范时返回 null。
int? versionCodeFor(String version) {
  final release = RegExp(r'^(\d{2})\.(\d+)\.(\d+)$').firstMatch(version);
  if (release != null) {
    return _code(
      yy: int.parse(release.group(1)!),
      drop: int.parse(release.group(2)!),
      hotfix: int.parse(release.group(3)!),
      stage: 9,
      seq: 999,
    );
  }
  final pre = RegExp(r'^(\d{2})\.(\d+)\.(\d+)-(snapshot|pre|beta|rc)\.(\d+)$')
      .firstMatch(version);
  if (pre == null) return null;
  final stage = switch (pre.group(4)!) {
    'snapshot' => 1,
    'pre' || 'beta' => 2,
    'rc' => 3,
    _ => 0,
  };
  return _code(
    yy: int.parse(pre.group(1)!),
    drop: int.parse(pre.group(2)!),
    hotfix: int.parse(pre.group(3)!),
    stage: stage,
    seq: int.parse(pre.group(5)!),
  );
}

void main() {
  test('pubspec 与 app_info 的版本号一致', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .map((l) => l.trim())
        .firstWhere((l) => l.startsWith('version:'));
    final match = RegExp(r'^version:\s*([0-9][^+\s]*)\+(\d+)$')
        .firstMatch(line);
    expect(
      match,
      isNotNull,
      reason: 'pubspec.yaml 的 version 需要写成 版本号+versionCode',
    );
    expect(match!.group(1), appVersion);
    expect(int.parse(match.group(2)!), appBuild);
  });

  test('versionCode 按分段公式推算（snapshot / pre / rc / 正式版）', () {
    expect(versionCodeFor('26.1.0-snapshot.1'), 260101001);
    expect(versionCodeFor('26.1.0-pre.1'), 260102001);
    expect(versionCodeFor('26.1.0-rc.1'), 260103001);
    expect(versionCodeFor('26.1.0'), 260109999);
    expect(versionCodeFor('26.1.1-rc.1'), 260113001);
    expect(versionCodeFor('26.1.1'), 260119999);
    // 不合规范的版本号返回 null
    expect(versionCodeFor('26.1.0-rc'), isNull);
    expect(versionCodeFor('26.1.0-alpha.1'), isNull);
  });

  test('阶段顺序：snapshot < pre < rc < 正式版 < 下一个热修的预发布', () {
    final codes = [
      versionCodeFor('26.1.0-snapshot.1'),
      versionCodeFor('26.1.0-pre.1'),
      versionCodeFor('26.1.0-rc.1'),
      versionCodeFor('26.1.0'),
      versionCodeFor('26.1.1-rc.1'),
      versionCodeFor('26.1.1'),
    ];
    expect(codes.every((c) => c != null), isTrue);
    for (var i = 1; i < codes.length; i++) {
      expect(codes[i]! > codes[i - 1]!, isTrue, reason: '$codes');
    }
  });

  test('当前版本号必须符合公式', () {
    expect(versionCodeFor(appVersion), appBuild);
  });
}
