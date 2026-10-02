import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/ui/app_scroll.dart';
import 'package:lancloud/ui/common.dart';

void main() {
  testWidgets('滚动驱动的收起进度立即生效', (tester) async {
    final app = AppController();
    app.setBarsHideFromScroll(0.4);
    expect(app.barsHide.value, 0.4);
    // 越界输入会被夹紧
    app.setBarsHideFromScroll(2);
    expect(app.barsHide.value, 1);
    app.dispose();
  });

  testWidgets('程序化显示/隐藏是平滑过渡而不是瞬间跳变', (tester) async {
    final app = AppController();
    app.setBarsHideFromScroll(1);
    app.animateBarsHide(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final mid = app.barsHide.value;
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(app.barsHide.value, 0);
    app.dispose();
  });

  testWidgets('滚动输入会打断程序化动画', (tester) async {
    final app = AppController();
    app.setBarsHideFromScroll(1);
    app.animateBarsHide(0);
    await tester.pump();
    app.setBarsHideFromScroll(0.7);
    await tester.pump(const Duration(milliseconds: 300));
    expect(app.barsHide.value, 0.7);
    app.dispose();
  });

  testWidgets('全局滚动行为使用网盘页同款 BouncingScrollPhysics', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    final physics = const AppScrollBehavior().getScrollPhysics(context);
    expect(physics, isA<BouncingScrollPhysics>());
    expect(physics.parent, isA<AlwaysScrollableScrollPhysics>());
  });

  testWidgets('空状态提示淡入显示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyHint(icon: Icons.folder_open, text: '这个文件夹是空的'),
        ),
      ),
    );
    final fade = tester.widget<Opacity>(
      find
          .descendant(
            of: find.byType(EmptyHint),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(fade.opacity, 0);
    await tester.pump(const Duration(milliseconds: 400));
    final done = tester.widget<Opacity>(
      find
          .descendant(
            of: find.byType(EmptyHint),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(done.opacity, 1);
  });
}
