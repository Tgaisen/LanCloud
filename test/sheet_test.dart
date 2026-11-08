import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';

const _firstPage = ValueKey<String>('sheet-test-first-page');
const _secondPage = ValueKey<String>('sheet-test-second-page');

/// 打开一个内容超高、可滚动的统一底部弹窗。
///
/// 弹窗放在二级页面上，便于验证返回键关闭弹窗时不会把下面的页面一起退掉。
Widget sheetHost() => MaterialApp(
  home: Scaffold(
    key: _firstPage,
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const _SheetTestPage()),
          ),
          child: const Text('进入二级页面'),
        ),
      ),
    ),
  ),
);

class _SheetTestPage extends StatelessWidget {
  const _SheetTestPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _secondPage,
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showAppSheet<void>(
              context,
              maxHeightRatio: 0.5,
              child: Column(
                children: [
                  for (var i = 0; i < 30; i++)
                    SizedBox(height: 40, child: Center(child: Text('第 $i 行'))),
                ],
              ),
            ),
            child: const Text('打开弹窗'),
          ),
        ),
      ),
    );
  }
}

Future<void> openSheet(WidgetTester tester) async {
  await tester.pumpWidget(sheetHost());
  await tester.tap(find.text('进入二级页面'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开弹窗'));
  await tester.pumpAndSettle();
}

double sheetHeight(WidgetTester tester) =>
    tester.getSize(find.byType(MeasuredSheet)).height;

double sheetTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(BottomSheet)).dy;

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

  testWidgets('滚到顶部后继续下拉，整个弹窗跟着一起下滑', (tester) async {
    await openSheet(tester);
    final double initialTop = sheetTop(tester);
    // 先向下滚动一段
    var gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeasuredSheet)),
    );
    await smoothDrag(tester, gesture, -200);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(sheetHeight(tester), 300);

    // 从顶部继续下拉：前半段滚回顶部，剩余位移带动整个弹窗路由下滑
    gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeasuredSheet)),
    );
    await smoothDrag(tester, gesture, 400, steps: 20);
    await tester.pump();
    expect(sheetTop(tester), greaterThan(initialTop));
    expect(sheetHeight(tester), 300, reason: '下滑时应移动整个面板，而不是缩短内容');

    // 反向拖回并松手：弹窗恢复原高度，而不是被关闭
    await smoothDrag(tester, gesture, -400, steps: 20);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(MeasuredSheet), findsOneWidget);
    expect(sheetTop(tester), moreOrLessEquals(initialTop, epsilon: 0.5));
  });

  testWidgets('小幅下拉松手后弹回，不关闭弹窗', (tester) async {
    await openSheet(tester);
    final double initialTop = sheetTop(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeasuredSheet)),
    );
    await smoothDrag(tester, gesture, 80, steps: 8);
    await tester.pump();
    expect(sheetTop(tester), greaterThan(initialTop));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(MeasuredSheet), findsOneWidget);
    expect(sheetTop(tester), moreOrLessEquals(initialTop, epsilon: 0.5));
  });

  testWidgets('超过阈值时返回键只关闭弹窗，不退出下面的页面', (tester) async {
    await openSheet(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeasuredSheet)),
    );
    await smoothDrag(tester, gesture, 180, steps: 18);
    expect(sheetTop(tester), greaterThan(300), reason: '已超过松手关闭阈值');

    // 模拟内容拖动尚未结束时长按返回键：路由开始退场，随后原手势被取消。
    final Future<bool> popFuture = tester.binding.handlePopRoute();
    await gesture.cancel();
    await popFuture;
    await tester.pumpAndSettle();

    expect(find.byType(MeasuredSheet), findsNothing);
    expect(find.byKey(_secondPage), findsOneWidget);
    expect(find.byKey(_firstPage), findsNothing, reason: '二级页面不应被连带退出');

    // 再验证正常拖过阈值松手仍然会关闭弹窗。
    await tester.tap(find.text('打开弹窗'));
    await tester.pumpAndSettle();
    final releaseGesture = await tester.startGesture(
      tester.getCenter(find.byType(MeasuredSheet)),
    );
    await smoothDrag(tester, releaseGesture, 180, steps: 18);
    await releaseGesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(MeasuredSheet), findsNothing);
    expect(find.byKey(_secondPage), findsOneWidget);

    // 遮罩关闭走同一条路由退场路径，也不能因原手势取消而多退一层。
    await tester.tap(find.text('打开弹窗'));
    await tester.pumpAndSettle();
    final barrierDrag = await tester.startGesture(
      tester.getCenter(find.byType(MeasuredSheet)),
    );
    await smoothDrag(tester, barrierDrag, 180, steps: 18);
    final barrierTap = await tester.startGesture(
      const Offset(400, 40),
      pointer: 2,
    );
    await barrierTap.up();
    await tester.pump();
    await barrierDrag.cancel();
    await tester.pumpAndSettle();
    expect(find.byType(MeasuredSheet), findsNothing);
    expect(find.byKey(_secondPage), findsOneWidget);
  });
}
