import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MD3E 控件都从 `m3e_core` 来，业务代码只认 `lib/ui/m3e.dart` 这个出口：
/// 出口里按名字逐个 `show`，业务代码不直接 import 第三方包。
///
/// 这两个测试就是这条约定的哨兵——裸 import 会让组件的默认值 / 语义在升级时
/// 各处漂移，也让「换哪个包」这件事重新变成全局改。
void main() {
  test('只有 m3e.dart / m3e_pull_refresh.dart 能直连 m3e_core', () {
    // 出口本身，以及下拉刷新（它直连 m3e_core 拿 motion / 触感 / 小球）。
    const allowed = <String>{'lib/ui/m3e.dart', 'lib/ui/m3e_pull_refresh.dart'};
    final directive = RegExp(
      "^\\s*(?:import|export)\\s+'package:m3e_core/",
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

  test('出口按名字逐个 show，不整包透出', () {
    final source = File('lib/ui/m3e.dart').readAsStringSync();
    final exports = RegExp("export\\s+'package:m3e_core/[^']+'\\s*(show\\b)?")
        .allMatches(source);

    expect(
      exports.where((m) => m.group(1) == null),
      isEmpty,
      reason: '整包 export 会把 m3e_core 的全部类型透给业务代码，必须逐个 show。',
    );
    expect(exports, isNotEmpty, reason: '出口至少要透出 m3e_core 的组件。');
  });
}
