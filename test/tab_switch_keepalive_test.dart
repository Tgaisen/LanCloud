import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/app.dart';

/// 探针页：记录自己何时被创建，并用外层传入的滚动控制器。
class _Probe extends StatefulWidget {
  const _Probe({
    required this.name,
    required this.created,
    required this.controller,
  });

  final String name;
  final List<String> created;
  final ScrollController controller;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.created.add(widget.name);
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: widget.controller,
      itemCount: 60,
      itemBuilder: (context, index) =>
          SizedBox(height: 60, child: Text('${widget.name}-$index')),
    );
  }
}

void main() {
  // 切走的离屏页面不销毁（KeepAlivePage）：回来时元素不重建，
  // 滚动位置、列表入场动画状态都保留。
  testWidgets('切页不销毁离屏页面：离屏页面保留滚动位置与状态', (tester) async {
    final created = <String>[];
    final controllers = [for (var i = 0; i < 3; i++) ScrollController()];
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    final pager = PageController();
    addTearDown(pager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageView(
            controller: pager,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < 3; i++)
                KeepAlivePage(
                  child: _Probe(
                    name: '$i',
                    created: created,
                    controller: controllers[i],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 把第 0 页滚起来
    await tester.drag(find.text('0-1'), const Offset(0, -300));
    await tester.pumpAndSettle();
    final offset = controllers[0].offset;
    expect(offset, greaterThan(0));

    // widget 测试里直接 await animateToPage 会一直等不到帧推进，
    // 先记下 Future，用 pump 推进完之后再收尾。
    Future<void> goTo(int target) async {
      final done = pager.animateToPage(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      await tester.pumpAndSettle();
      await done;
      await tester.pumpAndSettle();
    }

    await goTo(2);
    // 切走再切回：第 0 页的元素不应重建（只创建过一次）
    expect(created.where((name) => name == '0').length, 1);
    await goTo(0);
    expect(created.where((name) => name == '0').length, 1);
    // 滚动位置保留
    expect(controllers[0].offset, offset);
  });
}
