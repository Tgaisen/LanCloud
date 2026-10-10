import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/m3e.dart';

enum _Action { a, b, c, d, e }

List<M3EIconAction<_Action>> _items({bool thirdChecked = false}) => [
  for (final action in _Action.values)
    M3EIconAction(
      value: action,
      icon: Icons.star_border,
      checkedIcon: Icons.star_outline,
      tooltip: '按钮 ${action.name}',
      checked: action == _Action.c && thirdChecked,
      isToggle: action == _Action.c,
    ),
];

Future<void> _pumpGroup(
  WidgetTester tester, {
  required double width,
  List<M3EIconAction<_Action>>? groupItems,
  ValueChanged<_Action>? onPressed,
  void Function(_Action, bool)? onToggled,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: M3EIconButtonGroup<_Action>(
              items: groupItems ?? _items(),
              onPressed: onPressed,
              onToggled: onToggled,
            ),
          ),
        ),
      ),
    ),
  );
}

List<Rect> _buttonRects(WidgetTester tester) => [
  for (int i = 0; i < find.byType(M3EToggleButton).evaluate().length; i++)
    tester.getRect(find.byType(M3EToggleButton).at(i)),
];

void main() {
  testWidgets('标准图标按钮组：一行等宽、间距 6dp、宽度按可用宽度自适应', (tester) async {
    // 手机竖屏弹窗内容宽（360 - 两侧 24dp）≈ 312dp
    await _pumpGroup(tester, width: 312);

    final rects = _buttonRects(tester);
    expect(rects, hasLength(5));
    // (312 - 4×6) / 5 = 57.6dp，落在 48~80dp 之间
    for (final rect in rects) {
      expect(rect.width, moreOrLessEquals(57.6, epsilon: 0.5));
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.width, lessThanOrEqualTo(80));
    }
    for (int i = 1; i < rects.length; i++) {
      expect(
        rects[i].left - rects[i - 1].right,
        moreOrLessEquals(6, epsilon: 0.5),
      );
    }
    // 一行整体不超出可用宽度（不换行）
    expect(rects.last.right - rects.first.left, lessThanOrEqualTo(312.5));
  });

  testWidgets('宽窗口时单个按钮不超过 80dp 上限', (tester) async {
    await _pumpGroup(tester, width: 600);
    for (final rect in _buttonRects(tester)) {
      expect(rect.width, moreOrLessEquals(80, epsilon: 0.5));
    }
  });

  testWidgets('极窄窗口：收到 48dp 触控下限后交给组横向滚动，仍不换行', (tester) async {
    await _pumpGroup(tester, width: 240);
    final rects = _buttonRects(tester);
    for (final rect in rects) {
      expect(rect.width, moreOrLessEquals(48, epsilon: 0.5));
    }
    // 所有按钮仍在同一行（y 相同）
    expect(rects.map((r) => r.top).toSet(), hasLength(1));
  });

  testWidgets('动作按钮点完不会变成选中态，开关按钮回报新状态', (tester) async {
    final pressed = <_Action>[];
    final toggled = <(_Action, bool)>[];
    await _pumpGroup(
      tester,
      width: 312,
      onPressed: pressed.add,
      onToggled: (action, checked) => toggled.add((action, checked)),
    );

    // 普通动作：点完只回调，不进入选中态
    await tester.tap(find.byTooltip('按钮 a'));
    await tester.pumpAndSettle();
    expect(pressed, [_Action.a]);
    expect(toggled, isEmpty);
    expect(
      tester
          .widgetList<M3EToggleButton>(find.byType(M3EToggleButton))
          .where((b) => b.checked ?? false)
          .length,
      0,
    );

    // 开关按钮：回报切换后的状态
    await tester.tap(find.byTooltip('按钮 c'));
    await tester.pumpAndSettle();
    expect(toggled, [(_Action.c, true)]);
    expect(pressed, [_Action.a]);
  });

  testWidgets('开关按钮的选中态由调用方持有：传 checked 即显示为选中', (tester) async {
    await _pumpGroup(
      tester,
      width: 312,
      groupItems: _items(thirdChecked: true),
    );
    final M3EToggleButton third = tester
        .widgetList<M3EToggleButton>(find.byType(M3EToggleButton))
        .elementAt(2);
    expect(third.checked, isTrue);
  });
}
