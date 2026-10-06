import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';

/// 根目录 + [count] 层长名称目录，用来把路径栏撑到需要横向滚动。
List<PathSegment> segments(int count) => [
  const PathSegment(id: '-1', label: '根目录'),
  for (var i = 0; i < count; i++) PathSegment(id: '$i', label: '很长的目录名称$i'),
];

Widget host(List<PathSegment> data) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        height: 46,
        width: 400,
        child: PathBar(segments: data, onTap: (_) {}),
      ),
    ),
  ),
);

void main() {
  testWidgets('进入新路径后自动滚到末尾，当前卡片完整可见', (tester) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(segments(1)));
    await tester.pumpAndSettle();

    // 一路进到第 4 层：内容早已超出 400 宽
    await tester.pumpWidget(host(segments(4)));
    await tester.pumpAndSettle();

    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.pixels, scroll.position.maxScrollExtent);
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    // 最后一个卡片完整落在视口内（不再被截断）
    final chip = tester.getRect(find.text('很长的目录名称3'));
    expect(chip.right, lessThanOrEqualTo(400));
  });

  testWidgets('进入新路径：新卡片有横向展开 + 淡入动画', (tester) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(segments(1)));
    await tester.pumpAndSettle();

    await tester.pumpWidget(host(segments(2)));
    await tester.pump(const Duration(milliseconds: 60));
    final during = tester.getSize(find.byType(SizeTransition).last).width;
    await tester.pumpAndSettle();
    final settled = tester.getSize(find.byType(SizeTransition).last).width;

    expect(during, lessThan(settled));
  });

  testWidgets('返回上级：旧卡片淡出后移出列表', (tester) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(segments(3)));
    await tester.pumpAndSettle();
    expect(find.text('很长的目录名称2'), findsOneWidget);

    await tester.pumpWidget(host(segments(1)));
    await tester.pump(const Duration(milliseconds: 60));
    // 动画期间仍在树上（正在收缩淡出）
    expect(find.text('很长的目录名称2'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('很长的目录名称2'), findsNothing);
    expect(find.text('很长的目录名称1'), findsNothing);
  });
}
