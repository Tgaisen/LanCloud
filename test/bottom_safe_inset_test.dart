import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/ui/common.dart';
import 'package:provider/provider.dart';

import 'm3e_host.dart';

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
        builder: m3eTestBuilder,
        home: TopBarOverlayScaffold(
          appBar: AppBar(title: const Text('设置')),
          bottomSafeInset: bottomSafeInset,
          slivers: const [SliverToBoxAdapter(child: SizedBox(height: 700))],
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
            builder: m3eTestBuilder,
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
          builder: m3eTestBuilder,
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

  testWidgets('小屏：正文区整体让开左右挖孔，顶栏铺满整屏', (tester) async {
    /// 返回 (正文内容, 顶栏 AppBar, 顶栏搜索按钮) 的矩形
    Future<(Rect, Rect, Rect)> pumpSmallPage({
      double left = 0,
      double right = 0,
    }) async {
      final app = AppController();
      addTearDown(app.dispose);
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding(left: left, right: right);
      tester.view.viewPadding = FakeViewPadding(left: left, right: right);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: app,
          child: MaterialApp(
            builder: m3eTestBuilder,
            home: TopBarOverlayScaffold(
              appBar: AppBar(
                title: const Text('设置'),
                actions: [
                  IconButton(icon: const Icon(Icons.search), onPressed: () {}),
                ],
              ),
              slivers: const [
                SliverToBoxAdapter(
                  child: SizedBox(key: Key('content'), height: 200),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (
        tester.getRect(find.byKey(const Key('content'))),
        tester.getRect(find.byType(AppBar)),
        tester.getRect(find.byIcon(Icons.search)),
      );
    }

    final (plainContent, plainBar, plainSearch) = await pumpSmallPage();
    final (insetContent, insetBar, insetSearch) = await pumpSmallPage(
      left: 30,
      right: 40,
    );
    // 正文区整体让开两侧：左 30、右 40
    expect(insetContent.left - plainContent.left, 30);
    expect(plainContent.right - insetContent.right, 40);
    // 顶栏保持铺满整屏（背景不会被挖孔截断）
    expect(insetBar.width, plainBar.width);
    expect(insetBar.left, plainBar.left);
    // 顶栏里的控件由 AppBar 自己让一次；再让一次右侧就会多缩 40
    expect(plainSearch.right - insetSearch.right, 40);
  });

  testWidgets('小屏通铺弹窗：弹窗窗体整体避开左右挖孔，内容不再缩进', (tester) async {
    final app = AppController();
    addTearDown(app.dispose);
    // 440dp 宽的窗口：弹窗通铺整屏，左右各有挖孔
    tester.view.physicalSize = const Size(440, 600);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(left: 30, right: 40);
    tester.view.viewPadding = const FakeViewPadding(left: 30, right: 40);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          builder: m3eTestBuilder,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showAppSheet<void>(
                    context,
                    child: const SizedBox(
                      height: 48,
                      child: Align(
                        alignment: Alignment.center,
                        child: Text('item'),
                      ),
                    ),
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

    // 弹窗窗体（面板）整体避开左右挖孔，而不是让面板压住挖孔、内容缩进
    final panel = tester.getRect(find.byType(MeasuredSheet));
    expect(panel.left, 30);
    expect(panel.right, 400);
    // 内容在面板里居中：面板若照旧压住挖孔、只让内容单边缩进，这里就会偏
    final title = tester.getRect(find.text('item'));
    expect(title.center.dx, moreOrLessEquals(panel.center.dx, epsilon: 0.5));
  });
}
