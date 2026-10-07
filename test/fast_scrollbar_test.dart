import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';

Future<ScrollController> pumpBar(
  WidgetTester tester, {
  required int items,
  EdgeInsetsGeometry? padding,
}) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 600);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FastScrollbar(
          controller: controller,
          padding: padding,
          child: ListView.builder(
            controller: controller,
            itemCount: items,
            itemBuilder: (context, index) =>
                SizedBox(height: 60, child: Text('row $index')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

/// 滚动一下让滑块淡入，返回时滑块仍可见（可以抓住拖动）。
Future<void> fadeInThumb(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -120));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
}

void main() {
  testWidgets('滑块不常显；滚动淡入后可以抓住拖拽跳转', (tester) async {
    final controller = await pumpBar(tester, items: 200);

    final bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    // Android 默认不响应拖拽，必须显式打开
    expect(bar.interactive, isTrue);
    expect(bar.controller, same(controller));
    // 不常显：跟原生一样滚动出现、停止后淡出
    expect(bar.thumbVisibility, isNull);

    await fadeInThumb(tester);
    final before = controller.offset;
    expect(before, greaterThan(0));

    // 抓住刚淡入的滑块往下拖：一次跳到列表中部（而不是逐行滚）
    await tester.dragFrom(const Offset(398, 20), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(before + 1000));
  });

  testWidgets('短列表：内容不能滚动时不显示滑块', (tester) async {
    final controller = await pumpBar(tester, items: 3);

    final bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(bar.interactive, isTrue);
    expect(bar.thumbVisibility, isNull);
    expect(controller.offset, 0);
  });

  testWidgets('传入顶栏高度的 padding：轨道与滑块从顶栏下方开始', (tester) async {
    const padding = EdgeInsets.only(top: 80, bottom: 20);
    final controller = await pumpBar(tester, items: 200, padding: padding);

    // 滚动条上下文用的是「顶栏 + 底部占位」的 padding
    final barContext = tester.element(find.byType(Scrollbar));
    expect(MediaQuery.paddingOf(barContext), padding);
    // 内容仍拿原来的 padding，不受影响
    final listContext = tester.element(find.byType(ListView));
    expect(MediaQuery.paddingOf(listContext), EdgeInsets.zero);

    // 从顶栏下方的滑块位置拖动：一次跳到列表中部
    await fadeInThumb(tester);
    await tester.dragFrom(const Offset(398, 96), const Offset(0, 260));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(1000));
  });
}
