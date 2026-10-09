import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';

/// 打开一个内容超高、可滚动的统一底部弹窗。
Widget sheetHost() => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => SafeArea(
              child: MeasuredSheet(
                maxHeight: 300,
                child: Column(
                  children: [
                    for (var i = 0; i < 30; i++)
                      SizedBox(
                        height: 40,
                        child: Center(child: Text('第 $i 行')),
                      ),
                  ],
                ),
              ),
            ),
          ),
          child: const Text('打开弹窗'),
        ),
      ),
    ),
  ),
);

Future<void> openSheet(WidgetTester tester) async {
  await tester.pumpWidget(sheetHost());
  await tester.tap(find.text('打开弹窗'));
  await tester.pumpAndSettle();
}

double sheetHeight(WidgetTester tester) =>
    tester.getSize(find.byType(MeasuredSheet)).height;

/// 按真实手指那样分多步拖动（一次性大位移会被弹窗自身的拖拽接管）。
Future<void> smoothDrag(
  WidgetTester tester,
  TestGesture gesture,
  double dy, {
  int steps = 10,
}) async {
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('内容超过上限时弹窗高度被限制，内部可滚动', (tester) async {
    await openSheet(tester);
    expect(sheetHeight(tester), 300);
    expect(find.text('第 0 行'), findsOneWidget);
  });

  testWidgets('滚到顶部后继续下拉，弹窗跟着一起下滑', (tester) async {
    await openSheet(tester);
    // 先向下滚动一段
    var gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeasuredSheet)),
    );
    await smoothDrag(tester, gesture, -200);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(sheetHeight(tester), 300);

    // 从顶部继续下拉：前半段滚回顶部，剩余位移带动弹窗下滑
    gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeasuredSheet)),
    );
    await smoothDrag(tester, gesture, 400, steps: 20);
    await tester.pump();
    final pulled = sheetHeight(tester);
    expect(pulled, lessThan(300));
    expect(pulled, greaterThan(0));

    // 反向拖回并松手：弹窗恢复原高度，而不是被关闭
    await smoothDrag(tester, gesture, -400, steps: 20);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(MeasuredSheet), findsOneWidget);
    expect(sheetHeight(tester), 300);
  });

  testWidgets('小幅下拉松手后弹回，不关闭弹窗', (tester) async {
    await openSheet(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeasuredSheet)),
    );
    await smoothDrag(tester, gesture, 80, steps: 8);
    await tester.pump();
    expect(sheetHeight(tester), lessThan(300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(MeasuredSheet), findsOneWidget);
    expect(sheetHeight(tester), 300);
  });

  testWidgets('下拉超过阈值松手会关闭弹窗', (tester) async {
    await openSheet(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeasuredSheet)),
    );
    await smoothDrag(tester, gesture, 320, steps: 16);
    expect(sheetHeight(tester), lessThan(200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(MeasuredSheet), findsNothing);
  });
}
