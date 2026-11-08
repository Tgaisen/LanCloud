import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:material_ui/material_ui.dart';

Future<Future<String?> Function()> _pumpMenu(
  WidgetTester tester, {
  required Size size,
  Offset? pointerPosition,
  Listenable? closeOn,
  bool Function()? closeWhen,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  late Future<String?> opened;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (BuildContext context) => IconButton(
              tooltip: 'more',
              icon: const Icon(Icons.more_vert),
              onPressed: () {
                opened = showAdaptiveM3eMenu<String>(
                  context: context,
                  anchor: const Rect.fromLTWH(300, 100, 48, 48),
                  pointerPosition: pointerPosition,
                  closeOn: closeOn,
                  closeWhen: closeWhen,
                  items: const [
                    M3eMenuItem(
                      value: 'open',
                      label: '打开',
                      icon: Icons.open_in_new,
                    ),
                    M3eMenuItem(
                      value: 'disabled',
                      label: '不可用操作',
                      icon: Icons.block,
                      enabled: false,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(IconButton));
  await tester.pumpAndSettle();
  return () => opened;
}

void main() {
  testWidgets('Compact 移动端使用列表组底部面板并返回类型化结果', (tester) async {
    final opened = await _pumpMenu(tester, size: const Size(411, 800));

    expect(
      find.byKey(const ValueKey('adaptive-m3e-menu-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('m3e-menu-card')), findsNothing);

    final disabled = tester.widget<ListTile>(
      find.ancestor(of: find.text('不可用操作'), matching: find.byType(ListTile)),
    );
    expect(disabled.enabled, isFalse);
    expect(disabled.onTap, isNull);

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(await opened(), 'open');
  });

  testWidgets('Medium 宽度继续使用原锚定菜单', (tester) async {
    await _pumpMenu(tester, size: const Size(800, 800));

    expect(find.byKey(const ValueKey('m3e-menu-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('adaptive-m3e-menu-sheet')), findsNothing);
  });

  testWidgets('Compact Windows 和鼠标上下文菜单保持原菜单', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await _pumpMenu(tester, size: const Size(411, 800));
    expect(find.byKey(const ValueKey('m3e-menu-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('adaptive-m3e-menu-sheet')), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    debugDefaultTargetPlatformOverride = null;
    await _pumpMenu(
      tester,
      size: const Size(411, 800),
      pointerPosition: const Offset(180, 160),
    );
    expect(find.byKey(const ValueKey('m3e-menu-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('adaptive-m3e-menu-sheet')), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Compact 底部面板沿用 closeOn 自动收起', (tester) async {
    final state = ChangeNotifier();
    addTearDown(state.dispose);
    bool shouldClose = false;
    final opened = await _pumpMenu(
      tester,
      size: const Size(411, 800),
      closeOn: state,
      closeWhen: () => shouldClose,
    );

    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('adaptive-m3e-menu-sheet')),
      findsOneWidget,
    );

    shouldClose = true;
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('adaptive-m3e-menu-sheet')), findsNothing);
    expect(await opened(), isNull);
  });
}
