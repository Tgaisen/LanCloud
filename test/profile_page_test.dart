import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/update/release_info.dart';
import 'package:lancloud/core/update/update_service.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/backup_options_page.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/licenses_page.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'update_test_scope_test.dart';

class _TestProviders extends StatelessWidget {
  const _TestProviders.value({
    required this.value,
    required this.child,
    this.container,
  });

  final AppController value;
  final Widget child;
  final ProviderContainer? container;

  @override
  Widget build(BuildContext context) {
    final updateContainer = container;
    if (updateContainer != null) {
      return updateTestTree(
        app: value,
        container: updateContainer,
        child: child,
      );
    }
    return appTestTree(app: value, child: child);
  }
}

void main() {
  testWidgets('「我的」视图：显示账号、网页版、设置与关于', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      _TestProviders.value(
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
    expect(find.text('切换'), findsOneWidget);
    expect(find.text('显示 Cookie'), findsNothing);
    // 单栏态三组也都有分组小标题（账号 / 设置 / 应用）
    expect(find.text('账号'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
    expect(find.text('网页版'), findsOneWidget);
    expect(find.text('回收站'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('更新'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.byIcon(app_icons.Icons.swap_vertical_circle), findsOneWidget);
    expect(find.byIcon(app_icons.Icons.view_cozy), findsOneWidget);
    expect(find.byIcon(app_icons.Icons.text_snippet), findsOneWidget);
    expect(find.byIcon(app_icons.Icons.cloud_done), findsOneWidget);
    final accountHeader = find.descendant(
      of: find.widgetWithText(M3eSectionHeader, '账号'),
      matching: find.text('账号'),
    );
    final accountTile = find
        .descendant(
          of: find.byType(SegmentedList).first,
          matching: find.byType(ListTile),
        )
        .first;
    expect(tester.getTopLeft(accountHeader).dx, 20);
    expect(
      tester.getTopLeft(accountHeader).dx,
      closeTo(tester.getTopLeft(accountTile).dx, 0.01),
    );
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
        _TestProviders.value(
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
      _TestProviders.value(
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

  /// 起一个「两栏「我的」页」的测试环境。
  Future<void> pumpTwoPane(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final app = AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      _TestProviders.value(
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
  }

  /// 右窗格内容的焦点落点（FocusNode 的 debugLabel）。
  String? focusedPaneLabel() => FocusManager.instance.primaryFocus?.debugLabel;

  /// 顶栏标题的语义：右窗格换内容时标题跟着换，标题本身是 live region，
  /// 念不念、怎么念交给 TalkBack 自己（不自己发 announcement、不加自造文案）。
  SemanticsData paneTitleSemantics(WidgetTester tester, String title) => tester
      .getSemantics(
        find.descendant(of: find.byType(AppBar), matching: find.text(title)),
      )
      .getSemanticsData();

  testWidgets('两栏无障碍：切类别后焦点进右窗格，顶栏标题是 liveRegion', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTwoPane(tester);

    // 初始：右窗格是账号管理，顶栏标题是 live region
    expect(paneTitleSemantics(tester, '账号管理').label, '账号管理');
    expect(
      paneTitleSemantics(tester, '账号管理').flagsCollection.isLiveRegion,
      isTrue,
    );

    await tester.tap(find.text('传输与连接'));
    await tester.pumpAndSettle();

    expect(focusedPaneLabel(), 'profile-detail-pane');
    // 类别切换后标题换成类别名（与单栏态 push 出来的类别页标题一致）
    expect(paneTitleSemantics(tester, '传输与连接').label, '传输与连接');
    expect(
      paneTitleSemantics(tester, '传输与连接').flagsCollection.isLiveRegion,
      isTrue,
    );
    // 语义句柄要在测试体内销毁：框架在 tearDown 之前就会校验
    semantics.dispose();
  });

  testWidgets('两栏无障碍：进二级页 / 返回后焦点进右窗格，标题 liveRegion 跟随', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTwoPane(tester);

    await tester.tap(find.text('传输与连接'));
    await tester.pumpAndSettle();

    // 进二级页：焦点回右窗格（新内容），标题换成二级页名
    await tester.tap(find.widgetWithText(ListTile, '高级覆盖项'));
    await tester.pumpAndSettle();
    expect(focusedPaneLabel(), 'profile-detail-pane');
    expect(paneTitleSemantics(tester, '高级覆盖项').label, '高级覆盖项');

    // 返回：回到类别层，同样把焦点带回右窗格，标题换回类别名
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(focusedPaneLabel(), 'profile-detail-pane');
    expect(paneTitleSemantics(tester, '传输与连接').label, '传输与连接');
    semantics.dispose();
  });

  testWidgets('两栏无障碍：左窗格 ↑ / ↓ 在条目之间移动焦点', (tester) async {
    await pumpTwoPane(tester);

    // Tab 落到左窗格第一条
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final first = FocusManager.instance.primaryFocus;
    expect(first, isNotNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNot(same(first)));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(first));
  });

  testWidgets('两栏无障碍：Esc 与返回等价（关二级页、退出搜索）', (tester) async {
    await pumpTwoPane(tester);

    await tester.tap(find.text('传输与连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '高级覆盖项'));
    await tester.pumpAndSettle();
    Finder appBarTitle(String text) =>
        find.descendant(of: find.byType(AppBar), matching: find.text(text));
    expect(appBarTitle('高级覆盖项'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(appBarTitle('传输与连接'), findsOneWidget);
    expect(find.text('网络请求间隔'), findsOneWidget);

    // 再按一次：搜索态下 Esc 退出搜索（这里先进入搜索）
    await tester.tap(find.byTooltip('搜索设置项'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('大屏「我的」：两栏列表-详情，切换类别换详情', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final app = AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      _TestProviders.value(
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

    // 左窗格：账号 / 设置 5 大类 / 关于；默认选中账号，右窗格是账号面板
    // 三个分组都有小标题（账号 / 设置 / 应用），账号条目改名「账号管理」
    expect(find.text('账号'), findsOneWidget);
    // 「账号管理」既是左窗格条目，也是右窗格顶栏标题
    expect(find.text('账号管理'), findsNWidgets(2));
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('外观与布局'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
    expect(find.text('切换'), findsOneWidget);
    expect(find.text('网页版'), findsOneWidget);
    // 顶栏标题跟随右窗格；账号 / 关于没有搜索入口，设置类别才有
    Finder appBarTitle(String text) =>
        find.descendant(of: find.byType(AppBar), matching: find.text(text));
    expect(appBarTitle('账号管理'), findsOneWidget);
    expect(find.byTooltip('搜索设置项'), findsNothing);

    // 左右窗格之间没有额外间距：两张窗格（各自的滚动视图）直接相接，
    // 左窗格条目自带的 16dp 内边距就是全部（不再是 16 + 16 的双重边距）；
    // 顶栏只盖右窗格，起点与左窗格右缘一致（宽度按最长条目实测）。
    final panes = find.byType(CustomScrollView);
    expect(panes, findsNWidgets(2));
    final paneRight = tester.getRect(panes.at(0)).right;
    expect(tester.getRect(panes.at(1)).left, moreOrLessEquals(paneRight));
    expect(tester.getTopLeft(find.byType(TopBarOverlay)).dx, paneRight);
    // 左窗格（导航区）通到窗口底边，不再跟着右卡片让开底部那 8dp；
    // 右卡片照旧留 8dp
    final screenBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getRect(panes.at(0)).bottom, screenBottom);
    expect(tester.getRect(panes.at(1)).bottom, screenBottom - 8);

    // 选中「传输与连接」：右窗格换成该类别的设置页
    await tester.tap(find.text('传输与连接'));
    await tester.pumpAndSettle();
    expect(find.text('下载目录'), findsOneWidget);
    expect(find.text('切换'), findsNothing);
    // 两栏标题用类别名（与单栏态 push 出来的类别页一致）
    expect(appBarTitle('传输与连接'), findsOneWidget);
    expect(find.byTooltip('搜索设置项'), findsOneWidget);

    // 选中「关于」：右窗格换成关于内容
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    expect(find.text('开源许可'), findsOneWidget);
    expect(find.text('下载目录'), findsNothing);
    expect(appBarTitle('关于'), findsOneWidget);
    expect(find.byTooltip('搜索设置项'), findsNothing);

    // 选中「更新」：右窗格换成更新页内容（更新在「关于」前面，同一分组）
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(find.text('更新通道'), findsOneWidget);
    expect(find.text('开源许可'), findsNothing);
    expect(appBarTitle('更新'), findsOneWidget);
  });

  testWidgets('默认窗口尺寸下左窗格可滚动：最后一条「关于」能滚到可见', (tester) async {
    // Windows 默认窗口 856×620 逻辑像素 → 客户区约 841.6×582.4dp，
    // 外壳底部再让开 8dp，左窗格可视高度约 574dp。
    // 「应用」分组加了「更新」后整列超过这个高度：接受滚动（不压缩窗口与
    // 间距），保证最后一条能整条滚进视口即可。
    tester.view.physicalSize = const Size(841, 574);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final app = AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      _TestProviders.value(
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

    // 左窗格（两张窗格里的第一个滚动视图）现在有滚动余量；
    // 滚到底后最后一条「关于」整条落在视口里
    final paneScroll = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(CustomScrollView).first,
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(paneScroll.maxScrollExtent, greaterThan(0));
    paneScroll.jumpTo(paneScroll.maxScrollExtent);
    await tester.pumpAndSettle();
    final aboutRect = tester.getRect(find.text('关于'));
    expect(aboutRect.top, greaterThanOrEqualTo(0));
    expect(aboutRect.bottom, lessThanOrEqualTo(574));
  });

  testWidgets('大屏「我的」：左窗格宽度按最长条目自适应（中文比英文窄）', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<double> paneWidth(Locale locale) async {
      final app = AppController();
      addTearDown(app.dispose);
      await tester.pumpWidget(
        _TestProviders.value(
          value: app,
          child: MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
            home: const ProfilePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 左窗格的滚动视图从 0 开始，右缘就是窗格宽度
      return tester.getRect(find.byType(CustomScrollView).first).right;
    }

    final zh = await paneWidth(const Locale('zh'));
    final en = await paneWidth(const Locale('en'));

    // 中文最长条目只有 5 个字：窗格明显窄于原来写死的 280dp
    expect(zh, lessThan(280));
    // 英文条目更长：窗格更宽，但仍受上限约束
    expect(en, greaterThan(zh));
    expect(en, lessThanOrEqualTo(320));
  });

  testWidgets('大屏二级设置页：高级覆盖项 / 备份与恢复进右窗格，可返回', (tester) async {
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(<String>[
        'profile_pane_package',
      ], 'Profile pane license');
    });
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final app = AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      _TestProviders.value(
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

    Finder appBarTitle(String text) =>
        find.descendant(of: find.byType(AppBar), matching: find.text(text));
    double listLeftInset(Finder tile) {
      final pane = tester.getRect(find.byType(CustomScrollView).last);
      return tester.getRect(tile).left - pane.left;
    }

    double listTopInset(Finder tile) {
      final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
      return tester.getRect(tile).top - appBarBottom;
    }

    final accountTile = find.widgetWithText(ListTile, '未登录');
    expect(listLeftInset(accountTile), 20);
    expect(listTopInset(accountTile), 20);

    // 传输与连接 → 高级覆盖项：在右窗格内打开（左窗格还在 == 不是整页 push）
    await tester.tap(find.text('传输与连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '高级覆盖项'));
    await tester.pumpAndSettle();
    expect(appBarTitle('高级覆盖项'), findsOneWidget);
    expect(find.text('正常情况下不宜更改这些选项，否则可能导致相关功能故障'), findsOneWidget);
    expect(find.text('网盘接口域名'), findsOneWidget);
    expect(find.text('外观与布局'), findsOneWidget);

    // 返回：回到类别层
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(appBarTitle('传输与连接'), findsOneWidget);
    expect(find.text('网络请求间隔'), findsOneWidget);
    expect(find.text('正常情况下不宜更改这些选项，否则可能导致相关功能故障'), findsNothing);

    // 隐私与数据 → 备份与恢复：同样进右窗格
    await tester.tap(find.text('隐私与数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '备份与恢复'));
    await tester.pumpAndSettle();
    expect(appBarTitle('备份与恢复'), findsOneWidget);
    expect(find.text('本地备份'), findsOneWidget);
    expect(find.text('外观与布局'), findsOneWidget);

    // 从备份与恢复继续进入“备份选项”：仍在右窗格，顶栏和确认动作归外层。
    await tester.tap(find.widgetWithText(ListTile, '备份选项'));
    await tester.pumpAndSettle();
    expect(appBarTitle('备份选项'), findsOneWidget);
    expect(find.byType(BackupOptionsPage), findsOneWidget);
    final optionsRect = tester.getRect(find.byType(BackupOptionsPage));
    final paneRect = tester.getRect(find.byType(CustomScrollView).last);
    expect(optionsRect.left, closeTo(paneRect.left + 16, 0.01));
    expect(optionsRect.right, closeTo(paneRect.right - 16, 0.01));
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
          .onPressed,
      isNull,
    );
    expect(find.text('外观与布局'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(BackupOptionsPage),
        matching: find.text('设置项'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(appBarTitle('备份与恢复'), findsOneWidget);

    // 本地立即备份的选项页使用“备份”标题，也回到同一右窗格。
    await tester.tap(find.widgetWithText(ListTile, '立即备份'));
    await tester.pumpAndSettle();
    expect(appBarTitle('备份'), findsOneWidget);
    expect(find.byType(BackupOptionsPage), findsOneWidget);
    expect(find.text('外观与布局'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(appBarTitle('备份与恢复'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(appBarTitle('隐私与数据'), findsOneWidget);
    expect(find.text('本地备份'), findsNothing);

    // 关于 → 开源许可：同样进右窗格
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '开源许可'));
    await tester.pumpAndSettle();
    expect(appBarTitle('开源许可'), findsOneWidget);
    expect(find.text('外观与布局'), findsOneWidget);

    final packageTile = find
        .descendant(
          of: find.byType(LicensesContent),
          matching: find.byType(ListTile),
        )
        .first;
    final packageName =
        (tester.widget<ListTile>(packageTile).title! as Text).data!;
    final packageLeft = tester.getRect(packageTile).left;
    final packageTop = tester.getRect(packageTile).top;
    expect(listLeftInset(packageTile), 20);
    expect(listTopInset(packageTile), 20);
    await tester.tap(packageTile);
    await tester.pumpAndSettle();
    expect(appBarTitle(packageName), findsOneWidget);
    expect(find.byType(LicenseDetailContent), findsOneWidget);
    expect(find.text('外观与布局'), findsOneWidget);
    final detailCard = find.byKey(const ValueKey('license-detail-card-0'));
    expect(tester.getTopLeft(detailCard).dx, closeTo(packageLeft, 0.01));
    expect(tester.getTopLeft(detailCard).dy, closeTo(packageTop, 0.01));

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(appBarTitle('开源许可'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(appBarTitle('关于'), findsOneWidget);
  });

  testWidgets('切换窗格内容时把收起的顶栏调出来', (tester) async {
    tester.view.physicalSize = const Size(1200, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final app = AppController()..settings.hideTopBar = true;
    addTearDown(app.dispose);
    await tester.pumpWidget(
      _TestProviders.value(
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

    await tester.tap(find.text('传输与连接'));
    await tester.pumpAndSettle();

    // 上滑把顶栏收起
    await tester.drag(find.text('下载目录'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(app.topBarHide.value, greaterThan(0));

    // 切换类别：新视图要带着顶栏出现（不再保持收起）
    await tester.tap(find.text('外观与布局'));
    await tester.pumpAndSettle();
    expect(app.topBarHide.value, 0);
  });

  testWidgets('大屏右窗格切换动画：前进从右滑入、后退从左滑入', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final app = AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      _TestProviders.value(
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

    /// 某个文案当前所在窗格的滑动位移（相对窗格宽度的比例）。
    double slideDxOf(String text) => tester
        .widget<SlideTransition>(
          find
              .ancestor(
                of: find.text(text),
                matching: find.byType(SlideTransition),
              )
              .first,
        )
        .position
        .value
        .dx;

    // 前进：账号 → 行为与权限（列表往下选），新内容从右侧滑入、
    // 旧内容向左滑出
    await tester.tap(find.text('行为与权限'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(slideDxOf('行为'), greaterThan(0)); // 新内容：从右滑入
    expect(slideDxOf('切换'), lessThan(0)); // 旧内容：向左滑出
    await tester.pumpAndSettle();

    // 后退：行为与权限 → 外观与布局（列表往上选），新内容从左侧滑入
    await tester.tap(find.text('外观与布局'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(slideDxOf('外观'), lessThan(0));
    await tester.pumpAndSettle();
  });

  testWidgets('「我的」账号卡片：普通用户不显示等级卡片，会员等级显示', (tester) async {
    Widget tree(AppController app) =>
        _TestProviders.value(
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
    // 头像首字母是装饰：读屏跳过它（账号信息由标题 / 副标题播报）
    expect(
      find.ancestor(
        of: find.byType(CircleAvatar),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
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
      _TestProviders.value(
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
    await tester.tap(find.text('切换'));
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
      _TestProviders.value(
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
    await tester.tap(find.text('切换'));
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
    await tester.tap(find.text('切换'));
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

  testWidgets('「更新」条目：检测到新版本时显示「检测到更新」副标题（单栏 / 两栏）', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final app = AppController();
    addTearDown(app.dispose);
    await app.settings.load();
    final container = createUpdateContainer(
      settings: app.settings,
      fetch: () async => [
        ReleaseInfo(
          tag: 'v99.0.0',
          version: '99.0.0',
          body: '',
          htmlUrl: '',
          prerelease: false,
          draft: false,
          publishedAt: null,
          assets: const [],
        ),
      ],
    );
    addTearDown(container.dispose);
    final updates = container.read(updateServiceProvider.notifier);
    await updates.initialize();
    await updates.check();
    expect(updates.status, UpdateStatus.available);

    Future<void> pumpProfile() async {
      await tester.pumpWidget(
        _TestProviders.value(
          value: app,
          container: container,
          child: MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: const ProfilePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // 单栏：ListTile 副标题
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpProfile();
    expect(find.text('检测到更新'), findsOneWidget);

    // 两栏：左窗格条目副标题
    tester.view.physicalSize = const Size(1200, 800);
    await pumpProfile();
    expect(find.text('检测到更新'), findsOneWidget);
  });
}
