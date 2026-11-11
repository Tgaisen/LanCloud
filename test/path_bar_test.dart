import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;

/// 根目录 + [count] 层长名称目录，用来把路径栏撑到需要横向滚动。
List<PathSegment> segments(int count) => [
  const PathSegment(id: '-1', label: '根目录'),
  for (var i = 0; i < count; i++) PathSegment(id: '$i', label: '很长的目录名称$i'),
];

Widget host(
  List<PathSegment> data, {
  ValueChanged<int>? onTap,
  double? leadingPadding,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        height: 48,
        width: 400,
        child: PathBar(
          segments: data,
          onTap: onTap ?? (_) {},
          leadingPadding: leadingPadding,
        ),
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

    // 短路径也要撑满可用宽度，否则横向回弹手势区会随内容提前结束。
    expect(tester.getSize(find.byType(SingleChildScrollView)).width, 400);

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

  testWidgets('路径按钮始终透明，当前项强调整体但不再使用容器色', (tester) async {
    await tester.pumpWidget(host(segments(1)));
    await tester.pumpAndSettle();

    final scheme = Theme.of(tester.element(find.byType(PathBar))).colorScheme;
    final currentText = tester.widget<Text>(find.text('很长的目录名称0'));
    final parentText = tester.widget<Text>(find.text('根目录'));
    expect(currentText.style?.color, scheme.onSurface);
    expect(currentText.style?.fontWeight, FontWeight.w600);
    expect(parentText.style?.color, scheme.onSurfaceVariant);

    for (final label in ['根目录', '很长的目录名称0']) {
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.ancestor(
                of: find.text(label),
                matching: find.byType(PathChip),
              ),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, Colors.transparent);
    }

    final arrow = tester.widget<Icon>(
      find.byIcon(app_icons.Icons.chevron_right),
    );
    expect(arrow.size, 18);
  });

  testWidgets('路径胶囊：40dp 胶囊涟漪区域位于 48dp 触控目标内', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(
      host(segments(1), onTap: taps.add, leadingPadding: 4),
    );
    await tester.pumpAndSettle();

    for (final label in ['根目录', '很长的目录名称0']) {
      final chip = find.ancestor(
        of: find.text(label),
        matching: find.byType(PathChip),
      );
      expect(
        tester.getTopLeft(find.text(label)).dx - tester.getRect(chip).left,
        12,
        reason: '$label 的胶囊内部横向留白保持一致',
      );
    }
    expect(
      tester
          .getRect(
            find.ancestor(
              of: find.text('根目录'),
              matching: find.byType(PathChip),
            ),
          )
          .left,
      4,
      reason: '自定义起始留白只作用于路径栏，不改变第一段胶囊内部样式',
    );

    final chip = find.ancestor(
      of: find.text('很长的目录名称0'),
      matching: find.byType(PathChip),
    );
    expect(tester.getSize(chip).height, 48);
    final visual = find.descendant(of: chip, matching: find.byType(Material));
    expect(tester.getSize(visual).height, 40);
    final text = find.text('很长的目录名称0');
    expect(
      tester.widget<Text>(text).style?.fontSize,
      Theme.of(tester.element(text)).textTheme.titleSmall?.fontSize,
    );
    expect(
      tester.getCenter(text).dy,
      closeTo(tester.getCenter(visual).dy, 0.5),
      reason: '文字在 40dp 胶囊内垂直居中',
    );

    final target = tester.getRect(chip);
    await tester.tapAt(Offset(target.center.dx, target.top + 2));
    expect(taps, [1], reason: '胶囊外侧 4dp 仍属于触控目标');

    await tester.tapAt(target.center);
    expect(taps, [1, 1], reason: '胶囊内一次点击只触发一次');
  });
}
