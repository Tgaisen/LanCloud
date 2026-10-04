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

  testWidgets('大屏卡片内的 AppBar 不会再让一次系统 inset', (tester) async {
    /// 返回 AppBar 右侧搜索按钮右边缘的 x（大屏下页面被套进 MD3E 卡片）
    Future<double> searchRight(double rightInset) async {
      final app = AppController();
      addTearDown(app.dispose);
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding(right: rightInset);
      tester.view.viewPadding = FakeViewPadding(right: rightInset);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: app,
          child: MaterialApp(
            home: Md3ePageFrame(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('设置'),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () {},
                    ),
                  ],
                ),
                body: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getRect(find.byIcon(Icons.search)).right;
    }

    final without = await searchRight(0);
    final with40 = await searchRight(40);
    // 卡片让出 40；AppBar 若再让一次就会少 80，这里必须只差 40
    expect(without - with40, 40);
  });

  testWidgets('弹窗被 640dp 上限居中时，内容不再按挖孔 / 导航栏缩进', (tester) async {
    final app = AppController();
    addTearDown(app.dispose);
    // 900dp 宽的窗口：弹窗按 MD3 上限 640dp 居中，离两侧系统栏很远
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(left: 40, right: 40);
    tester.view.viewPadding = const FakeViewPadding(left: 40, right: 40);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showAppSheet<void>(
                    context,
                    child: const ListTile(title: Text('item')),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 弹窗按 MD3 上限 640dp 居中：两侧各留 (900-640)/2 = 130dp，
    // 再加上 ListTile 自身的 16dp；若内容又按 40dp 挖孔让位会变成 ~186
    final title = tester.getRect(find.text('item'));
    expect(title.left, inInclusiveRange(130, 160));
  });
}
