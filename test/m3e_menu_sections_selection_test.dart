import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
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

List<SemanticsNode> _semanticsNodes(WidgetTester tester) {
  final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
  final nodes = <SemanticsNode>[];
  void walk(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(owner.rootSemanticsNode!);
  return nodes;
}

SemanticsNode _semanticsNodeForLabel(WidgetTester tester, String label) {
  final matches = [
    for (final node in _semanticsNodes(tester))
      if (node.getSemanticsData().label == label &&
          node.getSemanticsData().hasAction(SemanticsAction.tap))
        node,
  ];
  expect(matches, hasLength(1), reason: '$label 应只有一个可点击语义节点，避免 TalkBack 重复停留');
  return matches.single;
}

SemanticsData _semanticsDataForLabel(WidgetTester tester, String label) {
  return _semanticsNodeForLabel(tester, label).getSemanticsData();
}

void main() {
  testWidgets('宽菜单分组可放下时使用 gap', (tester) async {
    final semantics = tester.ensureSemantics();
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
      tester.getSize(find.byKey(const ValueKey('m3e-menu-group-gap-1'))).height,
      2,
    );
    final scheme = Theme.of(tester.element(find.byType(M3eMenuRow).first))
        .colorScheme;
    final outer = tester.widget<Material>(
      find.byKey(const ValueKey('m3e-menu-card')),
    );
    expect(outer.color, Colors.transparent);
    expect(outer.elevation, 0);
    expect(outer.clipBehavior, Clip.none);
    final shadowClipFinder = find.byKey(const ValueKey('m3e-menu-shadow-clip'));
    expect(shadowClipFinder, findsOneWidget);
    final shadowClip = tester.widget<ClipRect>(shadowClipFinder);
    final shadowClipRect = shadowClip.clipper!.getClip(
      tester.getSize(shadowClipFinder),
    );
    expect(shadowClipRect.left, -16);
    expect(shadowClipRect.top, -16);
    expect(shadowClipRect.right, tester.getSize(shadowClipFinder).width + 16);
    expect(shadowClipRect.bottom, tester.getSize(shadowClipFinder).height + 16);
    expect(
      tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .padding,
      const EdgeInsets.symmetric(horizontal: 4),
    );
    for (var i = 0; i < 2; i++) {
      final group = tester.widget<Material>(
        find.byKey(ValueKey('m3e-menu-group-surface-$i')),
      );
      expect(group.color, scheme.surfaceContainerLow);
      expect(group.elevation, 3);
      expect(group.borderRadius, BorderRadius.circular(16));
      final groupRect = tester.getRect(
        find.byKey(ValueKey('m3e-menu-group-surface-$i')),
      );
      final rowRect = tester.getRect(
        find.descendant(
          of: find.byKey(ValueKey('m3e-menu-group-surface-$i')),
          matching: find.byType(M3eMenuRow),
        ),
      );
      expect(rowRect.top - groupRect.top, closeTo(4, 0.1));
      expect(groupRect.bottom - rowRect.bottom, closeTo(4, 0.1));
      if (i == 0) {
        expect(
          groupRect.top,
          100 + 48 + 4,
          reason: 'gap 菜单第一个分组表面与锚点的距离和无 gap 卡片一致',
        );
      }
    }
    expect(
      find.byKey(const ValueKey('m3e-menu-group-surface-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('m3e-menu-group-surface-1')),
      findsOneWidget,
    );
    final actionSemantics = _semanticsDataForLabel(tester, '选项 A');
    expect(actionSemantics.role, SemanticsRole.menuItem);
    expect(actionSemantics.flagsCollection.isChecked.name, 'none');
    expect(actionSemantics.flagsCollection.isInMutuallyExclusiveGroup, isFalse);
    final menuNodes = [
      for (final node in _semanticsNodes(tester))
        if (node.getSemanticsData().role == SemanticsRole.menu) node,
    ];
    expect(menuNodes, hasLength(1));
    final menuScroll = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byKey(const ValueKey('m3e-menu-card')),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(menuScroll.padding, isNotNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('m3e-menu-card')),
        matching: find.byType(ListView),
      ),
      findsNothing,
      reason: '菜单不能使用 ListView，否则 Android 会附加列表 collection 语义',
    );
    semantics.dispose();
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
    expect(
      find.byKey(const ValueKey('m3e-menu-group-surface-0')),
      findsNothing,
    );
    final outer = tester.widget<Material>(
      find.byKey(const ValueKey('m3e-menu-card')),
    );
    final scheme = Theme.of(tester.element(find.byType(M3eMenuRow).first))
        .colorScheme;
    expect(outer.color, scheme.surfaceContainerLow);
    expect(outer.elevation, 3);
    expect(outer.clipBehavior, Clip.antiAlias);
  });

  testWidgets('宽菜单单选显示选中态并在选择后返回', (tester) async {
    final semantics = tester.ensureSemantics();
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
    final selected = _semanticsDataForLabel(tester, '选项 A');
    final unselected = _semanticsDataForLabel(tester, '选项 B');
    expect(selected.role, SemanticsRole.menuItemRadio);
    expect(unselected.role, SemanticsRole.menuItemRadio);
    expect(selected.flagsCollection.isChecked.name, 'isTrue');
    expect(unselected.flagsCollection.isChecked.name, 'isFalse');
    expect(selected.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    expect(unselected.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    expect(selected.hasAction(SemanticsAction.tap), isTrue);

    final accessibilityEvents = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
          message,
        ) async {
          accessibilityEvents.add(message as Map<dynamic, dynamic>);
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );

    tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
      _semanticsNodeForLabel(tester, '选项 B').id,
      SemanticsAction.tap,
    );
    await tester.pumpAndSettle();
    expect(await result.future, 'b');
    expect(
      accessibilityEvents.any((event) => event['type'] == 'tap'),
      isTrue,
      reason: 'TalkBack 语义点击应发送 TapSemanticEvent，触发 Android 点击音效',
    );
    semantics.dispose();
  });

  testWidgets('宽菜单多选保持打开并即时回调', (tester) async {
    final semantics = tester.ensureSemantics();
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

    final initialA = _semanticsDataForLabel(tester, '选项 A');
    final initialB = _semanticsDataForLabel(tester, '选项 B');
    expect(initialA.role, SemanticsRole.menuItemCheckbox);
    expect(initialB.role, SemanticsRole.menuItemCheckbox);
    expect(initialA.flagsCollection.isChecked.name, 'isTrue');
    expect(initialB.flagsCollection.isChecked.name, 'isFalse');
    expect(initialA.flagsCollection.isInMutuallyExclusiveGroup, isFalse);
    expect(initialB.flagsCollection.isInMutuallyExclusiveGroup, isFalse);

    tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
      _semanticsNodeForLabel(tester, '选项 B').id,
      SemanticsAction.tap,
    );
    await tester.pumpAndSettle();
    expect(changed.last, {'a', 'b'});
    expect(
      _semanticsDataForLabel(tester, '选项 B').flagsCollection.isChecked.name,
      'isTrue',
    );
    expect(find.text('选项 A'), findsOneWidget);
    expect(find.text('选项 B'), findsOneWidget);

    await tester.tap(find.text('选项 A'));
    await tester.pumpAndSettle();
    expect(changed.last, {'b'});
    expect(find.text('选项 A'), findsOneWidget);
    expect(find.text('选项 B'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('宽菜单可混合单选与复选并保持打开', (tester) async {
    final semantics = tester.ensureSemantics();
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

    final initialA = _semanticsDataForLabel(tester, '选项 A');
    final initialAscending = _semanticsDataForLabel(tester, '升序');
    expect(initialA.role, SemanticsRole.menuItemRadio);
    expect(initialAscending.role, SemanticsRole.menuItemCheckbox);
    expect(initialA.flagsCollection.isChecked.name, 'isTrue');
    expect(initialA.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    expect(initialAscending.flagsCollection.isChecked.name, 'isFalse');
    expect(
      initialAscending.flagsCollection.isInMutuallyExclusiveGroup,
      isFalse,
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
    expect(
      _semanticsDataForLabel(tester, '升序').flagsCollection.isChecked.name,
      'isTrue',
    );
    expect(find.text('选项 A'), findsOneWidget);
    expect(find.text('升序'), findsOneWidget);
    semantics.dispose();
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
