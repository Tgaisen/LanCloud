import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/app_permissions.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/settings_page.dart';
import 'package:provider/provider.dart';

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
    await scrollToSetting(tester, '相机（扫码）');

    expect(find.text('权限'), findsOneWidget);
    expect(find.text('相机（扫码）'), findsOneWidget);
    expect(find.text('安装应用（打开 APK）'), findsOneWidget);
    expect(find.text('电池优化'), findsOneWidget);
    expect(find.text('未授权，点击授权'), findsOneWidget);
    expect(find.text('未允许，打开 APK 安装包前需授权'), findsOneWidget);
    expect(find.text('受电池优化限制，后台传输可能被中断'), findsOneWidget);
  });

  testWidgets('点击相机发起请求，授权后状态刷新', (tester) async {
    await pumpSettings(tester);
    await scrollToSetting(tester, '相机（扫码）');

    await tester.tap(find.text('相机（扫码）'));
    await tester.pumpAndSettle();

    expect(_fake.cameraRequests, 1);
    expect(tileStatus('相机（扫码）', '已授权'), findsOneWidget);
  });

  testWidgets('相机被系统拒绝时引导去系统设置', (tester) async {
    _fake.cameraResult = PermissionState.blocked;

    await pumpSettings(tester);
    await scrollToSetting(tester, '相机（扫码）');
    await tester.tap(find.text('相机（扫码）'));
    await tester.pumpAndSettle();

    expect(find.text('需要到系统设置开启'), findsOneWidget);
    await tester.tap(find.text('打开系统设置'));
    await tester.pumpAndSettle();
    expect(_fake.appSettingsOpens, 1);
  });

  testWidgets('安装应用与电池优化分别走各自通道', (tester) async {
    await pumpSettings(tester);
    await scrollToSetting(tester, '安装应用（打开 APK）');

    await tester.tap(find.text('安装应用（打开 APK）'));
    await tester.pumpAndSettle();
    expect(_fake.installOpens, 1);

    await scrollToSetting(tester, '电池优化');
    await tester.tap(find.text('电池优化'));
    await tester.pumpAndSettle();
    expect(_fake.batteryRequests, 1);
  });

  testWidgets('设置底部新增隐私分组，包含显示 Cookie', (tester) async {
    await pumpSettings(tester);
    await scrollToSetting(tester, '显示 Cookie');

    expect(find.text('隐私'), findsOneWidget);
    expect(find.text('显示 Cookie'), findsOneWidget);
    expect(find.text('需通过生物识别 / 锁屏验证'), findsOneWidget);
  });
}
