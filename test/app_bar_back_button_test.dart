import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/common.dart';

void main() {
  testWidgets('返回按钮的图标位置与普通 IconButton 完全一致', (tester) async {
    Future<Rect> iconRect(Widget? leading) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(leading: leading, title: const Text('t')),
            body: const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getRect(find.byIcon(app_icons.Icons.arrow_back));
    }

    final plain = await iconRect(
      Builder(
        builder: (context) => IconButton(
          onPressed: () {},
          icon: const Icon(app_icons.Icons.arrow_back),
        ),
      ),
    );
    final tonal = await iconRect(const AppBarBackButton());
    expect(tonal, plain);
  });

  testWidgets('按钮表面（含波纹）仍是 40dp 圆形底色，且不贴屏幕左边', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            leading: const AppBarBackButton(),
            title: const Text('t'),
            actions: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
            ],
          ),
          body: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 返回按钮自身的 Material（波纹所在的那层表面）
    final surface = tester.getRect(
      find
          .descendant(
            of: find.byType(AppBarBackButton),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(surface.size, const Size(40, 40), reason: '表面应保持 40dp');
    expect(surface.left, greaterThan(0), reason: '不能贴着屏幕左边');
    // 图标位置不变：表面中心 = 图标中心
    final icon = tester.getRect(find.byIcon(app_icons.Icons.arrow_back));
    expect(surface.center.dx, icon.center.dx);

    final scheme =
        Theme.of(tester.element(find.byType(AppBarBackButton))).colorScheme;
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(AppBarBackButton),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      material.color,
      scheme.secondaryContainer,
    );
  });

  testWidgets('返回按钮点击后返回', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(leading: const AppBarBackButton()),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppBarBackButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
}
