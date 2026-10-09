import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/m3e.dart';

/// m3e_core 与应用同处 material_ui 之上，这里守住「MD3E 控件能正常渲染 /
/// 打开」这条底线（迁移前它们之间还需要一层主题桥，现已删除）。
Widget host(Widget child) => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E6BE6)),
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('MD3E 加载指示器 / 进度条能在框架主题下渲染', (tester) async {
    await tester.pumpWidget(
      host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            M3eLoadingIndicator(semanticsLabel: '加载中'),
            M3eContainedLoadingIndicator(),
            M3eLinearProgressIndicator(value: 0.5),
            M3eLinearProgressIndicator(value: 0.5, wavy: true),
            M3eCircularProgressIndicator(value: 0.25),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 32));

    expect(tester.takeException(), isNull);
    expect(find.byType(M3ELoadingIndicator), findsNWidgets(2));
    expect(find.byType(M3ELinearProgressIndicator), findsOneWidget);
    expect(find.byType(M3ELinearWavyProgressIndicator), findsOneWidget);
    expect(find.byType(M3ECircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('加载中'), findsOneWidget);
  });

  testWidgets('MD3E 模态底部弹窗能在根 Navigator 上打开', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2E6BE6),
            brightness: Brightness.dark,
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showM3EModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const M3EBottomSheet(
                    title: Text('测试弹窗'),
                    child: SizedBox(height: 120),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(M3EBottomSheet), findsOneWidget);
    expect(find.text('测试弹窗'), findsOneWidget);
  });

  test('M3E 强调排版：字号与基线一致、字重更重', () {
    // 用带完整字号 / 字重的 M3 typography 做基线比对。
    final base = Typography.dense2021;
    final emphasized = m3eEmphasizedTextTheme(base);

    expect(emphasized.titleLarge!.fontSize, base.titleLarge!.fontSize);
    expect(
      emphasized.titleLarge!.fontWeight!.value,
      greaterThan(base.titleLarge!.fontWeight!.value),
    );
    expect(emphasized.bodyMedium!.fontSize, base.bodyMedium!.fontSize);
    expect(
      emphasized.bodyMedium!.fontWeight!.value,
      greaterThan(base.bodyMedium!.fontWeight!.value),
    );
  });

  testWidgets('context.m3eEmphasizedTheme 基于已本地化的排版派生', (tester) async {
    late TextTheme base;
    late TextTheme emphasized;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFF2E6BE6)),
        home: Builder(
          builder: (context) {
            base = Theme.of(context).textTheme;
            emphasized = context.m3eEmphasizedTheme;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(emphasized.titleLarge!.fontSize, base.titleLarge!.fontSize);
    expect(
      emphasized.titleLarge!.fontWeight!.value,
      greaterThan(base.titleLarge!.fontWeight!.value),
    );
    expect(
      emphasized.labelLarge!.fontWeight!.value,
      greaterThan(base.labelLarge!.fontWeight!.value),
    );
  });
}
