import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_info.dart';

/// 版本号规范（docs/VERSIONING.md）：
/// versionName = 年份.内容更新序号.热修号[-阶段.序号]，
/// versionCode = YY*10^7 + Drop*10^5 + Hotfix*10^4 + ABI*10^3 + Stage*10^2 + Seq
/// （ABI=0 的基准号；阶段：snapshot=1 / pre(beta)=2 / rc=3 / 正式版=9 且 Seq=99）。
int _code({
  required int yy,
  required int drop,
  required int hotfix,
  required int stage,
  required int seq,
}) => yy * 10000000 + drop * 100000 + hotfix * 10000 + stage * 100 + seq;

/// 按规范换算 versionCode；不符合规范时返回 null。
int? versionCodeFor(String version) {
  final release = RegExp(r'^(\d{2})\.(\d+)\.(\d+)$').firstMatch(version);
  if (release != null) {
    return _code(
      yy: int.parse(release.group(1)!),
      drop: int.parse(release.group(2)!),
      hotfix: int.parse(release.group(3)!),
      stage: 9,
      seq: 99,
    );
  }
  final pre = RegExp(r'^(\d{2})\.(\d+)\.(\d+)-(snapshot|pre|beta|rc)\.(\d+)$')
      .firstMatch(version);
  if (pre == null) return null;
  final seq = int.parse(pre.group(5)!);
  // Seq 只占两位（01–99）
  if (seq > 99) return null;
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
    seq: seq,
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
    expect(versionCodeFor('26.1.0-snapshot.1'), 260100101);
    expect(versionCodeFor('26.1.0-pre.1'), 260100201);
    expect(versionCodeFor('26.1.0-pre.99'), 260100299);
    expect(versionCodeFor('26.1.0-rc.1'), 260100301);
    expect(versionCodeFor('26.1.0'), 260100999);
    expect(versionCodeFor('26.1.1-rc.1'), 260110301);
    expect(versionCodeFor('26.1.1'), 260110999);
    // 不合规范的版本号返回 null
    expect(versionCodeFor('26.1.0-rc'), isNull);
    expect(versionCodeFor('26.1.0-alpha.1'), isNull);
    // Seq 只有两位：100 会和阶段位撞车
    expect(versionCodeFor('26.1.0-pre.100'), isNull);
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
