import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('轻提示：盖在最上层显示，约 2 秒后自动消失', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showAppToast(context, '已复制'),
              child: const Text('toast'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('toast'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('已复制'), findsOneWidget);

    // 1.6s 停留 + 180ms 淡出后自己消失
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('已复制'), findsNothing);
  });

  testWidgets('长文本轻提示：左右留边距、最多两行、超出省略', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showAppToast(context, '解析分享失败：很长的错误详情信息' * 20),
              child: const Text('toast'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('toast'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final text = tester.widget<Text>(find.textContaining('解析分享失败'));
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);

    // 气泡左右各留 16dp：宽度不超过屏宽 − 32，也不贴边
    final bubble = tester.getRect(
      find
          .ancestor(
            of: find.textContaining('解析分享失败'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(bubble.width, lessThanOrEqualTo(400 - 32 + 0.5));
    expect(bubble.left, greaterThanOrEqualTo(16 - 0.5));
    expect(bubble.right, lessThanOrEqualTo(400 - 16 + 0.5));
  });
}
