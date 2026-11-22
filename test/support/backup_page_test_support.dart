import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/app_startup.dart';
import 'package:lancloud/core/backup/backup_dependencies.dart';
import 'package:lancloud/core/backup/backup_sections.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/backup_service_provider.dart';
import 'package:lancloud/core/backup/webdav_client.dart';
import 'package:lancloud/core/backup/webdav_store.dart';
import 'package:lancloud/core/cookie_auth.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/backup_page.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lancloud/l10n/delegates.dart';

Future<void> _reloadFromStorage(AppEnvironment environment) =>
    AppStartup(environment: environment, onChanged: () {}).reloadFromStorage();

BackupDependencies backupDependenciesFor(AppEnvironment environment) =>
    BackupStoreDependencies(
      accounts: environment.accountState.store,
      settings: environment.settingsState.store,
      db: environment.db,
      reloadCallback: () => _reloadFromStorage(environment),
    );

class FakeBackupService extends BackupService {
  FakeBackupService(this.environment)
    : super(backupDependenciesFor(environment));

  final AppEnvironment environment;

  final FakeWebdavStore _store = FakeWebdavStore();

  @override
  WebdavStore get webdav => _store;

  @override
  Future<void> init() => _store.load();

  int saveCount = 0;
  int uploadCount = 0;
  int testCount = 0;
  int restoreCount = 0;
  String? lastRestoredContent;
  bool? lastMergeFavorites;
  bool? lastRestoreAccounts;
  Set<BackupSection>? lastSections;
  String? lastPassphrase;
  Completer<void>? exportGate;
  Completer<void>? uploadGenerationGate;
  Completer<void>? uploadGate;

  /// 云端恢复列表：测试里按需设置；[remoteGate] 用来卡住「拉列表」这一步，
  /// 观察进度线在列表回来前后是否收起。
  List<WebdavEntry> remoteEntries = const [];
  Completer<void>? remoteGate;
  String downloadedContent = '';

  @override
  Future<File> exportFile({
    Set<BackupSection> sections = const {},
    String? passphrase,
    DateTime? now,
  }) async {
    final gate = exportGate;
    if (gate != null) await gate.future;
    saveCount += 1;
    lastSections = sections;
    lastPassphrase = passphrase;
    return File('${Directory.systemTemp.path}/lancloud-backup-test.json');
  }

  @override
  Future<void> testConnection({CancelToken? cancelToken}) async {
    testCount += 1;
  }

  @override
  Future<String> uploadNow({
    Set<BackupSection>? sections,
    DateTime? now,
    void Function()? onGenerated,
    CancelToken? cancelToken,
  }) async {
    final generationGate = uploadGenerationGate;
    if (generationGate != null) await generationGate.future;
    onGenerated?.call();
    final networkGate = uploadGate;
    if (networkGate != null) await networkGate.future;
    uploadCount += 1;
    lastSections = sections ?? _store.backupSections;
    return 'lancloud-backup-20261002-181500.json';
  }

  @override
  Future<void> restoreFromString(
    String content, {
    String? passphrase,
    bool mergeFavorites = false,
    bool restoreAccounts = true,
  }) async {
    restoreCount += 1;
    lastRestoredContent = content;
    lastMergeFavorites = mergeFavorites;
    lastRestoreAccounts = restoreAccounts;
  }

  @override
  Future<List<WebdavEntry>> remoteBackups({CancelToken? cancelToken}) async {
    final gate = remoteGate;
    if (gate != null) await gate.future;
    return remoteEntries;
  }

  @override
  Future<String> webdavDownload(
    String name, {
    CancelToken? cancelToken,
  }) async => downloadedContent;
}

/// 测试环境没有安全存储插件，密码改放内存。
class FakeWebdavStore extends WebdavStore {
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

class FakeBackupCookieAuth extends CookieAuth {
  FakeBackupCookieAuth(this.result);

  CookieAuthResult result;
  int calls = 0;

  @override
  Future<CookieAuthResult> verify(
    String reason, {
    Iterable<AuthMessages> messages = const <AuthMessages>[],
  }) async {
    calls += 1;
    return result;
  }
}

final class BackupPageHarness {
  late FakeBackupService fake;
  late FakeBackupCookieAuth fakeAuth;
  late List<MethodCall> savedCalls;
  String? saveResult;

  static const _saveChannel = MethodChannel('lancloud/file_picker');

  void setUp() {
    SharedPreferences.setMockInitialValues({});
    fake = FakeBackupService(AppEnvironment());
    addTearDown(fake.environment.dispose);
    fakeAuth = FakeBackupCookieAuth(CookieAuthResult.ok);
    CookieAuth.instance = fakeAuth;
    savedCalls = [];
    saveResult = 'lancloud-backup-test.json';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_saveChannel, (call) async {
          if (call.method != 'saveFile') return null;
          savedCalls.add(call);
          return saveResult;
        });
  }

  void tearDown() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_saveChannel, null);
    CookieAuth.instance = CookieAuth();
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupServiceProvider.overrideWithValue(fake),
          navigationAppearanceSettingsStateProvider.overrideWithValue(
            fake.environment.navigationAppearanceSettings,
          ),
          navigationStateProvider.overrideWithValue(
            fake.environment.navigation,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const BackupPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}
