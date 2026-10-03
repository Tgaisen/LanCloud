import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/app_permissions.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/app_localizations_zh.dart';
import 'package:lancloud/ui/settings_page.dart';
import 'package:provider/provider.dart';

/// 文案以中文本地化为准，避免改文案就要改测试。
final _zh = AppLocalizationsZh();

class _FakePermissions extends AppPermissions {
  PermissionSnapshot snapshot = const PermissionSnapshot(
    camera: PermissionState.denied,
    install: PermissionState.denied,
    battery: PermissionState.denied,
  );
  PermissionState cameraResult = PermissionState.granted;
  int cameraRequests = 0;
  int installOpens = 0;
  int batteryRequests = 0;
  int appSettingsOpens = 0;

  @override
  Future<PermissionSnapshot> status() async => snapshot;

  @override
  Future<PermissionState> requestCamera() async {
    cameraRequests += 1;
    snapshot = PermissionSnapshot(
      camera: cameraResult,
      install: snapshot.install,
      battery: snapshot.battery,
    );
    return cameraResult;
  }

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

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpens += 1;
    return true;
  }
}

late _FakePermissions _fake;

Future<void> pumpSettings(WidgetTester tester) async {
  final app = AppController();
  addTearDown(app.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const SettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> scrollToSetting(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Finder tileStatus(String tile, String status) => find.descendant(
      of: find.widgetWithText(ListTile, tile),
      matching: find.text(status),
    );

void main() {
  setUp(() {
    _fake = _FakePermissions();
    AppPermissions.instance = _fake;
  });

  tearDown(() {
    AppPermissions.instance = AppPermissions();
  });

  testWidgets('权限分组显示相机/安装应用/电池优化三项状态', (tester) async {
    await pumpSettings(tester);
    await scrollToSetting(tester, _zh.permissionCamera);

    expect(find.text(_zh.categoryPermissions), findsOneWidget);
    expect(find.text(_zh.permissionCamera), findsOneWidget);
    expect(find.text(_zh.permissionInstall), findsOneWidget);
    expect(find.text(_zh.permissionBattery), findsOneWidget);
    expect(find.text(_zh.permissionDenied), findsOneWidget);
    expect(find.text(_zh.permissionInstallDenied), findsOneWidget);
    expect(find.text(_zh.permissionBatteryRestricted), findsOneWidget);
  });

  testWidgets('点击相机发起请求，授权后状态刷新', (tester) async {
    await pumpSettings(tester);
    await scrollToSetting(tester, _zh.permissionCamera);

    await tester.tap(find.text(_zh.permissionCamera));
    await tester.pumpAndSettle();

    expect(_fake.cameraRequests, 1);
    expect(tileStatus(_zh.permissionCamera, _zh.permissionGranted), findsOneWidget);
  });

  testWidgets('相机被系统拒绝时引导去系统设置', (tester) async {
    _fake.cameraResult = PermissionState.blocked;

    await pumpSettings(tester);
    await scrollToSetting(tester, _zh.permissionCamera);
    await tester.tap(find.text(_zh.permissionCamera));
    await tester.pumpAndSettle();

    expect(find.text(_zh.permissionBlockedTitle), findsOneWidget);
    await tester.tap(find.text(_zh.permissionOpenSystemSettings));
    await tester.pumpAndSettle();
    expect(_fake.appSettingsOpens, 1);
  });

  testWidgets('安装应用与电池优化分别走各自通道', (tester) async {
    await pumpSettings(tester);
    await scrollToSetting(tester, _zh.permissionInstall);

    await tester.tap(find.text(_zh.permissionInstall));
    await tester.pumpAndSettle();
    expect(_fake.installOpens, 1);

    await scrollToSetting(tester, _zh.permissionBattery);
    await tester.tap(find.text(_zh.permissionBattery));
    await tester.pumpAndSettle();
    expect(_fake.batteryRequests, 1);
  });

  testWidgets('设置底部新增隐私分组，包含显示 Cookie', (tester) async {
    await pumpSettings(tester);
    await scrollToSetting(tester, _zh.showCookie);

    expect(find.text(_zh.categoryPrivacy), findsOneWidget);
    expect(find.text(_zh.showCookie), findsOneWidget);
    expect(find.text(_zh.showCookieSubtitle), findsOneWidget);
  });
}
