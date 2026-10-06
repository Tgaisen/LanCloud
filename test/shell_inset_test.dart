import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';

/// 外壳页面末尾要补的底栏留白 = 底栏总高度（含系统导航栏）。
/// CustomScrollView 不会自动消费 MediaQuery 的 padding，各页都得显式补这一段，
/// 所以这里把四种情形固定成测试，避免以后再各写一套。
void main() {
  double? insetIn(BuildContext context) => shellBottomBarInset(context);

  testWidgets('外壳 + 小屏底栏：留白 = 底栏总高度（含系统导航栏）', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.reset);
    const barHeight = 80.0 + 24.0;
    double? value;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBody: true,
          bottomNavigationBar: const SizedBox(height: barHeight),
          body: Builder(
            builder: (context) {
              value = insetIn(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(value, barHeight);
  });

  testWidgets('外壳 + 悬浮底栏：同样按底栏总高度（108 + 系统导航栏）', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.reset);
    const barHeight = 108.0 + 24.0;
    double? value;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBody: true,
          bottomNavigationBar: const SizedBox(height: barHeight),
          body: Builder(
            builder: (context) {
              value = insetIn(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(value, barHeight);
  });

  testWidgets('大屏（底栏在侧边）：不再补留白', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.reset);
    double? value;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            value = insetIn(context);
            return const Scaffold();
          },
        ),
      ),
    );
    expect(value, 0);
  });

  testWidgets('独立页面（非首个路由）：只补系统导航栏', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.reset);
    double? value;
    final navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );
    navKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => Builder(
          builder: (inner) {
            value = insetIn(inner);
            return const Scaffold();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(value, 24);
  });
}
