import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/profile_page.dart';
import 'package:provider/provider.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  testWidgets('「我的」视图：显示账号、网页版、设置与关于', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
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
            localizationsDelegates: appLocalizationsDelegates,
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
          localizationsDelegates: appLocalizationsDelegates,
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

  testWidgets('「我的」账号卡片：普通用户不显示等级卡片，会员等级显示', (tester) async {
    Widget tree(AppController app) =>
        ChangeNotifierProvider<AppController>.value(
          value: app,
          child: MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: const ProfilePage(),
          ),
        );

    final app = AppController();
    addTearDown(app.dispose);
    app.accounts.accounts.add(
      Account(uid: '556911', cookie: 'c', nickname: '土豆'),
    );
    app.accounts.activeUid = '556911';
    await tester.pumpWidget(tree(app));
    await tester.pumpAndSettle();

    expect(find.text('土豆'), findsOneWidget);
    // 等级还没取到（按普通用户「普」处理）：不显示卡片
    expect(find.text('普'), findsNothing);

    // 截取到会员等级后显示小卡片
    app.accounts.byUid('556911')!.level = '白';
    app.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('白'), findsOneWidget);

    // 调成普通用户「普」：卡片隐藏
    app.accounts.byUid('556911')!.level = '普';
    app.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('普'), findsNothing);
  });

  testWidgets('管理账号弹窗：两个列表组，容器色比弹窗底高一档、窗体边距 16dp', (tester) async {
    final app = AppController();
    addTearDown(app.dispose);
    app.accounts.accounts.add(
      Account(uid: '556911', cookie: 'c', nickname: '土豆'),
    );
    app.accounts.activeUid = '556911';
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();

    // 弹窗里：账号组 + 退出登录组，共 2 组
    final lists = tester
        .widgetList<SegmentedList>(
          find.descendant(
            of: find.byType(M3EBottomSheet),
            matching: find.byType(SegmentedList),
          ),
        )
        .toList();
    expect(lists, hasLength(2));
    final scheme = Theme.of(tester.element(find.byType(ProfilePage)))
        .colorScheme;
    for (final list in lists) {
      // 比弹窗底（surfaceContainerLow）高一档容器色
      expect(list.color, scheme.surfaceContainer);
    }
    // 组 1 是普通组外边距；组 2 是弹窗内容的最后一块：底边与左右同值（16dp）
    expect(lists[0].margin, const EdgeInsets.fromLTRB(16, 4, 16, 4));
    expect(lists[1].margin, SheetListGroup.endMargin);
    // 退出登录单独一组（第二组只有它一项）
    expect(
      find.descendant(
        of: find.byType(M3EBottomSheet),
        matching: find.text('退出登录'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('移除账号弹窗：列表组复选行「清除使用数据」，勾选后确认即移除账号', (tester) async {
    // 移除账号会写安全存储：测试里换成内存实现
    FlutterSecureStorage.setMockInitialValues({});
    final app = AppController();
    addTearDown(app.dispose);
    app.accounts.accounts.add(
      Account(uid: '556911', cookie: 'c', nickname: '土豆'),
    );
    app.accounts.activeUid = '556911';
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    // 确认弹窗：消息 + 「清除使用数据」复选行（列表组样式）
    expect(find.text('移除账号'), findsOneWidget);
    expect(find.text('清除使用数据'), findsOneWidget);
    expect(find.text('清除此账号相关数据，如快速访问、最近使用'), findsOneWidget);
    Checkbox checkbox() => tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox().value, isFalse);

    // 点行勾选（默认没勾：移除账号不动使用数据）
    await tester.tap(find.text('清除使用数据'));
    await tester.pumpAndSettle();
    expect(checkbox().value, isTrue);

    // 取消：账号还在
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(app.accounts.accounts, hasLength(1));

    // 重新打开并确认移除：账号从本机删掉
    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除使用数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    expect(app.accounts.accounts, isEmpty);
    expect(app.accounts.activeUid, isNull);
  });
}
