import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/backup/backup_sections.dart';
import 'package:lancloud/core/cookie_auth.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/backup_options_page.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'support/profile_page_test_support.dart';

void main() {
  testWidgets('大屏备份选项确认后，本地保存与 WebDAV 设置都会继续执行', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final app = AppEnvironment();
    addTearDown(app.dispose);
    final service = RecordingBackupService(app);
    final saveCalls = <MethodCall>[];
    const saveChannel = MethodChannel('lancloud/file_picker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(saveChannel, (call) async {
          if (call.method != 'saveFile') return null;
          saveCalls.add(call);
          return 'profile-backup-test.json';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(saveChannel, null),
    );

    await tester.pumpWidget(
      ProfileTestProviders.value(
        value: app,
        backupService: service,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('隐私与数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '备份与恢复'));
    await tester.pumpAndSettle();

    // 立即备份：从备份内容进入右窗格选项页，确认后必须继续生成并保存。
    await tester.tap(find.widgetWithText(ListTile, '立即备份'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BackupOptionsPage),
        matching: find.text('设置项'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '继续'));
    await tester.pumpAndSettle();

    expect(service.exportCount, 1);
    expect(saveCalls, hasLength(1));
    expect(find.textContaining('profile-backup-test.json'), findsOneWidget);

    // WebDAV 备份选项确认后，也必须由仍存活的 BackupContent 落盘。
    await tester.tap(find.widgetWithText(ListTile, '备份选项'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BackupOptionsPage),
        matching: find.text('设置项'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(service.webdav.backupSections, {BackupSection.settings});
    expect(find.byType(BackupOptionsPage), findsNothing);
  });

  testWidgets('大屏备份选项：敏感项仍会发起身份验证（回归）', (tester) async {
    final fakeAuth = FakeProfileCookieAuth();
    CookieAuth.instance = fakeAuth;
    addTearDown(() => CookieAuth.instance = CookieAuth());
    await pumpTwoPane(tester);

    await tester.tap(find.text('隐私与数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '备份与恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '备份选项'));
    await tester.pumpAndSettle();

    final sensitiveTile = find.descendant(
      of: find.byType(BackupOptionsPage),
      matching: find.text('账号列表与 Cookie'),
    );
    await tester.ensureVisible(sensitiveTile);
    await tester.pumpAndSettle();
    await tester.tap(sensitiveTile);
    await tester.pumpAndSettle();

    expect(fakeAuth.calls, 1);
    expect(
      tester
          .widget<M3ePickTile>(find.widgetWithText(M3ePickTile, '账号列表与 Cookie'))
          .selected,
      isTrue,
    );
  });
}
