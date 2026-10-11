import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:material_ui/material_ui.dart';

/// 系统返回键与 MD3E 弹出菜单的优先级：
///
/// 外壳（app.dart）用 `PopScope(canPop: false)` 接管返回键（例如在网盘标签页
/// 按返回切回首页）。菜单是独立路由，返回键应当先收菜单、不穿透到外壳——
/// 这里复刻这套组合守住它。
void main() {
  testWidgets('外壳 PopScope 下：返回键先收菜单，不穿透到外壳', (tester) async {
    var shellHandledBack = false;
    bool? shellDidPop;
    await tester.pumpWidget(
      MaterialApp(
        home: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            shellHandledBack = true;
            shellDidPop = didPop;
          },
          child: Scaffold(
            body: Center(
              child: Builder(
                builder: (buttonContext) => ElevatedButton(
                  onPressed: () => showM3eMenu<String>(
                    context: buttonContext,
                    anchor: m3eMenuAnchorOf(buttonContext)!,
                    alignEnd: true,
                    items: const [
                      M3eMenuItem(value: 'a', label: '甲', icon: Icons.add),
                    ],
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('甲'), findsOneWidget, reason: '菜单应该已展开');

    await tester.binding.handlePopRoute();
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.text('甲'), findsNothing, reason: '返回键应先收起菜单');
    expect(shellHandledBack, isFalse, reason: '这次返回不该穿透到外壳');

    // 菜单收起后，返回键照旧交给外壳处理（没被这次修复影响）
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(shellHandledBack, isTrue);
    expect(shellDidPop, isFalse, reason: '外壳应当自己拦下这次返回');
  });
}
