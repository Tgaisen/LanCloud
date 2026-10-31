import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/account_state.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/backup/backup_dependencies.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/backup_service_provider.dart';
import 'package:lancloud/core/drive_state.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/login_page.dart';
import 'package:lancloud/ui/m3e.dart';

import 'package:lancloud/l10n/delegates.dart';

Future<void> _noopReload() async {}

BackupDependencies backupDependenciesFor(AppEnvironment environment) =>
    BackupStoreDependencies(
      accounts: environment.accountState.store,
      settings: environment.settingsState.store,
      db: environment.db,
      reloadCallback: _noopReload,
    );

Widget host(Widget home, {AppEnvironment? environment}) {
  final current = environment ?? AppEnvironment();
  addTearDown(current.dispose);
  return ProviderScope(
    overrides: [
      accountStateProvider.overrideWithValue(current.accountState),
      lanzouClientRegistryProvider.overrideWithValue(current.clientRegistry),
      driveStateProvider.overrideWithValue(current.drive),
      backupServiceProvider.overrideWithValue(
        BackupService(backupDependenciesFor(current)),
      ),
      navigationAppearanceSettingsStateProvider.overrideWithValue(
        current.navigationAppearanceSettings,
      ),
      navigationStateProvider.overrideWithValue(current.navigation),
    ],
    child: MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: home,
    ),
  );
}

void main() {
  testWidgets('登录弹窗：标题「登录」+ 两个入口，Cookie 输入在弹窗内', (tester) async {
    await tester.pumpWidget(
      host(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showLoginSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('网页登录'), findsOneWidget);
    expect(find.text('Cookie 登录'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Cookie 登录'));
    await tester.pumpAndSettle();
    expect(find.text('如何获取 Cookie'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('兜底登录页内容与弹窗一致（页面内没有 Cookie 输入框）', (tester) async {
    await tester.pumpWidget(host(const LoginPage(firstRun: true)));
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('网页登录'), findsOneWidget);
    expect(find.text('Cookie 登录'), findsOneWidget);
    expect(find.text('从已有备份恢复'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('安全存储重置后明确提示需要重新登录且保留其他数据', (tester) async {
    await tester.pumpWidget(
      host(const LoginPage(firstRun: true, credentialsResetNotice: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('需要重新登录'), findsOneWidget);
    expect(find.textContaining('收藏、设置和本地文件仍会保留'), findsOneWidget);
  });

  testWidgets('开始使用页使用 MD3E 图标框而不是重复展示应用 Logo', (tester) async {
    await tester.pumpWidget(host(const LoginPage(firstRun: true)));
    await tester.pumpAndSettle();

    final iconBox = tester.widget<M3eShapedIcon>(find.byType(M3eShapedIcon));
    expect(iconBox.size, 88);
    expect(iconBox.iconSize, 44);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('大屏登录页使用登录 / 恢复两个列表组，并可进入备份来源选择', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(const LoginPage(firstRun: true)));
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);
    final restore = find.widgetWithText(ListTile, '从已有备份恢复');
    expect(restore, findsOneWidget);
    expect(tester.widget<ListTile>(restore).subtitle, isNull);
    expect(find.widgetWithText(OutlinedButton, '从已有备份恢复'), findsNothing);
    expect(tester.getSize(restore).width, lessThanOrEqualTo(480));

    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.text('请选择备份来源'), findsOneWidget);
    expect(find.byType(Md3eBodyCard), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
      Theme.of(tester.element(find.byType(Md3eBodyCard)))
          .colorScheme
          .surfaceContainer,
    );
    expect(find.text('本地备份文件'), findsOneWidget);
    expect(find.text('WebDAV 云端'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, '本地备份文件'),
        matching: find.byIcon(app_icons.Icons.chevron_right),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'WebDAV 云端'),
        matching: find.byIcon(app_icons.Icons.chevron_right),
      ),
      findsNothing,
    );

    await tester.tap(find.text('WebDAV 云端'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.text('备份密码'), findsNothing);
    expect(find.text('连接并查找备份'), findsOneWidget);
    expect(find.text('建议使用 HTTPS，避免 WebDAV 密码在不安全连接中传输。'), findsNothing);
  });

  testWidgets('HTTP WebDAV 继续连接前弹出不安全连接提醒', (tester) async {
    await tester.pumpWidget(host(const LoginPage(firstRun: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '从已有备份恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WebDAV 云端'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).at(0),
      'http://dav.example.com/',
    );
    await tester.enterText(find.byType(TextField).at(1), 'user');
    await tester.enterText(find.byType(TextField).at(2), 'password');
    await tester.tap(find.text('连接并查找备份'));
    await tester.pumpAndSettle();

    expect(find.text('连接不安全'), findsOneWidget);
    expect(find.text('建议使用 HTTPS 连接，是否继续？'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('连接不安全'), findsNothing);
  });

  testWidgets('恢复页顶栏随滚动渐变并收纳', (tester) async {
    final environment = AppEnvironment();
    environment.settingsState.store.hideTopBar = true;
    tester.view.physicalSize = const Size(400, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(const LoginPage(firstRun: true), environment: environment),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '从已有备份恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WebDAV 云端'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(400, 320);
    await tester.pumpAndSettle();

    final initialBar = tester.widget<TopBarOverlay>(find.byType(TopBarOverlay));
    final initialTop = tester.getTopLeft(find.byType(AppBar)).dy;
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();

    final scrolledBar = tester.widget<TopBarOverlay>(
      find.byType(TopBarOverlay),
    );
    expect(scrolledBar.background, isNot(initialBar.background));
    expect(tester.getTopLeft(find.byType(AppBar)).dy, lessThan(initialTop));
  });

  testWidgets('从恢复页直接返回时不会误报数据已恢复', (tester) async {
    await tester.pumpWidget(host(const LoginPage(firstRun: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '从已有备份恢复'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(app_icons.Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('数据已恢复，请继续登录'), findsNothing);
    expect(find.text('从已有备份恢复'), findsOneWidget);
  });

  testWidgets('开始使用页使用透明的沉浸式系统栏', (tester) async {
    await tester.pumpWidget(host(const LoginPage(firstRun: true)));
    await tester.pumpAndSettle();

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find
          .descendant(
            of: find.byType(LoginPage),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          )
          .first,
    );
    expect(region.value.statusBarColor, Colors.transparent);
    expect(region.value.systemNavigationBarColor, Colors.transparent);
    expect(region.value.systemNavigationBarContrastEnforced, isFalse);
  });

  testWidgets('兜底登录页铺满屏幕高度（回弹不截断）', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(const LoginPage(firstRun: true)));
    await tester.pumpAndSettle();

    // 滚动视图占满整屏：iOS 回弹时内容不会被缩水的高度截断
    expect(tester.getSize(find.byType(SingleChildScrollView)).height, 800);
  });

  testWidgets('Cookie 登录入口使用 badge 图标且不显示右箭头', (tester) async {
    await tester.pumpWidget(host(const LoginPage(firstRun: true)));
    await tester.pumpAndSettle();

    final cookieTile = find.widgetWithText(ListTile, 'Cookie 登录');
    expect(
      find.descendant(
        of: cookieTile,
        matching: find.byIcon(app_icons.Icons.badge_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cookieTile,
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsNothing,
    );
  });

  testWidgets('Cookie 登录输入框使用统一的 MD3E error state', (tester) async {
    await tester.pumpWidget(
      host(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCookieLoginDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存并登录'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.errorText, '请输入 Cookie');
    expect(find.text('请输入 Cookie'), findsOneWidget);
    expect(find.byIcon(app_icons.Icons.error), findsOneWidget);
  });
}
