import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:material_ui/material_ui.dart';

/// 在 411dp 宽的屏幕中间打开一个菜单（锚点是一颗 48dp 的 ⋯ 按钮）。
Future<void> openMenu(
  WidgetTester tester,
  List<M3eMenuItem<String>> items,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(411, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: Builder(
              builder: (BuildContext buttonContext) => IconButton(
                tooltip: 'more',
                icon: const Icon(Icons.more_vert),
                onPressed: () => showM3eMenu<String>(
                  context: context,
                  anchor: m3eMenuAnchorOf(buttonContext)!,
                  items: items,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(IconButton));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('菜单宽度按内容算：短文案不再固定撑到锚点宽度 + 176', (tester) async {
    await openMenu(tester, const [
      M3eMenuItem(value: 'open', label: 'Open', icon: Icons.open_in_new),
    ]);

    final width = tester.getSize(find.byType(ListView)).width;
    // M3：112dp 下限；不再跟着 48dp 锚点变成 224dp 的固定宽度
    expect(width, greaterThanOrEqualTo(112));
    expect(width, lessThan(224));
    // 短文案完整显示，不截断
    final paragraph = tester.renderObject<RenderParagraph>(find.text('Open'));
    expect(paragraph.didExceedMaxLines, isFalse);
  });

  testWidgets('长文案：菜单加宽到 280dp 上限，行内省略号截断、不再溢出卡片', (tester) async {
    await openMenu(tester, const [
      M3eMenuItem(value: 'open', label: 'Open', icon: Icons.open_in_new),
      M3eMenuItem(
        value: 'remove',
        label: 'Remove from quick access',
        icon: Icons.push_pin_outlined,
      ),
      M3eMenuItem(value: 'top', label: 'Move to top', icon: Icons.arrow_upward),
    ]);

    // 内容比 280dp 还宽：宽度顶到上限，文案由省略号截断（测试字体下 24 字符
    // 宽 338dp，必然超过 280−内边距后的可用宽度）
    final width = tester.getSize(find.byType(ListView)).width;
    expect(width, 280);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Remove from quick access'),
    );
    expect(paragraph.didExceedMaxLines, isTrue);
    // 菜单整体仍在屏幕内（左右各留 12dp）
    final left = tester.getTopLeft(find.byType(ListView)).dx;
    expect(left, greaterThanOrEqualTo(12));
    expect(left + width, lessThanOrEqualTo(411 - 12));
  });
}
