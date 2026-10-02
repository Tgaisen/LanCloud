import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';

Widget host() => MaterialApp(
  home: Scaffold(
    body: SegmentedList(
      children: const [
        ListTile(title: Text('A')),
        ListTile(title: Text('B')),
        ListTile(title: Text('C')),
      ],
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

void main() {
  testWidgets('连接式列表：外侧 16dp、相邻处 4dp、用空白间隔', (tester) async {
    await tester.pumpWidget(host());

    expect(
      radiusOf(tester, 0),
      const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
        bottomLeft: Radius.circular(4),
        bottomRight: Radius.circular(4),
      ),
    );
    expect(radiusOf(tester, 1), BorderRadius.circular(4));
    expect(
      radiusOf(tester, 2),
      const BorderRadius.only(
        topLeft: Radius.circular(4),
        topRight: Radius.circular(4),
        bottomLeft: Radius.circular(16),
        bottomRight: Radius.circular(16),
      ),
    );

    // 条目之间是空白间隔，没有分割线
    expect(find.byType(Divider), findsNothing);
    expect(find.byType(SizedBox), findsNWidgets(2));
  });

  testWidgets('按下条目做 shape morphing，相邻条目相邻角同步收圆', (tester) async {
    await tester.pumpWidget(host());

    final gesture = await tester.startGesture(tester.getCenter(find.text('B')));
    await tester.pumpAndSettle();

    // 按下项整体放大
    expect(radiusOf(tester, 1), BorderRadius.circular(28));
    // 上下相邻条目的相邻角收圆到外侧圆角
    expect(radiusOf(tester, 0).bottomLeft, const Radius.circular(16));
    expect(radiusOf(tester, 0).bottomRight, const Radius.circular(16));
    expect(radiusOf(tester, 2).topLeft, const Radius.circular(16));
    expect(radiusOf(tester, 2).topRight, const Radius.circular(16));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(radiusOf(tester, 1), BorderRadius.circular(4));
    expect(radiusOf(tester, 0).bottomLeft, const Radius.circular(4));
  });
}
