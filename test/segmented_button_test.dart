import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';

Set<String> lastSelection = <String>{};

Widget host({Set<String> selected = const {'b'}}) => MaterialApp(
  home: Scaffold(
    body: ConnectedSegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'a',
          icon: Icon(Icons.grid_view),
          label: Text('A'),
        ),
        ButtonSegment(
          value: 'b',
          icon: Icon(Icons.view_list),
          label: Text('B'),
        ),
        ButtonSegment(value: 'c', icon: Icon(Icons.sort), label: Text('C')),
      ],
      selected: selected,
      onSelectionChanged: (values) => lastSelection = values,
    ),
  ),
);

BorderRadius radiusOf(WidgetTester tester, int index) {
  final containers = tester
      .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
      .toList();
  final decoration = containers[index].decoration! as BoxDecoration;
  return decoration.borderRadius! as BorderRadius;
}

Color? colorOf(WidgetTester tester, int index) {
  final containers = tester
      .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
      .toList();
  return (containers[index].decoration! as BoxDecoration).color;
}

void main() {
  testWidgets('连接式按钮组：外侧 16dp、相邻处 4dp、空白间隔，不显示对勾', (tester) async {
    lastSelection = <String>{};
    await tester.pumpWidget(host());
    final scheme = Theme.of(
      tester.element(find.byType(ConnectedSegmentedButton<String>)),
    ).colorScheme;

    expect(
      radiusOf(tester, 0),
      const BorderRadius.only(
        topLeft: Radius.circular(16),
        bottomLeft: Radius.circular(16),
        topRight: Radius.circular(4),
        bottomRight: Radius.circular(4),
      ),
    );
    expect(radiusOf(tester, 1), BorderRadius.circular(4));
    expect(
      radiusOf(tester, 2),
      const BorderRadius.only(
        topLeft: Radius.circular(4),
        bottomLeft: Radius.circular(4),
        topRight: Radius.circular(16),
        bottomRight: Radius.circular(16),
      ),
    );

    // 选中项用主题色强调，未选中透明
    expect(colorOf(tester, 1), scheme.secondaryContainer);
    expect(colorOf(tester, 0), Colors.transparent);

    // 保留各自图标，不替换成对勾
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.byIcon(Icons.grid_view), findsOneWidget);
    expect(find.byIcon(Icons.view_list), findsOneWidget);

    // 条目之间是空白间隔
    final gaps = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((s) => s.width == 2)
        .length;
    expect(gaps, 2);
  });

  testWidgets('点击切换选中项（单选）', (tester) async {
    lastSelection = <String>{};
    await tester.pumpWidget(host());
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(lastSelection, {'a'});
  });

  testWidgets('按下时做 shape morphing，相邻角同步收圆', (tester) async {
    lastSelection = <String>{};
    await tester.pumpWidget(host());
    final gesture = await tester.startGesture(tester.getCenter(find.text('B')));
    await tester.pumpAndSettle();

    expect(radiusOf(tester, 1), BorderRadius.circular(28));
    // 左右相邻：左邻的右侧角、右邻的左侧角收圆
    expect(radiusOf(tester, 0).topRight, const Radius.circular(16));
    expect(radiusOf(tester, 0).bottomRight, const Radius.circular(16));
    expect(radiusOf(tester, 2).topLeft, const Radius.circular(16));
    expect(radiusOf(tester, 2).bottomLeft, const Radius.circular(16));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(radiusOf(tester, 1), BorderRadius.circular(4));
  });
}
