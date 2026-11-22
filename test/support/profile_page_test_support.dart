import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/app_startup.dart';
import 'package:lancloud/core/backup/backup_dependencies.dart';
import 'package:lancloud/core/backup/backup_sections.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/webdav_store.dart';
import 'package:lancloud/core/cookie_auth.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/profile_page.dart';
import 'package:local_auth_android/local_auth_android.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'app_test_scope.dart';

export 'transfer_test_support.dart' show buildTransferManagerForEnvironment;

Future<void> _reloadFromStorage(AppEnvironment environment) =>
    AppStartup(environment: environment, onChanged: () {}).reloadFromStorage();

BackupDependencies backupDependenciesFor(AppEnvironment environment) =>
    BackupStoreDependencies(
      accounts: environment.accountState.store,
      settings: environment.settingsState.store,
      db: environment.db,
      reloadCallback: () => _reloadFromStorage(environment),
    );

class NoopBackupService extends BackupService {
  NoopBackupService(AppEnvironment environment)
    : super(backupDependenciesFor(environment));

  @override
  Future<void> init() async {}
}

class RecordingWebdavStore extends WebdavStore {
  Map<String, String>? _secureAccount;
  String _legacyPassword = '';

  @override
  Future<Map<String, String>?> readSecureAccount() async =>
      _secureAccount == null ? null : Map.of(_secureAccount!);

  @override
  Future<void> writeSecureAccount(Map<String, String> value) async {
    _secureAccount = Map.of(value);
  }

  @override
  Future<void> deleteSecureAccount() async => _secureAccount = null;

  @override
  Future<String> readLegacyPassword() async => _legacyPassword;

  @override
  Future<void> deleteLegacyPassword() async => _legacyPassword = '';
}

class RecordingBackupService extends BackupService {
  RecordingBackupService(AppEnvironment environment)
    : super(backupDependenciesFor(environment));

  final _store = RecordingWebdavStore();
  int exportCount = 0;

  @override
  WebdavStore get webdav => _store;

  @override
  Future<void> init() => _store.load();

  @override
  Future<File> exportFile({
    Set<BackupSection> sections = const {},
    String? passphrase,
    DateTime? now,
  }) async {
    exportCount += 1;
    return File('${Directory.systemTemp.path}/profile-backup-test.json');
  }
}

class FakeProfileCookieAuth extends CookieAuth {
  int calls = 0;

  @override
  Future<CookieAuthResult> verify(
    String reason, {
    Iterable<AuthMessages> messages = const <AuthMessages>[],
  }) async {
    calls += 1;
    return CookieAuthResult.ok;
  }
}

class ProfileTestProviders extends StatelessWidget {
  const ProfileTestProviders.value({
    super.key,
    required this.value,
    required this.child,
    this.container,
    this.backupService,
    this.transferManager,
  });

  final AppEnvironment value;
  final Widget child;
  final ProviderContainer? container;
  final BackupService? backupService;
  final TransferManager? transferManager;

  @override
  Widget build(BuildContext context) {
    final updateContainer = container;
    if (updateContainer != null) {
      return updateEnvironmentTestTree(
        environment: value,
        container: updateContainer,
        child: child,
      );
    }
    return appEnvironmentTestTree(
      environment: value,
      child: child,
      backupService: backupService,
      transferManager: transferManager,
    );
  }
}

/// 起一个「两栏“我的”页」的测试环境。
Future<void> pumpTwoPane(WidgetTester tester) async {
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
