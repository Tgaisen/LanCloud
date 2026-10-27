import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/app.dart';
import 'package:lancloud/ui/common.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final theme = buildLanCloudTheme(
    brightness: Brightness.light,
    seed: const Color(0xFF2E6BE6),
    oledDark: false,
  );

  testWidgets('带数字角标的分组小标题沿用设置页的 MD3E 强调样式', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: SectionHeader(title: '收藏夹', count: 3)),
      ),
    );

    final title = tester.widget<Text>(find.text('收藏夹'));
    expect(title.style?.fontWeight, FontWeight.w700);
    expect(title.style?.color, theme.colorScheme.primary);

    final padding = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(SectionHeader),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(padding.padding, const EdgeInsets.fromLTRB(4, 16, 4, 8));
  });

  testWidgets('单行提示卡的文字在容器内垂直居中', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Center(
            child: SizedBox(width: 400, child: InfoHintCard(text: '单行提示')),
          ),
        ),
      ),
    );

    final row = tester.widget<Row>(
      find
          .descendant(of: find.byType(InfoHintCard), matching: find.byType(Row))
          .first,
    );
    expect(row.crossAxisAlignment, CrossAxisAlignment.center);

    final surface = find
        .descendant(
          of: find.byType(InfoHintCard),
          matching: find.byType(Container),
        )
        .first;
    expect(
      tester.getCenter(find.text('单行提示')).dy,
      moreOrLessEquals(tester.getCenter(surface).dy, epsilon: 0.5),
    );
  });

  testWidgets('宽屏 SnackBar 使用最大宽度并在视口内居中', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => Theme(
          data: withResponsiveSnackBarWidth(
            Theme.of(context),
            MediaQuery.sizeOf(context).width,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('提示'))),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    final material = find.descendant(
      of: find.byType(SnackBar),
      matching: find.byType(Material),
    );
    expect(tester.getSize(material).width, kSnackBarMaxWidth);
    expect(tester.getCenter(material).dx, 500);
  });
}
