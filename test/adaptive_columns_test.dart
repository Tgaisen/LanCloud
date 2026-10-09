import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';

/// 设置测试窗口的逻辑宽度（高度固定 800dp）。
void useWindow(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 800);
}

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  test('列数按 M3 窗口档位：<600 → 1 列，600–839 → 2 列，≥840 → 3 列', () {
    expect(adaptiveColumnsForWidth(320), 1);
    expect(adaptiveColumnsForWidth(599), 1);
    expect(adaptiveColumnsForWidth(600), 2);
    expect(adaptiveColumnsForWidth(839), 2);
    expect(adaptiveColumnsForWidth(840), 3);
    expect(adaptiveColumnsForWidth(1280), 3);
  });

  testWidgets('SegmentedList(adaptive) 按窗口宽度铺成 1 / 2 / 3 列', (tester) async {
    addTearDown(tester.view.reset);

    Future<List<Offset>> pumpWidth(double width) async {
      useWindow(tester, width);
      await tester.pumpWidget(
        host(
          SegmentedList(
            adaptive: true,
            children: const [
              SizedBox(height: 48, child: Center(child: Text('甲'))),
              SizedBox(height: 48, child: Center(child: Text('乙'))),
              SizedBox(height: 48, child: Center(child: Text('丙'))),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      return [
        for (final text in ['甲', '乙', '丙']) tester.getTopLeft(find.text(text)),
      ];
    }

    // Compact：单列纵向排列
    final compact = await pumpWidth(500);
    expect(compact[0].dy, lessThan(compact[1].dy));
    expect(compact[1].dy, lessThan(compact[2].dy));
    expect(compact[0].dx, compact[1].dx);

    // Medium：2 列，前两项同一行
    final medium = await pumpWidth(700);
    expect(medium[0].dy, medium[1].dy);
    expect(medium[0].dx, lessThan(medium[1].dx));
    expect(medium[2].dy, greaterThan(medium[0].dy));

    // Expanded：3 列，三项同一行
    final expanded = await pumpWidth(900);
    expect(expanded[0].dy, expanded[1].dy);
    expect(expanded[1].dy, expanded[2].dy);
    expect(expanded[0].dx, lessThan(expanded[1].dx));
    expect(expanded[1].dx, lessThan(expanded[2].dx));
  });

  testWidgets('AdaptiveSliverRows：宽窗口按行铺开，窄窗口退化为单列', (tester) async {
    addTearDown(tester.view.reset);

    Future<List<Offset>> pumpWidth(double width) async {
      useWindow(tester, width);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                AdaptiveSliverRows(
                  itemCount: 5,
                  itemBuilder: (context, index) => SizedBox(
                    height: 40,
                    child: Center(child: Text('项目$index')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return [for (var i = 0; i < 5; i++) tester.getTopLeft(find.text('项目$i'))];
    }

    final compact = await pumpWidth(500);
    expect(compact[1].dy, greaterThan(compact[0].dy));
    expect(compact[0].dx, compact[1].dx);

    final expanded = await pumpWidth(900);
    expect(expanded[0].dy, expanded[1].dy);
    expect(expanded[1].dy, expanded[2].dy);
    // 第 4 项换到第二行
    expect(expanded[2].dy, lessThan(expanded[3].dy));
    expect(expanded[3].dy, expanded[4].dy);
  });

  testWidgets('多列下每个条目独立成卡：四周外侧圆角，按下才放大', (tester) async {
    useWindow(tester, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        SegmentedList(
          adaptive: true,
          children: const [
            SizedBox(height: 48, child: Center(child: Text('甲'))),
            SizedBox(height: 48, child: Center(child: Text('乙'))),
            SizedBox(height: 48, child: Center(child: Text('丙'))),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    List<BorderRadiusGeometry?> radii() => tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((c) => (c.decoration as BoxDecoration?)?.borderRadius)
        .toList();

    // 未按下：每个条目（包括下标 1、2）四周都是外侧圆角 16dp，
    // 不能因为组内下标被判成“组内相邻处”的 4dp 内圆角
    for (final radius in radii()) {
      expect(radius, BorderRadius.circular(16));
    }

    // 按住第二项：只有它放大到 pressedRadius，其余保持 16dp
    final gesture = await tester.startGesture(tester.getCenter(find.text('乙')));
    await tester.pump(const Duration(milliseconds: 300));
    final pressed = radii();
    expect(pressed[1], BorderRadius.circular(28));
    expect(pressed[0], BorderRadius.circular(16));
    expect(pressed[2], BorderRadius.circular(16));
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
