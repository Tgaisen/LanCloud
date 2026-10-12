import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/m3e.dart';

void main() {
  Widget host(M3eIconButton button) => MaterialApp(
    home: Scaffold(body: Center(child: button)),
  );

  testWidgets('M3eIconButton：48dp 触控目标 + 40dp 圆形容器 + 点按回调', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        M3eIconButton(
          icon: Icons.more_vert,
          tooltip: '更多操作',
          onPressed: () => taps++,
        ),
      ),
    );

    // Small 尺寸：可见容器 40dp，触控目标 ≥48dp（M3E 无障碍要求）
    expect(tester.getSize(find.byType(M3eIconButton)), const Size(48, 48));
    expect(
      tester.getSize(
        find.descendant(
          of: find.byType(M3eIconButton),
          matching: find.byType(InkResponse),
        ),
      ),
      const Size(40, 40),
    );

    await tester.tap(find.byType(M3eIconButton));
    expect(taps, 1);
    // tooltip 同时充当读屏名称
    expect(find.byTooltip('更多操作'), findsOneWidget);
  });

  testWidgets('M3eIconButton：按下形变到 8dp 圆角，松开恢复正圆', (tester) async {
    await tester.pumpWidget(
      host(
        M3eIconButton(icon: Icons.more_vert, tooltip: '更多操作', onPressed: () {}),
      ),
    );

    double radius() {
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(M3eIconButton),
          matching: find.byType(Material),
        ),
      );
      final shape = material.shape! as RoundedRectangleBorder;
      return shape.borderRadius.resolve(TextDirection.ltr).topLeft.x;
    }

    // 静止 = CornerFull（40 / 2）
    expect(radius(), 20);

    final gesture = await tester.press(find.byType(M3eIconButton));
    // onTapDown 要等手势仲裁的 100ms 截止线，之后再让弹簧跑一会
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 120));
    expect(radius(), lessThan(20));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(radius(), moreOrLessEquals(20, epsilon: 0.5));
  });
}
