import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/app_scroll.dart';
import 'package:lancloud/ui/pointer_support.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _pumpScrollView(
  WidgetTester tester,
  ScrollBehavior behavior,
) async {
  await tester.pumpWidget(
    MaterialApp(
      scrollBehavior: behavior,
      home: ListView(children: const [SizedBox(height: 2000)]),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() => PointerSupport.hasMouse.value = false);

  testWidgets('检测到鼠标时由全局滚动行为提供统一滚动条', (tester) async {
    PointerSupport.hasMouse.value = false;
    await _pumpScrollView(tester, const AppScrollBehavior());
    expect(find.byType(Scrollbar), findsNothing);

    PointerSupport.hasMouse.value = true;
    await tester.pump();
    expect(find.byType(Scrollbar), findsOneWidget);
  });

  testWidgets('NoAutoScrollbarBehavior 不追加框架滚动条', (tester) async {
    PointerSupport.hasMouse.value = true;
    await _pumpScrollView(tester, const NoAutoScrollbarBehavior());
    expect(find.byType(Scrollbar), findsNothing);
  });
}
