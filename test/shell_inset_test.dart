import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/app.dart';
import 'package:lancloud/core/account_state.dart';
import 'package:lancloud/core/account_session.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/app_runtime_state.dart';
import 'package:lancloud/core/cache_page_settings_state.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/data/app_db_provider.dart';
import 'package:lancloud/core/data/settings_store_provider.dart';
import 'package:lancloud/core/drive_state.dart';
import 'package:lancloud/core/language_clipboard_settings_state.dart';
import 'package:lancloud/core/list_home_settings_state.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/favorites_page.dart';
import 'package:lancloud/ui/profile_page.dart';
import 'package:lancloud/ui/scroll_tint.dart';
import 'package:lancloud/ui/transfers_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'transfer_dependencies_test.dart'
    show buildTransferManagerForEnvironment;

Widget _rootShellHost(
  AppEnvironment environment,
  TransferManager transfers,
) => ProviderScope(
  overrides: [
    settingsStoreProvider.overrideWithValue(environment.settingsState.store),
    accountStateProvider.overrideWithValue(environment.accountState),
    accountSessionProvider.overrideWithValue(environment.accountSession),
    appDbProvider.overrideWithValue(environment.db),
    driveStateProvider.overrideWithValue(environment.drive),
    appRuntimeStateProvider.overrideWithValue(environment.runtimeState),
    cachePageSettingsStateProvider.overrideWithValue(
      environment.cachePageSettings,
    ),
    languageClipboardSettingsStateProvider.overrideWithValue(
      environment.languageClipboardSettings,
    ),
    lanzouClientRegistryProvider.overrideWithValue(environment.clientRegistry),
    listHomeSettingsStateProvider.overrideWithValue(
      environment.listHomeSettings,
    ),
    transferManagerProvider.overrideWithValue(transfers),
    navigationAppearanceSettingsStateProvider.overrideWithValue(
      environment.navigationAppearanceSettings,
    ),
    navigationStateProvider.overrideWithValue(environment.navigation),
  ],
  child: MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: const RootShell(),
  ),
);

Widget _favoritesHost(AppEnvironment environment, TransferManager transfers) =>
    ProviderScope(
      overrides: [
        accountStateProvider.overrideWithValue(environment.accountState),
        lanzouClientRegistryProvider.overrideWithValue(
          environment.clientRegistry,
        ),
        appDbProvider.overrideWithValue(environment.db),
        driveStateProvider.overrideWithValue(environment.drive),
        navigationAppearanceSettingsStateProvider.overrideWithValue(
          environment.navigationAppearanceSettings,
        ),
        navigationStateProvider.overrideWithValue(environment.navigation),
        transferManagerProvider.overrideWithValue(transfers),
      ],
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const ScrollTint(child: FavoritesPage(tabIndex: 3)),
      ),
    );

/// 外壳页面末尾要补的底栏留白 = 底栏总高度（含系统导航栏）。
/// CustomScrollView 不会自动消费 MediaQuery 的 padding，各页都得显式补这一段，
/// 所以这里把四种情形固定成测试，避免以后再各写一套。
void main() {
  double? insetIn(BuildContext context) => shellBottomBarInset(context);

  double? cardGapIn(BuildContext context) => shellBodyCardGap(context);

  testWidgets('正文卡片底部留白：根壳 + 大屏 8dp（别的组合为 0）', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    double? value;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              value = cardGapIn(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(value, 8);
  });

  testWidgets('正文卡片底部留白：小屏为 0（让位由底栏负责）', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    double? value;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              value = cardGapIn(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(value, 0);
  });

  testWidgets('正文卡片底部留白：push 出来的独立页面为 0（外面已套卡片）', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    double? value;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: Builder(
                        builder: (context) {
                          value = cardGapIn(context);
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(value, 0);
  });

  testWidgets('大屏外壳：一般页面让开卡片底部 8dp，「我的」页左窗格通到窗口底边', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    environment.runtimeState.ready.value = true;
    environment.accountState.store.accounts.add(
      Account(uid: '556911', cookie: 'c', nickname: '土豆'),
    );
    environment.accountState.store.activeUid = '556911';
    final transfers = buildTransferManagerForEnvironment(environment);
    addTearDown(transfers.dispose);
    await tester.pumpWidget(_rootShellHost(environment, transfers));
    await tester.pumpAndSettle();

    expect(find.byIcon(app_icons.Icons.browse_outlined), findsWidgets);

    // 首页（外壳里的页面）：正文让开卡片底部的 8dp
    final homeScroll = find.byType(CustomScrollView).first;
    expect(tester.getRect(homeScroll).bottom, 792);

    // 切到「我的」：左窗格（导航区）通到窗口底边，右卡片仍留 8dp
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    final panes = find.descendant(
      of: find.byType(ProfilePage),
      matching: find.byType(CustomScrollView),
    );
    expect(panes, findsNWidgets(2));
    expect(tester.getRect(panes.at(0)).bottom, 800);
    expect(tester.getRect(panes.at(1)).bottom, 792);
  });

  testWidgets('外壳任务角标随运行中任务数更新', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    environment.runtimeState.ready.value = true;
    environment.accountState.store.accounts.add(
      Account(uid: '556911', cookie: 'c', nickname: '土豆'),
    );
    environment.accountState.store.activeUid = '556911';
    final transfers = buildTransferManagerForEnvironment(environment);
    addTearDown(transfers.dispose);
    transfers.tasks.add(
      TransferTask(
        id: 't1',
        kind: TransferKind.upload,
        name: 'a.zip',
        accountUid: '556911',
      )..status = TransferStatus.running,
    );

    await tester.pumpWidget(_rootShellHost(environment, transfers));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('1')),
      findsOneWidget,
    );

    transfers.cancel('t1');
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('1')),
      findsNothing,
    );
  });

  testWidgets('跨越宽窄布局阈值时，标签页、滚动与多选状态保持', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    environment.runtimeState.ready.value = true;
    environment.settingsState.store.navShowTransfers = true;
    environment.settingsState.store.navShowFavorites = true;
    environment.accountState.store.accounts.add(
      Account(uid: '556911', cookie: 'c', nickname: '土豆'),
    );
    environment.accountState.store.activeUid = '556911';
    final transfers = buildTransferManagerForEnvironment(environment);
    addTearDown(transfers.dispose);

    await tester.pumpWidget(_rootShellHost(environment, transfers));
    await tester.pumpAndSettle();
    transfers.tasks.addAll([
      for (var i = 0; i < 20; i++)
        TransferTask(
          id: 't$i',
          kind: TransferKind.download,
          name: 'file-$i.zip',
          accountUid: '556911',
        )..status = TransferStatus.done,
    ]);
    await tester.pump();
    await tester.tap(find.text('传输').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('多选'));
    await tester.pumpAndSettle();

    final shellBeforeResize = tester.state(find.byType(RootShell));
    final pagerBeforeResize = tester.state(find.byType(PageView));
    final stateBeforeResize = tester.state(find.byType(TransfersPage));
    final scheme = Theme.of(tester.element(find.byType(TransfersPage)))
        .colorScheme;
    Color selectionColor() => tester
        .widget<Material>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('transfers-selection-appbar')),
                matching: find.byType(Material),
              )
              .first,
        )
        .color!;
    double selectionOpacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byKey(const ValueKey('transfers-selection-appbar')),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;
    expect(selectionOpacity(), 1);
    expect(selectionColor(), scheme.surface);

    final transferList = find.descendant(
      of: find.byType(TransfersPage),
      matching: find.byType(CustomScrollView),
    );
    await tester.drag(transferList, const Offset(0, -240));
    await tester.pumpAndSettle();
    final scrollOffset = tester
        .state<ScrollableState>(
          find.descendant(of: transferList, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    expect(scrollOffset, greaterThan(0));
    expect(selectionColor(), scheme.surfaceContainer);

    tester.view.physicalSize = const Size(900, 800);
    await tester.pumpAndSettle();

    expect(tester.state(find.byType(RootShell)), same(shellBeforeResize));
    expect(tester.state(find.byType(PageView)), same(pagerBeforeResize));
    expect(
      tester.state(find.byType(TransfersPage)),
      same(stateBeforeResize),
      reason: '宽窄布局切换只应重排外壳，不应重建标签页',
    );
    expect(selectionOpacity(), 1);
    expect(selectionColor(), scheme.surfaceContainer);
    expect(find.text('下载').hitTestable(), findsOneWidget);

    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TransfersPage)), same(stateBeforeResize));
    expect(selectionOpacity(), 1);
    expect(selectionColor(), scheme.surfaceContainer);
    // 宽布局列数更多，可用滚动范围可能变短，位置会被合法地夹到新上限；
    // 关键是仍离开顶部且页面 State 没有重建。
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(
              of: transferList,
              matching: find.byType(Scrollable),
            ),
          )
          .position
          .pixels,
      greaterThan(0),
    );
  });

  testWidgets('收藏页跨越宽窄布局保留搜索，多选顶栏随滚动变色', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    environment.runtimeState.ready.value = true;
    environment.settingsState.store.navShowFavorites = true;
    environment.accountState.store.accounts.add(
      Account(uid: '556911', cookie: 'c', nickname: '土豆'),
    );
    environment.accountState.store.activeUid = '556911';
    final transfers = buildTransferManagerForEnvironment(environment);
    addTearDown(transfers.dispose);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await environment.db.addFavorite(
          kind: 'shareFile',
          name: 'favorite-$i.txt',
          ref: 'https://example.com/$i',
        );
      }
    });
    await tester.pumpWidget(_favoritesHost(environment, transfers));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'favorite');
    await tester.pumpAndSettle();

    final favoritesBeforeResize = tester.state(find.byType(FavoritesPage));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'favorite',
    );

    tester.view.physicalSize = const Size(900, 800);
    await tester.pumpAndSettle();
    expect(
      tester.state(find.byType(FavoritesPage)),
      same(favoritesBeforeResize),
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'favorite',
    );

    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(
      tester.state(find.byType(FavoritesPage)),
      same(favoritesBeforeResize),
    );
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();

    Material selectionMaterial() => tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('favorites-selection-appbar')),
            matching: find.byType(Material),
          )
          .first,
    );
    final scheme = Theme.of(tester.element(find.byType(FavoritesPage)))
        .colorScheme;
    expect(selectionMaterial().color, scheme.surface);

    await tester.drag(
      find.descendant(
        of: find.byType(FavoritesPage),
        matching: find.byType(CustomScrollView),
      ),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    expect(selectionMaterial().color, scheme.surfaceContainer);
    expect(
      tester.state(find.byType(FavoritesPage)),
      same(favoritesBeforeResize),
    );
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
  });

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
