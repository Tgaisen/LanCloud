import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/app_permissions.dart';
import 'package:lancloud/core/platform_capabilities.dart';
import 'package:lancloud/core/settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/app_localizations_zh.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/settings_page.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'support/app_test_scope.dart';

/// 文案以中文本地化为准，避免改文案就要改测试。
final _zh = AppLocalizationsZh();

class _FakePermissions extends AppPermissions {
  PermissionSnapshot snapshot = const PermissionSnapshot(
    install: PermissionState.denied,
    battery: PermissionState.denied,
  );
  int installOpens = 0;
  int batteryRequests = 0;

  @override
  Future<PermissionSnapshot> status() async => snapshot;

  @override
  Future<bool> openInstallSettings() async {
    installOpens += 1;
    return true;
  }

  @override
  Future<bool> requestBattery() async {
    batteryRequests += 1;
    return true;
  }
}

late _FakePermissions _fake;

Future<AppEnvironment> pumpSettings(
  WidgetTester tester, {
  bool hideTopBar = false,
  SettingsCategory category = SettingsCategory.behaviorPermissions,
  PlatformCapabilities capabilities = PlatformCapabilities.android,
}) async {
  final environment = AppEnvironment();
  environment.settingsState.store.hideTopBar = hideTopBar;
  addTearDown(environment.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        platformCapabilitiesProvider.overrideWithValue(capabilities),
        settingsStateProvider.overrideWithValue(environment.settingsState),
      ],
      child: appEnvironmentTestTree(
        environment: environment,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: SettingsCategoryPage(category: category),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return environment;
}

Future<void> scrollToSetting(WidgetTester tester, String text) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(find.text(text), 400, scrollable: scrollable);
  // 顶栏是浮层、不占布局：ensureVisible 会把目标顶到屏幕上沿，
  // 正好被顶栏盖住（点不到），这里往回拖一段让它落在顶栏下方。
  await tester.drag(scrollable, const Offset(0, 120));
  await tester.pumpAndSettle();
}

Future<void> expectSystemSettingsEntries(
  WidgetTester tester, {
  required bool visible,
}) async {
  await tester.tap(find.byTooltip(_zh.searchSettings));
  await tester.pumpAndSettle();
  for (final label in [
    _zh.managePermissions,
    _zh.manageDefaultLinks,
    _zh.openSystemSettings,
  ]) {
    await tester.enterText(find.byType(TextField), label);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(ListTile, label),
      visible ? findsOneWidget : findsNothing,
      reason: label,
    );
  }
}

Future<void> expectNotificationEntries(
  WidgetTester tester, {
  required bool progressVisible,
  required bool doneVisible,
  required bool favoriteUpdateVisible,
  required bool favoriteAutoCheckVisible,
}) async {
  await tester.tap(find.byTooltip(_zh.searchSettings));
  await tester.pumpAndSettle();
  for (final (:label, :visible) in [
    (label: _zh.notifProgress, visible: progressVisible),
    (label: _zh.notifDone, visible: doneVisible),
    (label: _zh.favoriteUpdateNotify, visible: favoriteUpdateVisible),
  ]) {
    await tester.enterText(find.byType(TextField), label);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(ListTile, label),
      visible ? findsOneWidget : findsNothing,
      reason: label,
    );
  }
  await tester.enterText(find.byType(TextField), _zh.favoriteAutoCheck);
  await tester.pumpAndSettle();
  expect(
    find.widgetWithText(ListTile, _zh.favoriteAutoCheck),
    favoriteAutoCheckVisible ? findsOneWidget : findsNothing,
  );
}

void main() {
  setUp(() {
    _fake = _FakePermissions();
    AppPermissions.instance = _fake;
  });

  tearDown(() {
    AppPermissions.instance = AppPermissions();
  });

  testWidgets('权限分组只有「管理权限」一个入口，弹窗里是三项系统权限', (tester) async {
    await pumpSettings(tester);
    await scrollToSetting(tester, _zh.managePermissions);

    expect(find.text(_zh.categoryPermissions), findsOneWidget);
    expect(find.text(_zh.managePermissions), findsOneWidget);
    // 三项不再各自占一行
    expect(find.text(_zh.permissionInstall), findsNothing);
    expect(find.text(_zh.permissionBattery), findsNothing);
    expect(find.text(_zh.notifPermission), findsNothing);

    await tester.tap(find.text(_zh.managePermissions));
    await tester.pumpAndSettle();

    expect(find.text(_zh.notifPermission), findsOneWidget);
    expect(find.text(_zh.permissionInstall), findsOneWidget);
    expect(find.text(_zh.permissionBattery), findsOneWidget);
    expect(find.text(_zh.permissionInstallDenied), findsOneWidget);
    expect(find.text(_zh.permissionBatteryRestricted), findsOneWidget);
  });

  testWidgets('Android 能力下显式保留三个系统设置入口', (tester) async {
    await pumpSettings(tester);

    await expectSystemSettingsEntries(tester, visible: true);
  });

  testWidgets('Windows 能力下隐藏三个 Android 专属设置入口', (tester) async {
    await pumpSettings(tester, capabilities: PlatformCapabilities.windows);

    await expectSystemSettingsEntries(tester, visible: false);
  });

  testWidgets('iOS 能力下隐藏三个 Android 专属设置入口', (tester) async {
    await pumpSettings(tester, capabilities: PlatformCapabilities.ios);

    await expectSystemSettingsEntries(tester, visible: false);
  });

  testWidgets('Android 通知能力下保留三个通知设置入口', (tester) async {
    await pumpSettings(
      tester,
      category: SettingsCategory.notificationsReminders,
      capabilities: PlatformCapabilities.android,
    );

    await expectNotificationEntries(
      tester,
      progressVisible: true,
      doneVisible: true,
      favoriteUpdateVisible: true,
      favoriteAutoCheckVisible: true,
    );
  });

  testWidgets('Windows 通知能力下隐藏进度通知，保留终态与收藏更新', (tester) async {
    await pumpSettings(
      tester,
      category: SettingsCategory.notificationsReminders,
      capabilities: PlatformCapabilities.windows,
    );

    await expectNotificationEntries(
      tester,
      progressVisible: false,
      doneVisible: true,
      favoriteUpdateVisible: true,
      favoriteAutoCheckVisible: true,
    );
  });

  testWidgets('iOS 通知能力下隐藏通知开关但保留收藏自动检测', (tester) async {
    await pumpSettings(
      tester,
      category: SettingsCategory.notificationsReminders,
      capabilities: PlatformCapabilities.ios,
    );

    await expectNotificationEntries(
      tester,
      progressVisible: false,
      doneVisible: false,
      favoriteUpdateVisible: false,
      favoriteAutoCheckVisible: true,
    );
  });

  testWidgets('设置页顶栏同样是浮层：上滑随手指渐隐，底色不渐隐', (tester) async {
    final environment = await pumpSettings(tester, hideTopBar: true);

    double barTop() =>
        tester.getTopLeft(find.byType(AppBar, skipOffstage: false)).dy;
    double contentOpacity() => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byType(AppBar, skipOffstage: false),
                matching: find.byType(Opacity, skipOffstage: false),
              )
              .first,
        )
        .opacity;

    expect(barTop(), 0);
    expect(contentOpacity(), 1);

    // 滑过一个顶栏高度：顶栏内容完全淡出，底栏视图共用的外壳进度不受影响
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(barTop(), -kToolbarHeight);
    expect(contentOpacity(), closeTo(0, 0.01));
    final background = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(TopBarOverlay, skipOffstage: false),
            matching: find.byType(ColoredBox, skipOffstage: false),
          )
          .first,
    );
    expect(background.color.a, 1);
    expect(environment.navigation.topBarHide.value, 0);

    // 滑回顶部恢复显示
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(barTop(), 0);
    expect(contentOpacity(), 1);
  });

  testWidgets('管理权限弹窗里安装应用与电池优化分别走各自通道', (tester) async {
    await pumpSettings(tester);
    await scrollToSetting(tester, _zh.managePermissions);

    await tester.tap(find.text(_zh.managePermissions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_zh.permissionInstall));
    await tester.pumpAndSettle();
    expect(_fake.installOpens, 1);

    await scrollToSetting(tester, _zh.managePermissions);
    await tester.tap(find.text(_zh.managePermissions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_zh.permissionBattery));
    await tester.pumpAndSettle();
    expect(_fake.batteryRequests, 1);
  });

  testWidgets('设置底部新增隐私分组，包含显示 Cookie', (tester) async {
    await pumpSettings(tester, category: SettingsCategory.privacyData);
    await scrollToSetting(tester, _zh.showCookie);

    expect(find.text(_zh.categoryPrivacy), findsOneWidget);
    expect(find.text(_zh.showCookie), findsOneWidget);
    expect(find.text(_zh.showCookieSubtitle), findsOneWidget);
  });
}
