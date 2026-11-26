import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/backup_options_page.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/licenses_page.dart';
import 'package:lancloud/ui/profile_page.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'support/profile_page_test_support.dart';

void main() {
  testWidgets('大屏「我的」：两栏列表-详情，切换类别换详情', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final app = AppEnvironment();
    addTearDown(app.dispose);
    final backupService = NoopBackupService(app);
    await tester.pumpWidget(
      ProfileTestProviders.value(
        value: app,
        backupService: backupService,
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
    final app = AppEnvironment();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      ProfileTestProviders.value(
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
      final app = AppEnvironment();
      addTearDown(app.dispose);
      await tester.pumpWidget(
        ProfileTestProviders.value(
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
    final app = AppEnvironment();
    addTearDown(app.dispose);
    final backupService = NoopBackupService(app);
    await tester.pumpWidget(
      ProfileTestProviders.value(
        value: app,
        backupService: backupService,
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
    final advancedTile = find.widgetWithText(ListTile, '高级覆盖项');
    await tester.ensureVisible(advancedTile);
    await tester.pumpAndSettle();
    await tester.tap(advancedTile);
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
    final app = AppEnvironment();
    app.settingsState.store.hideTopBar = true;
    addTearDown(app.dispose);
    await tester.pumpWidget(
      ProfileTestProviders.value(
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
    expect(app.navigation.topBarHide.value, greaterThan(0));

    // 切换类别：新视图要带着顶栏出现（不再保持收起）
    await tester.tap(find.text('外观与布局'));
    await tester.pumpAndSettle();
    expect(app.navigation.topBarHide.value, 0);
  });

  testWidgets('大屏右窗格：同级切换用 FadeThrough，层级进出用 SharedAxis', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final app = AppEnvironment();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      ProfileTestProviders.value(
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

    // 同级类别切换无方向性，使用 Fade Through。
    await tester.tap(find.text('行为与权限'));
    await tester.pump();
    expect(find.byType(FadeThroughTransition), findsNWidgets(2));
    expect(
      tester
          .widget<PageTransitionSwitcher>(find.byType(PageTransitionSwitcher))
          .reverse,
      isFalse,
    );
    await tester.pumpAndSettle();

    // 类别 → 二级页是前进导航，使用水平 Shared Axis。
    await tester.tap(find.text('传输与连接'));
    await tester.pumpAndSettle();
    final advancedTile = find.widgetWithText(ListTile, '高级覆盖项');
    await tester.ensureVisible(advancedTile);
    await tester.pumpAndSettle();
    await tester.tap(advancedTile);
    await tester.pump();
    final forwardTransition = tester.widget<SharedAxisTransition>(
      find.byType(SharedAxisTransition).first,
    );
    expect(
      forwardTransition.transitionType,
      SharedAxisTransitionType.horizontal,
    );
    expect(
      tester
          .widget<PageTransitionSwitcher>(find.byType(PageTransitionSwitcher))
          .reverse,
      isFalse,
    );
    await tester.pumpAndSettle();

    // 返回上一级是反向 Shared Axis。
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    expect(find.byType(SharedAxisTransition), findsNWidgets(2));
    expect(
      tester
          .widget<PageTransitionSwitcher>(find.byType(PageTransitionSwitcher))
          .reverse,
      isTrue,
    );
    await tester.pumpAndSettle();
  });
}
