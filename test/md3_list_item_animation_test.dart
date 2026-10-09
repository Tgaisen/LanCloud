import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';

/// 用一个可切换的状态包住列表项，模拟"外部数据变化"。
Widget hostWith(Widget Function(StateSetter setState) builder) => MaterialApp(
  home: Scaffold(
    body: StatefulBuilder(builder: (context, setState) => builder(setState)),
  ),
);

void main() {
  testWidgets('挂载时淡入：透明度从 0 过渡到 1', (tester) async {
    await tester.pumpWidget(
      hostWith(
        (_) => const Column(
          children: [Md3ListItem(icon: Icons.folder_outlined, title: '条目')],
        ),
      ),
    );

    double opacity() => tester
        .widget<Opacity>(
          find
              .ancestor(of: find.text('条目'), matching: find.byType(Opacity))
              .first,
        )
        .opacity;

    expect(opacity(), lessThan(1));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
  });

  testWidgets('animateIn=false 时不播放出现动画', (tester) async {
    await tester.pumpWidget(
      hostWith(
        (_) => const Column(
          children: [
            Md3ListItem(
              icon: Icons.folder_outlined,
              title: '条目',
              animateIn: false,
            ),
          ],
        ),
      ),
    );

    final opacity = tester
        .widget<Opacity>(
          find
              .ancestor(of: find.text('条目'), matching: find.byType(Opacity))
              .first,
        )
        .opacity;
    expect(opacity, 1);
  });

  testWidgets('removing 时淡出并收起高度，后面的条目补位', (tester) async {
    // 单列（Compact 窗口）才会收起高度
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    var removing = false;
    late StateSetter setHost;
    await tester.pumpWidget(
      hostWith((setState) {
        setHost = setState;
        return Column(
          children: [
            Md3ListItem(
              icon: Icons.folder_outlined,
              title: 'A',
              animateIn: false,
              removing: removing,
            ),
            const Md3ListItem(
              icon: Icons.folder_outlined,
              title: 'B',
              animateIn: false,
            ),
          ],
        );
      }),
    );
    await tester.pumpAndSettle();

    // 记录 B 的初始位置与 A 的初始高度
    final bTopBefore = tester.getTopLeft(find.text('B')).dy;
    final heightBefore = tester.getSize(find.byType(Md3ListItem).first).height;

    // 触发删除动画
    setHost(() => removing = true);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final heightMid = tester.getSize(find.byType(Md3ListItem).first).height;
    expect(heightMid, lessThan(heightBefore));

    await tester.pumpAndSettle();
    final heightAfter = tester.getSize(find.byType(Md3ListItem).first).height;
    expect(heightAfter, lessThan(heightMid));
    // A 收起后 B 会往上补位
    expect(tester.getTopLeft(find.text('B')).dy, lessThan(bTopBefore));
  });

  testWidgets('pulse 递增时高亮闪烁，播完自动消失', (tester) async {
    var pulse = 0;
    late StateSetter setHost;
    await tester.pumpWidget(
      hostWith((setState) {
        setHost = setState;
        return Column(
          children: [
            Md3ListItem(
              icon: Icons.folder_outlined,
              title: '条目',
              animateIn: false,
              pulse: pulse,
            ),
          ],
        );
      }),
    );
    await tester.pumpAndSettle();

    bool hasTint() => tester
        .widgetList<ColoredBox>(
          find.descendant(
            of: find.byType(Md3ListItem),
            matching: find.byType(ColoredBox),
          ),
        )
        .any((box) => box.color.a > 0 && box.color.a < 1);

    expect(hasTint(), isFalse);

    setHost(() => pulse = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(hasTint(), isTrue);

    await tester.pumpAndSettle();
    expect(hasTint(), isFalse);
  });

  testWidgets('多列（宽窗口）删除时不收起高度，只淡出缩小', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 800);
    addTearDown(tester.view.reset);

    var removing = false;
    late StateSetter setHost;
    await tester.pumpWidget(
      hostWith((setState) {
        setHost = setState;
        return Row(
          children: [
            Expanded(
              child: Md3ListItem(
                icon: Icons.folder_outlined,
                title: 'A',
                animateIn: false,
                removing: removing,
              ),
            ),
          ],
        );
      }),
    );
    await tester.pumpAndSettle();
    final heightBefore = tester.getSize(find.byType(Md3ListItem)).height;

    setHost(() => removing = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final opacity = tester
        .widget<Opacity>(
          find
              .ancestor(of: find.text('A'), matching: find.byType(Opacity))
              .first,
        )
        .opacity;
    expect(opacity, lessThan(1));
    // 多列下高度保持不变（收起高度会让同一行的卡片被压扁）
    expect(tester.getSize(find.byType(Md3ListItem)).height, heightBefore);

    await tester.pumpAndSettle();
  });

  testWidgets('数据移除后后面的条目不会反向展开（key 跟随条目）', (tester) async {
    // 单列窗口：删除时会收起高度
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    var items = ['A', 'B', 'C'];
    var removing = <String>{};
    late StateSetter setHost;
    await tester.pumpWidget(
      hostWith((setState) {
        setHost = setState;
        return SegmentedList(
          children: [
            for (final name in items)
              Md3ListItem(
                key: ValueKey(name),
                icon: Icons.folder_outlined,
                title: name,
                removing: removing.contains(name),
              ),
          ],
        );
      }),
    );
    await tester.pumpAndSettle();

    final bTopBefore = tester.getTopLeft(find.text('B')).dy;

    // 开始删除 A：B 跟着收起高度上移
    setHost(() => removing = {'A'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final bTopMid = tester.getTopLeft(find.text('B')).dy;
    expect(bTopMid, lessThan(bTopBefore));

    // 动画播完后真正移除数据（与外部的删除流程一致）
    await tester.pump(const Duration(milliseconds: 120));
    setHost(() {
      items = ['B', 'C'];
      removing = <String>{};
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // 关键：不应出现"再展开"的下移动画
    final bTopAfter = tester.getTopLeft(find.text('B')).dy;
    expect(bTopAfter, lessThanOrEqualTo(bTopMid + 1));
    // 也不应重播出现动画（元素状态跟着 key 走，而不是按下标复用）
    final bOpacity = tester
        .widget<Opacity>(
          find
              .ancestor(of: find.text('B'), matching: find.byType(Opacity))
              .first,
        )
        .opacity;
    expect(bOpacity, 1);

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('B')).dy, bTopAfter);
  });
}
