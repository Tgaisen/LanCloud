import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/app.dart';
import 'package:lancloud/core/account_state.dart';
import 'package:lancloud/core/account_session.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/data/settings_store_provider.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/profile_page.dart';
import 'package:provider/provider.dart';

import 'package:lancloud/l10n/delegates.dart';

Widget _rootShellHost(
  AppController app,
  TransferManager transfers,
) => ProviderScope(
  overrides: [
    settingsStoreProvider.overrideWithValue(app.settings),
    accountStateProvider.overrideWithValue(app.accountState),
    accountSessionProvider.overrideWithValue(app.accountSession),
    transferManagerProvider.overrideWithValue(transfers),
    navigationAppearanceSettingsStateProvider.overrideWithValue(
      app.navigationAppearanceSettings,
    ),
    navigationStateProvider.overrideWithValue(app.navigation),
  ],
  child: ChangeNotifierProvider<AppController>.value(
    value: app,
    child: MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: const RootShell(),
    ),
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
    final app = AppController();
    addTearDown(app.dispose);
    app.ready = true;
    app.accounts.accounts.add(
      Account(uid: '556911', cookie: 'c', nickname: '土豆'),
    );
    app.accounts.activeUid = '556911';
    final transfers = TransferManager(app);
    addTearDown(transfers.dispose);
    await tester.pumpWidget(
      _rootShellHost(app, transfers),
    );
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
    final app = AppController();
    addTearDown(app.dispose);
    app.ready = true;
    app.accounts.accounts.add(
      Account(uid: '556911', cookie: 'c', nickname: '土豆'),
    );
    app.accounts.activeUid = '556911';
    final transfers = TransferManager(app);
    addTearDown(transfers.dispose);
    transfers.tasks.add(
      TransferTask(
        id: 't1',
        kind: TransferKind.upload,
        name: 'a.zip',
        accountUid: '556911',
      )..status = TransferStatus.running,
    );

    await tester.pumpWidget(_rootShellHost(app, transfers));
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
