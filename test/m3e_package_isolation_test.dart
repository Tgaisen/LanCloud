import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `m3e_core` 和 `material_3_expressive` 两个包长期共存（进度条 / 加载指示器用
/// 新包，按钮组、底部弹窗、下拉刷新小球用 m3e_core），而它们有 80+ 个同名类型。
/// 共存不出乱子的前提只有一条：**业务代码只认 lib/ui/m3e.dart 这个出口**。
///
/// 这两个测试就是这条前提的哨兵——裸 import 会让同名类型在编译期变歧义（报错
/// 还算好），更麻烦的是有人把新包的同名类型传进我们的 wrapper（类型对不上才
/// 报错，对得上的地方就静默混用两个包的观感）。
void main() {
  const m3ePackages = r'(?:m3e_core|material_3_expressive)';

  test('只有 m3e.dart / m3e_pull_refresh.dart 能直连 MD3E 包', () {
    // 出口本身，以及下拉刷新（它直连 m3e_core 拿 motion / 触感 / 小球）。
    const allowed = <String>{'lib/ui/m3e.dart', 'lib/ui/m3e_pull_refresh.dart'};
    final directive = RegExp(
      "^\\s*(?:import|export)\\s+'package:$m3ePackages/",
      multiLine: true,
    );

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (allowed.contains(path)) continue;
      if (directive.hasMatch(entity.readAsStringSync())) offenders.add(path);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '这些文件绕过了 lib/ui/m3e.dart，请改成 import 出口；'
          '确实需要直连时把它加进本测试的 allowed。',
    );
  });

  test('出口只透 m3e_core，且按名字逐个 show', () {
    final source = File('lib/ui/m3e.dart').readAsStringSync();
    final exports = RegExp(
      "export\\s+'package:$m3ePackages/[^']+'\\s*(show\\b)?",
    ).allMatches(source);

    expect(
      exports.where((m) => m.group(1) == null),
      isEmpty,
      reason: '整包 export 会把两个包的同名类型一起透给业务代码，必须逐个 show。',
    );
    // material_3_expressive 只在本文件内部用（加载指示器 / 弹出菜单都包了
    // 一层自己的 wrapper），业务代码不该直接认得它的类型。
    expect(
      exports.where((m) => m.group(0)!.contains('material_3_expressive')),
      isEmpty,
      reason: '新包不往外透；要暴露什么先在 m3e.dart 里加一层 wrapper。',
    );
  });
}
