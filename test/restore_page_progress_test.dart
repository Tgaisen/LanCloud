import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/backup/backup_crypto.dart';
import 'package:lancloud/core/backup/backup_dependencies.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/backup_service_provider.dart';
import 'package:lancloud/core/backup/webdav_client.dart';
import 'package:lancloud/core/cookie_auth.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/restore_page.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:material_ui/material_ui.dart';

BackupDependencies backupDependenciesFor(AppController app) =>
    BackupStoreDependencies(
      accounts: app.accountState.store,
      settings: app.settingsState.store,
      db: app.db,
      reloadCallback: app.reloadFromStorage,
    );

class _RestoreBackupService extends BackupService {
  _RestoreBackupService(AppController app, this.content)
    : super(backupDependenciesFor(app));

  final String content;

  @override
  Future<List<WebdavEntry>> remoteBackupsWithConnection({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async => const [
    WebdavEntry(name: 'lancloud-latest.json', href: '', size: 100),
  ];

  @override
  Future<String> webdavDownloadWithConnection(
    String name, {
    required String url,
    required String username,
    required String password,
    required String path,
  }) async => content;
}

class _GatedCookieAuth extends CookieAuth {
  final Completer<CookieAuthResult> result = Completer<CookieAuthResult>();

  @override
  Future<CookieAuthResult> verify(
    String reason, {
    Iterable<AuthMessages> messages = const <AuthMessages>[],
  }) => result.future;
}

void main() {
  testWidgets('首次恢复时解密弹窗关闭后才显示顶栏进度条', (tester) async {
    final app = AppController();
    addTearDown(app.dispose);
    final plaintext = jsonEncode({
      'app': 'lancloud',
      'format': 3,
      'sections': ['webdavAccount'],
      'tables': <String, Object?>{},
      'webdav': {
        'url': 'https://dav.example.com/dav/',
        'username': 'user',
        'password': 'pwd',
        'backupPassphrase': 'backup-secret',
        'path': '/LanCloud',
      },
    });
    final encryption = await BackupCrypto.encrypt(
      plaintext,
      passphrase: 'backup-secret',
      iterations: 1000,
    );
    final encrypted = jsonEncode({
      'app': 'lancloud',
      'format': 3,
      'encryption': encryption,
    });
    final service = _RestoreBackupService(app, encrypted);
    final auth = _GatedCookieAuth();
    CookieAuth.instance = auth;
    addTearDown(() {
      CookieAuth.instance = CookieAuth();
    });

    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupServiceProvider.overrideWithValue(service),
          navigationAppearanceSettingsStateProvider.overrideWithValue(
            app.navigationAppearanceSettings,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const RestorePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('WebDAV 云端'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(4));
    await tester.enterText(fields.at(0), 'https://dav.example.com/dav/');
    await tester.enterText(fields.at(1), 'user');
    await tester.enterText(fields.at(2), 'pwd');
    await tester.tap(find.text('连接并查找备份'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('lancloud-latest.json'));
    await tester.pumpAndSettle();
    expect(find.text('解锁加密备份'), findsOneWidget);
    expect(find.byType(M3eLinearProgressIndicator), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('backup-unlock-passphrase')),
      'backup-secret',
    );
    await tester.tap(find.text('解锁'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('解锁加密备份').evaluate().isEmpty) break;
    }

    expect(find.text('解锁加密备份'), findsNothing);
    expect(find.byType(M3eLinearProgressIndicator), findsOneWidget);

    auth.result.complete(CookieAuthResult.ok);
    await tester.pumpAndSettle();
    expect(find.byType(M3eLinearProgressIndicator), findsNothing);
  });
}
