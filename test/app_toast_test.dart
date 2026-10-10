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
}
