import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';
import 'package:material_ui/material_ui.dart';

/// 模拟按下鼠标的某个键（默认左键 / 侧键「后退」）。
Future<void> mouseClick(
  WidgetTester tester,
  Offset at, {
  int buttons = kPrimaryButton,
}) async {
  final gesture = await tester.startGesture(
    at,
    kind: PointerDeviceKind.mouse,
    buttons: buttons,
  );
  await gesture.up();
}

Future<GlobalKey<NavigatorState>> pumpTwoPages(WidgetTester tester) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) => MouseBackButtonListener(
        onBack: () => navigatorKey.currentState?.maybePop(),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('第二页')),
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
  expect(find.text('第二页'), findsOneWidget);
  return navigatorKey;
}

void main() {
  testWidgets('鼠标侧键「后退」等价系统返回键：弹出当前页面', (tester) async {
    await pumpTwoPages(tester);
    await mouseClick(
      tester,
      tester.getCenter(find.text('第二页')),
      buttons: kBackMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('第二页'), findsNothing);
    expect(find.text('打开'), findsOneWidget);
  });

  testWidgets('普通左键点击不会触发返回', (tester) async {
    await pumpTwoPages(tester);
    await mouseClick(tester, tester.getCenter(find.text('第二页')));
    await tester.pumpAndSettle();

    expect(find.text('第二页'), findsOneWidget);
  });
}
