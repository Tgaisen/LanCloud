import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/ui/common.dart';
import 'package:provider/provider.dart';

/// 复刻「没有底栏、只有滚动内容」的页面：设置 / 关于 / 备份等都用这个骨架。
Future<void> pumpOverlayPage(
  WidgetTester tester, {
  Size size = const Size(400, 600),
  required double bottomInset,
  bool bottomSafeInset = true,
}) async {
  final app = AppController();
  addTearDown(app.dispose);
  tester.view.physicalSize = size;
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
  testWidgets('小屏无底栏页面：滚动内容末尾按系统导航栏高度留白', (tester) async {
    await pumpOverlayPage(tester, bottomInset: 40);
    final withInset = maxScrollExtent(tester);
    await pumpOverlayPage(tester, bottomInset: 0);
    // 有系统导航栏时滚动范围正好多出 40
    expect(withInset - maxScrollExtent(tester), 40);
  });

  testWidgets('大屏：正文卡片统一让开导航栏，页面内不再重复补', (tester) async {
    await pumpOverlayPage(tester, size: const Size(800, 600), bottomInset: 40);
    final withInset = maxScrollExtent(tester);
    await pumpOverlayPage(tester, size: const Size(800, 600), bottomInset: 0);
    // 只由卡片让出 40，不能再叠一份
    expect(withInset - maxScrollExtent(tester), 40);
  });

  testWidgets('内容自己让开导航栏（SafeArea）时不留白，避免多出滚动范围', (tester) async {
    await pumpOverlayPage(tester, bottomInset: 40, bottomSafeInset: false);
    final withoutTail = maxScrollExtent(tester);
    await pumpOverlayPage(tester, bottomInset: 40);
    expect(maxScrollExtent(tester) - withoutTail, 40);
  });
}
