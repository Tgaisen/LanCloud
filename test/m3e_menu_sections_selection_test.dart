import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:material_ui/material_ui.dart';

const List<M3eMenuSection<String>> _sections = [
  M3eMenuSection(
    items: [
      M3eMenuItem(value: 'a', label: '选项 A', icon: Icons.circle_outlined),
    ],
  ),
  M3eMenuSection(
    items: [
      M3eMenuItem(value: 'b', label: '选项 B', icon: Icons.square_outlined),
    ],
  ),
];

const List<M3eMenuSection<String>> _choiceSections = [
  M3eMenuSection(
    items: [
      M3eMenuItem(
        value: 'a',
        label: '选项 A',
        icon: Icons.circle_outlined,
        selectionRole: M3eMenuSelectionRole.radio,
      ),
      M3eMenuItem(
        value: 'b',
        label: '选项 B',
        icon: Icons.square_outlined,
        selectionRole: M3eMenuSelectionRole.radio,
      ),
    ],
  ),
  M3eMenuSection(
    items: [
      M3eMenuItem(
        value: 'ascending',
        label: '升序',
        icon: Icons.arrow_upward,
        selectionRole: M3eMenuSelectionRole.checkbox,
      ),
    ],
  ),
];

Future<void> _pumpTrigger(
  WidgetTester tester, {
  required Size size,
  required Future<void> Function(BuildContext context) open,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (BuildContext context) => ElevatedButton(
              onPressed: () => unawaited(open(context)),
              child: const Text('打开菜单'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开菜单'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('宽菜单分组可放下时使用 gap', (tester) async {
    await _pumpTrigger(
      tester,
      size: const Size(800, 800),
      open: (BuildContext context) async {
        await showM3eMenu<String>(
          context: context,
          anchor: const Rect.fromLTWH(300, 100, 48, 48),
          sections: _sections,
        );
      },
    );

    expect(find.byKey(const ValueKey('m3e-menu-group-gap-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('m3e-menu-divider-1')), findsNothing);
    expect(
      find.byKey(const ValueKey('m3e-menu-group-surface-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('m3e-menu-group-surface-1')),
      findsOneWidget,
    );
  });

  testWidgets('宽菜单需要滚动时改用 divider 分组', (tester) async {
    await _pumpTrigger(
      tester,
      size: const Size(800, 600),
      open: (BuildContext context) async {
        await showM3eMenu<String>(
          context: context,
          anchor: const Rect.fromLTWH(300, 100, 48, 48),
          sections: [
            M3eMenuSection(
              items: [
                for (var i = 0; i < 5; i++)
                  M3eMenuItem(
                    value: 'a$i',
                    label: '选项 A$i',
                    icon: Icons.circle_outlined,
                  ),
              ],
            ),
            M3eMenuSection(
              items: [
                for (var i = 0; i < 5; i++)
                  M3eMenuItem(
                    value: 'b$i',
                    label: '选项 B$i',
                    icon: Icons.square_outlined,
                  ),
              ],
            ),
          ],
        );
      },
    );

    expect(find.byKey(const ValueKey('m3e-menu-divider-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('m3e-menu-group-gap-1')), findsNothing);
  });

  testWidgets('宽菜单单选显示选中态并在选择后返回', (tester) async {
    final result = Completer<String?>();
    await _pumpTrigger(
      tester,
      size: const Size(800, 800),
      open: (BuildContext context) async {
        final selected = await showM3eSingleSelectMenu<String>(
          context: context,
          anchor: const Rect.fromLTWH(300, 100, 48, 48),
          sections: _sections,
          selected: 'a',
        );
        result.complete(selected);
      },
    );

    final rows = tester
        .widgetList<M3eMenuRow>(find.byType(M3eMenuRow))
        .toList();
    expect(rows.firstWhere((row) => row.label == '选项 A').selected, isTrue);
    expect(rows.firstWhere((row) => row.label == '选项 B').selected, isFalse);
    expect(
      find.byKey(const ValueKey('m3e-menu-selected-check-选项 A')),
      findsOneWidget,
    );

    await tester.tap(find.text('选项 B'));
    await tester.pumpAndSettle();
    expect(await result.future, 'b');
  });

  testWidgets('宽菜单多选保持打开并即时回调', (tester) async {
    final changed = <Set<String>>[];
    await _pumpTrigger(
      tester,
      size: const Size(800, 800),
      open: (BuildContext context) async {
        await showM3eMultiSelectMenu<String>(
          context: context,
          anchor: const Rect.fromLTWH(300, 100, 48, 48),
          sections: _sections,
          selected: const {'a'},
          onChanged: changed.add,
        );
      },
    );

    await tester.tap(find.text('选项 B'));
    await tester.pumpAndSettle();
    expect(changed.last, {'a', 'b'});
    expect(find.text('选项 A'), findsOneWidget);
    expect(find.text('选项 B'), findsOneWidget);

    await tester.tap(find.text('选项 A'));
    await tester.pumpAndSettle();
    expect(changed.last, {'b'});
    expect(find.text('选项 A'), findsOneWidget);
    expect(find.text('选项 B'), findsOneWidget);
  });

  testWidgets('宽菜单可混合单选与复选并保持打开', (tester) async {
    final changed = <M3eMenuChoice<String>>[];
    await _pumpTrigger(
      tester,
      size: const Size(800, 800),
      open: (BuildContext context) async {
        await showM3eChoiceMenu<String>(
          context: context,
          anchor: const Rect.fromLTWH(300, 100, 48, 48),
          sections: _choiceSections,
          radioValue: 'a',
          onChanged: changed.add,
        );
      },
    );

    await tester.tap(find.text('选项 B'));
    await tester.pumpAndSettle();
    expect(changed.last.radioValue, 'b');
    expect(changed.last.checkedValues, isEmpty);
    final rows = tester
        .widgetList<M3eMenuRow>(find.byType(M3eMenuRow))
        .toList();
    expect(rows.firstWhere((row) => row.label == '选项 A').selected, isFalse);
    expect(rows.firstWhere((row) => row.label == '选项 B').selected, isTrue);

    await tester.tap(find.text('升序'));
    await tester.pumpAndSettle();
    expect(changed.last.radioValue, 'b');
    expect(changed.last.checkedValues, {'ascending'});
    expect(
      find.byKey(const ValueKey('m3e-menu-selected-check-升序')),
      findsOneWidget,
    );
    expect(find.text('选项 A'), findsOneWidget);
    expect(find.text('升序'), findsOneWidget);
  });

  testWidgets('Compact 单选使用多个列表组和 radio', (tester) async {
    final result = Completer<String?>();
    await _pumpTrigger(
      tester,
      size: const Size(411, 800),
      open: (BuildContext context) async {
        final selected = await showAdaptiveM3eSingleSelectMenu<String>(
          context: context,
          anchor: const Rect.fromLTWH(300, 100, 48, 48),
          sections: _sections,
          selected: 'a',
        );
        result.complete(selected);
      },
    );

    expect(find.byType(SheetListGroup), findsNWidgets(2));
    expect(find.byType(Radio<bool>), findsNWidgets(2));
    await tester.tap(find.text('选项 B'));
    await tester.pumpAndSettle();
    expect(await result.future, 'b');
  });

  testWidgets('Compact 多选使用多个列表组和 checkbox，并保持打开', (tester) async {
    final changed = <Set<String>>[];
    await _pumpTrigger(
      tester,
      size: const Size(411, 800),
      open: (BuildContext context) async {
        await showAdaptiveM3eMultiSelectMenu<String>(
          context: context,
          anchor: const Rect.fromLTWH(300, 100, 48, 48),
          sections: _sections,
          selected: const {'a'},
          onChanged: changed.add,
        );
      },
    );

    expect(find.byType(SheetListGroup), findsNWidgets(2));
    expect(find.byType(Checkbox), findsNWidgets(2));
    await tester.tap(find.text('选项 B'));
    await tester.pumpAndSettle();
    expect(changed.last, {'a', 'b'});
    expect(find.text('选项 A'), findsOneWidget);
    expect(find.text('选项 B'), findsOneWidget);
  });

  testWidgets('Compact 混合选择按项显示 radio 与 checkbox', (tester) async {
    final changed = <M3eMenuChoice<String>>[];
    await _pumpTrigger(
      tester,
      size: const Size(411, 800),
      open: (BuildContext context) async {
        await showAdaptiveM3eChoiceMenu<String>(
          context: context,
          anchor: const Rect.fromLTWH(300, 100, 48, 48),
          sections: _choiceSections,
          radioValue: 'a',
          onChanged: changed.add,
        );
      },
    );

    expect(find.byType(Radio<bool>), findsNWidgets(2));
    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.text('升序'));
    await tester.pumpAndSettle();
    expect(changed.last.checkedValues, {'ascending'});
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    final tiles = tester
        .widgetList<M3ePickTile>(find.byType(M3ePickTile))
        .toList();
    expect(tiles.firstWhere((tile) => tile.label == '选项 A').selected, isTrue);
    expect(tiles.firstWhere((tile) => tile.label == '选项 B').selected, isFalse);
    expect(find.text('升序'), findsOneWidget);
  });
}
