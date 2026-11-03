import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _pumpPointerMenu(
  WidgetTester tester,
  Offset pointerPosition,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(411, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Builder(
            builder: (BuildContext buttonContext) => TextButton(
              onPressed: () => showM3eMenu<String>(
                context: buttonContext,
                anchor: m3eMenuAnchorOf(buttonContext)!,
                pointerPosition: pointerPosition,
                items: const [
                  M3eMenuItem(
                    value: 'open',
                    label: 'Open',
                    icon: Icons.open_in_new,
                  ),
                ],
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pump();
}

void main() {
  testWidgets('鼠标右键：菜单从全局坐标展开，并使用 M3E popup 弹簧', (tester) async {
    await _pumpPointerMenu(tester, const Offset(180, 160));

    final transformFinder = find.byKey(
      const ValueKey('m3e-menu-popup-surface'),
    );
    final animationTransform = tester.widget<Transform>(transformFinder);
    expect(animationTransform.transform.entry(0, 0), closeTo(0.8, 0.001));

    await tester.pump(const Duration(milliseconds: 150));
    final overshootTransform = tester.widget<Transform>(transformFinder);
    expect(
      overshootTransform.transform.entry(0, 0),
      greaterThan(1),
      reason: '空间弹簧应在展开过程中产生 M3E 风格的轻微 overshoot',
    );

    await tester.pumpAndSettle();
    final card = tester.getRect(find.byKey(const ValueKey('m3e-menu-card')));
    expect(card.top, closeTo(160, 0.1));
    expect(card.left, closeTo(180, 0.1));
    expect(
      tester.widget<Transform>(transformFinder).transform.entry(0, 0),
      closeTo(1, 0.001),
    );
  });

  testWidgets('鼠标靠近右边缘：菜单翻到鼠标左侧且右缘贴住坐标', (tester) async {
    await _pumpPointerMenu(tester, const Offset(390, 160));
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byKey(const ValueKey('m3e-menu-card')));
    expect(card.top, closeTo(160, 0.1));
    expect(card.right, closeTo(390, 0.1));
    expect(card.left, greaterThanOrEqualTo(12));
  });
}
