import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/ui/common.dart';
import 'package:provider/provider.dart';

/// 复刻「没有底栏、只有滚动内容」的页面：设置 / 关于 / 备份等都用这个骨架。
Future<void> pumpOverlayPage(
  WidgetTester tester, {
  required double bottomInset,
  bool bottomSafeInset = true,
}) async {
  final app = AppController();
  addTearDown(app.dispose);
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = FakeViewPadding(bottom: bottomInset);
  tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: app,
      child: MaterialApp(
        home: TopBarOverlayScaffold(
          appBar: AppBar(title: const Text('设置')),
          bottomSafeInset: bottomSafeInset,
          slivers: const [
            SliverToBoxAdapter(child: SizedBox(height: 700)),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double maxScrollExtent(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).last)
    .position
    .maxScrollExtent;

void main() {
  testWidgets('无底栏页面：滚动内容末尾按系统导航栏高度留白', (tester) async {
    await pumpOverlayPage(tester, bottomInset: 40);
    // 视口 600；顶栏占位 kToolbarHeight(56) + 内容 700 + 导航栏留白 40
    expect(maxScrollExtent(tester), 196);
  });

  testWidgets('内容自己让开导航栏（SafeArea）时不留白，避免多出滚动范围', (tester) async {
    await pumpOverlayPage(tester, bottomInset: 40, bottomSafeInset: false);
    expect(maxScrollExtent(tester), 156);
  });
}
