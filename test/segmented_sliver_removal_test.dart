import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';

/// 记录每个条目元素被创建过几次（复用元素时不会 +1）。
class Probe extends StatefulWidget {
  const Probe({super.key, required this.id});

  final String id;

  static final Map<String, int> created = <String, int>{};

  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  @override
  void initState() {
    super.initState();
    Probe.created[widget.id] = (Probe.created[widget.id] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 48, child: Text(widget.id));
}

/// 条目当前的不透明度（出现动画进行中会小于 1）。
double itemOpacity(WidgetTester tester, String id) => tester
    .widgetList<Opacity>(
      find.descendant(
        of: find.byKey(ValueKey('item-$id')),
        matching: find.byType(Opacity),
      ),
    )
    .map((o) => o.opacity)
    .reduce((a, b) => a < b ? a : b);

void main() {
  testWidgets('单列：删除多条时幸存条目按 key 复用元素，不重建', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 600); // Compact：单列
    addTearDown(tester.view.reset);
    Probe.created.clear();
    final ids = ValueNotifier<List<String>>(['a', 'b', 'c', 'd', 'e']);
    addTearDown(ids.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              ValueListenableBuilder<List<String>>(
                valueListenable: ids,
                builder: (context, list, _) => SegmentedSliverList(
                  itemCount: list.length,
                  findChildIndexCallback: childIndexLookup(
                    list,
                    (id) => ValueKey('item-$id'),
                  ),
                  itemBuilder: (context, index) => Probe(
                    key: ValueKey('item-${list[index]}'),
                    id: list[index],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(Probe.created, {'a': 1, 'b': 1, 'c': 1, 'd': 1, 'e': 1});

    ids.value = ['a', 'c', 'e']; // 一次删掉 b、d
    await tester.pumpAndSettle();

    // 下标变了的 c、e 复用原元素：创建次数不变
    expect(Probe.created, {'a': 1, 'b': 1, 'c': 1, 'd': 1, 'e': 1});
    expect(find.text('b'), findsNothing);
    expect(find.text('d'), findsNothing);
  });

  testWidgets('多列：删除多条后幸存条目不重播出现动画', (tester) async {
    // 900dp → 多列（行会被整体重建，靠 ListEnterGate 兜底）
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);
    final ids = ValueNotifier<List<String>>(['a', 'b', 'c', 'd', 'e', 'f']);
    addTearDown(ids.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              ValueListenableBuilder<List<String>>(
                valueListenable: ids,
                builder: (context, list, _) => SegmentedSliverList(
                  adaptive: true,
                  itemCount: list.length,
                  itemBuilder: (context, index) => Md3ListItem(
                    key: ValueKey('item-${list[index]}'),
                    index: index,
                    icon: Icons.folder,
                    title: list[index],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(itemOpacity(tester, 'f'), 1.0);

    ids.value = ['a', 'c', 'e']; // 一次删掉 b、d、f
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    // 行被重建，但这一帧是"列表刚删过条目"，新元素直接显示
    expect(itemOpacity(tester, 'e'), 1.0);
    expect(itemOpacity(tester, 'c'), 1.0);
    await tester.pumpAndSettle();
  });
}
