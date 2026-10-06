import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';

void main() {
  testWidgets('SectionCard 折叠后隐藏内容并旋转三角，展开后恢复', (tester) async {
    var expanded = true;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => SectionCard(
                title: '快速访问',
                expanded: expanded,
                onToggle: () => setState(() => expanded = !expanded),
                child: const Text('内容'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('内容'), findsOneWidget);
    expect(
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
      0.25,
    );

    // 折叠按钮是标题行右侧的 IconButton（点标题文字不再触发）
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    // 内容常驻在树里（整组高度过渡，条目不会重建），但被裁到 0 高
    expect(find.text('内容'), findsOneWidget);
    expect(tester.getSize(find.byType(SizeTransition)).height, 0);
    expect(
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
      0,
    );

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.text('内容'), findsOneWidget);
    expect(tester.getSize(find.byType(SizeTransition)).height, greaterThan(0));
  });

  testWidgets('SectionCard 出现/隐藏内容时高度动画过渡', (tester) async {
    var expanded = true;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => SectionCard(
                title: '最近使用',
                expanded: expanded,
                onToggle: () => setState(() => expanded = !expanded),
                child: const SizedBox(height: 200, width: 200),
              ),
            ),
          ),
        ),
      ),
    );
    final fullHeight = tester.getSize(find.byType(SectionCard)).height;
    expect(fullHeight, greaterThan(200));

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100)); // 动画进行中
    final midHeight = tester.getSize(find.byType(SectionCard)).height;
    expect(midHeight, greaterThan(0));
    expect(midHeight, lessThan(fullHeight));

    await tester.pumpAndSettle();
    final collapsed = tester.getSize(find.byType(SectionCard)).height;
    expect(collapsed, lessThan(midHeight));
    // 折叠后只剩标题行（展开按钮 48 + 上下留白）
    expect(collapsed, lessThan(120));
  });
}
