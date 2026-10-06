import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/profile_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('「我的」视图：显示账号、网页版、设置与关于', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('管理'), findsOneWidget);
    expect(find.text('显示 Cookie'), findsNothing);
    expect(find.text('网页版'), findsOneWidget);
    expect(find.text('回收站'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    app.dispose();
  });

  testWidgets('「我的」末尾留白：不再自己叠加固定 96（由 shellBottomBarInset 统一补）', (
    tester,
  ) async {
    Future<int> tailSpacerCount({required bool floating}) async {
      final app = AppController()..settings.floatingNavBar = floating;
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: app,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: const ProfilePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final count = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((box) => box.height == 96)
          .length;
      app.dispose();
      return count;
    }

    // 两种底栏样式都不该再自己塞一段 96：底栏让位统一由
    // shellBottomBarInset（= 外壳 extendBody 补进来的 padding.bottom）承担
    expect(await tailSpacerCount(floating: true), 0);
    expect(await tailSpacerCount(floating: false), 0);
  });

  testWidgets('「我的」切到别的标签页再切回来，滚动位置保留', (tester) async {
    final app = AppController();
    addTearDown(app.dispose);
    // 视口做小一点，让「我的」内容可滚动
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final pager = PageController(initialPage: 2);
    addTearDown(pager.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: PageView(
              controller: pager,
              children: const [
                Center(child: Text('home')),
                Center(child: Text('drive')),
                ProfilePage(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    ScrollPosition pageScroll() => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(ProfilePage),
            matching: find.byType(Scrollable),
          ),
        )
        .position;

    expect(pageScroll().maxScrollExtent, greaterThan(0));
    pageScroll().jumpTo(pageScroll().maxScrollExtent);
    await tester.pumpAndSettle();
    final offset = pageScroll().pixels;
    expect(offset, greaterThan(0));

    // 切到最左边再切回来（相隔两页，PageView 不会保活相邻页之外的状态）
    pager.jumpToPage(0);
    await tester.pumpAndSettle();
    pager.jumpToPage(2);
    await tester.pumpAndSettle();
    expect(pageScroll().pixels, offset);
  });
}
