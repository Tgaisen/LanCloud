import 'dart:async';
import 'dart:io';

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
import 'package:lancloud/l10n/app_localizations_zh.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/backup_page.dart';
import 'package:lancloud/ui/backup_options_page.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
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

class _FakeBackupService extends BackupService {
  _FakeBackupService(this.environment)
    : super(backupDependenciesFor(environment));

  final AppEnvironment environment;

  final _FakeWebdavStore _store = _FakeWebdavStore();

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
  Future<void> testConnection() async {
    testCount += 1;
  }

  @override
  Future<String> uploadNow({
    Set<BackupSection>? sections,
    DateTime? now,
    void Function()? onGenerated,
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
  Future<List<WebdavEntry>> remoteBackups() async {
    final gate = remoteGate;
    if (gate != null) await gate.future;
    return remoteEntries;
  }

  @override
  Future<String> webdavDownload(String name) async => downloadedContent;
}

/// 测试环境没有安全存储插件，密码改放内存。
class _FakeWebdavStore extends WebdavStore {
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

class _FakeCookieAuth extends CookieAuth {
  _FakeCookieAuth(this.result);

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

void main() {
  late _FakeBackupService fake;
  late _FakeCookieAuth fakeAuth;

  /// 系统「保存文件」对话框收到的调用；返回 null 表示用户取消。
  late List<MethodCall> savedCalls;
  late String? saveResult;

  const saveChannel = MethodChannel('lancloud/file_picker');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fake = _FakeBackupService(AppEnvironment());
    addTearDown(fake.environment.dispose);
    // 备份包含 Cookie 需要生物验证，测试里直接放行
    fakeAuth = _FakeCookieAuth(CookieAuthResult.ok);
    CookieAuth.instance = fakeAuth;
    savedCalls = [];
    saveResult = 'lancloud-backup-test.json';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(saveChannel, (call) async {
          if (call.method != 'saveFile') return null;
          savedCalls.add(call);
          return saveResult;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(saveChannel, null);
    CookieAuth.instance = CookieAuth();
  });

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

  testWidgets('备份页显示本地与 WebDAV 分组', (tester) async {
    await pumpPage(tester);

    expect(find.text('本地备份'), findsOneWidget);
    expect(find.text('立即备份'), findsOneWidget);
    expect(find.text('从文件恢复'), findsOneWidget);
    expect(find.text('WebDAV 账号'), findsOneWidget);
    expect(find.text('备份选项'), findsOneWidget);
    expect(find.text('自动备份'), findsOneWidget);
    expect(find.text('未配置 WebDAV'), findsOneWidget);
    expect(find.textContaining('上次备份'), findsNothing);
    final backupNowTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '立即备份'),
    );
    expect(
      (backupNowTile.trailing! as Icon).icon,
      app_icons.Icons.chevron_right,
    );
    final backupOptionsTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '备份选项'),
    );
    expect(
      (backupOptionsTile.trailing! as Icon).icon,
      app_icons.Icons.chevron_right,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, '备份选项'),
        matching: find.byIcon(app_icons.Icons.tune),
      ),
      findsOneWidget,
    );
    // 旧的两个开关搬进「备份内容」弹窗
    expect(find.text('备份包含 Cookie'), findsNothing);
    expect(find.text('备份包含 WebDAV 账号'), findsNothing);
    // “备份选项”行只保留标题，不再显示挤占空间的内容摘要小标题
    expect(find.text('未选择'), findsNothing);
    // 云端备份已并入 WebDAV 分组，不再单独显示小标题
    expect(find.text('云端备份'), findsNothing);
  });

  testWidgets('立即备份：先勾选备份内容，再交给系统保存对话框', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('立即备份'));
    await tester.pumpAndSettle();

    // 独立页面默认一项都不勾，“继续”不可用
    final optionsPage = find.byType(BackupOptionsPage);
    expect(optionsPage, findsOneWidget);
    expect(
      find.descendant(of: optionsPage, matching: find.text('备份')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: optionsPage, matching: find.byType(AppBarBackButton)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '继续'))
          .onPressed,
      isNull,
    );
    // 常规 2 + 账号信息 2 + 敏感信息 2；账号条目只在勾 Cookie 时随备份写入，
    // 所以没有单独的「账号列表」分项
    final l10n = AppLocalizationsZh();
    expect(
      find.descendant(of: optionsPage, matching: find.byType(M3ePickTile)),
      findsNWidgets(6),
    );
    // 保护备份与备份内容各一组
    expect(
      find.descendant(of: optionsPage, matching: find.byType(SegmentedList)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: optionsPage,
        matching: find.text(l10n.backupSectionQuick),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: optionsPage,
        matching: find.text(l10n.backupSectionCookies),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: optionsPage, matching: find.text('设置项')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '继续'));
    await tester.pumpAndSettle();

    expect(fake.saveCount, 1);
    expect(fake.lastSections, {BackupSection.settings});
    expect(fake.lastPassphrase, isNull);
    expect(savedCalls, hasLength(1));
    expect('${savedCalls.single.arguments['mime']}', 'application/json');
    expect('${savedCalls.single.arguments['fileName']}', endsWith('.json'));
    expect(find.textContaining('lancloud-backup-test.json'), findsOneWidget);
  });

  testWidgets('系统保存对话框取消时不提示', (tester) async {
    saveResult = null;
    await pumpPage(tester);

    await tester.tap(find.text('立即备份'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BackupOptionsPage),
        matching: find.text('收藏夹'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '继续'));
    await tester.pumpAndSettle();

    expect(savedCalls, hasLength(1));
    expect(find.textContaining('已保存到'), findsNothing);
  });

  testWidgets('生成备份期间显示加载弹窗，完成后再打开系统保存页', (tester) async {
    fake.exportGate = Completer<void>();
    await pumpPage(tester);

    await tester.tap(find.text('立即备份'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BackupOptionsPage),
        matching: find.text('设置项'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '继续'));
    await tester.pump();
    await tester.pump();

    expect(find.text('正在生成备份'), findsOneWidget);
    expect(savedCalls, isEmpty);

    fake.exportGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('正在生成备份'), findsNothing);
    expect(savedCalls, hasLength(1));
  });

  testWidgets('WebDAV 的备份选项会保存下来，只影响云端上传', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('备份选项'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '备份选项'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(BackupOptionsPage),
        matching: find.text('收藏夹'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(fake.webdav.backupSections, {BackupSection.favorites});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('webdav_backup_sections'), ['favorites']);
    expect(find.text('备份选项'), findsOneWidget);
  });

  testWidgets('敏感项勾选前验证身份，通过后本次运行不再重复验证', (tester) async {
    fakeAuth.result = CookieAuthResult.canceled;
    await pumpPage(tester);

    await tester.tap(find.text('备份选项'));
    await tester.pumpAndSettle();
    final optionsPage = find.byType(BackupOptionsPage);
    final l10n = AppLocalizationsZh();

    // 验证被取消：Cookie 保持未勾选
    await tester.tap(
      find.descendant(
        of: optionsPage,
        matching: find.text(l10n.backupSectionCookies),
      ),
    );
    await tester.pumpAndSettle();
    expect(fakeAuth.calls, 1);
    expect(
      tester
          .widget<M3ePickTile>(
            find.widgetWithText(M3ePickTile, l10n.backupSectionCookies),
          )
          .selected,
      isFalse,
    );

    // 验证通过后正常勾选
    fakeAuth.result = CookieAuthResult.ok;
    await tester.tap(
      find.descendant(
        of: optionsPage,
        matching: find.text(l10n.backupSectionCookies),
      ),
    );
    await tester.pumpAndSettle();
    expect(fakeAuth.calls, 2);
    expect(
      tester
          .widget<M3ePickTile>(
            find.widgetWithText(M3ePickTile, l10n.backupSectionCookies),
          )
          .selected,
      isTrue,
    );

    // 本次运行已验证过：再勾 WebDav 账号不再弹验证
    fakeAuth.result = CookieAuthResult.canceled;
    await tester.tap(
      find.descendant(of: optionsPage, matching: find.text(l10n.webdavAccount)),
    );
    await tester.pumpAndSettle();
    expect(fakeAuth.calls, 2);
    expect(
      tester
          .widget<M3ePickTile>(
            find.widgetWithText(M3ePickTile, l10n.webdavAccount),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets('导出敏感备份必须设置口令，并把口令交给加密层', (tester) async {
    await pumpPage(tester);
    final l10n = AppLocalizationsZh();

    await tester.tap(find.text('立即备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.backupSectionCookies));
    await tester.pumpAndSettle();
    expect(find.text('保护备份'), findsOneWidget);
    expect(
      tester
          .widget<M3eSwitchTile>(find.widgetWithText(M3eSwitchTile, '加密备份'))
          .enabled,
      isFalse,
    );
    await tester.enterText(
      find.byKey(const ValueKey('backup-options-passphrase')),
      'backup-secret',
    );
    await tester.tap(find.widgetWithText(TextButton, '继续'));
    await tester.pumpAndSettle();

    expect(fake.lastSections, contains(BackupSection.cookies));
    expect(fake.lastPassphrase, 'backup-secret');
    expect(savedCalls, hasLength(1));
  });

  testWidgets('恢复确认弹窗：无图标标题，含收藏夹时给保留选项且默认勾选', (tester) async {
    RestoreDecision? decision;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  decision = await showRestoreConfirmDialog(
                    context,
                    preview: BackupService.inspect(
                      '{"app":"lancloud","sections":["favorites"],'
                      '"tables":{"favorites":[{"ref":"existing"}]}}',
                    ),
                    showKeepFavorites: true,
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 标题和其它弹窗一样是无图标的文本
    expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).icon, isNull);
    expect(
      tester
          .widget<M3ePickTile>(find.widgetWithText(M3ePickTile, '保留原收藏夹内容'))
          .selected,
      isTrue,
    );

    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(decision?.keepFavorites, isTrue);
  });

  testWidgets('恢复确认弹窗：备份不含收藏夹时不显示保留选项', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showRestoreConfirmDialog(
                  context,
                  preview: BackupService.inspect(
                    '{"app":"lancloud","tables":{"favorites":[]}}',
                  ),
                  showKeepFavorites: false,
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

    expect(find.text('保留原收藏夹内容'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('确认恢复后真的执行恢复（回归：忙碌保护曾把内层调用吞掉）', (tester) async {
    bool? restored;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  restored = await confirmAndRestore(
                    context,
                    fake,
                    '{"app":"lancloud","tables":{"favorites":[]}}',
                  );
                },
                child: const Text('恢复'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    expect(restored, isTrue);
    expect(fake.restoreCount, 1);
    expect(fake.lastRestoredContent, contains('lancloud'));
  });

  testWidgets('取消恢复弹窗时不做任何恢复', (tester) async {
    bool? restored;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  restored = await confirmAndRestore(
                    context,
                    fake,
                    '{"app":"lancloud"}',
                  );
                },
                child: const Text('恢复'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(restored, isFalse);
    expect(fake.restoreCount, 0);
  });

  testWidgets('恢复敏感凭据前重新验证身份，取消时不写入账号', (tester) async {
    bool? restored;
    const content =
        '{"app":"lancloud","format":3,"sections":["cookies"],'
        '"activeUid":"1","accounts":[{"uid":"1","nickname":"A",'
        '"cookie":"ylogin=1; phpdisk_info=secret"}],"tables":{}}';
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  restored = await confirmAndRestore(context, fake, content);
                },
                child: const Text('恢复'),
              ),
            ),
          ),
        ),
      ),
    );

    fakeAuth.result = CookieAuthResult.canceled;
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(restored, isFalse);
    expect(fakeAuth.calls, 1);
    expect(fake.restoreCount, 0);

    fakeAuth.result = CookieAuthResult.ok;
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(restored, isTrue);
    expect(fakeAuth.calls, 2);
    expect(fake.restoreCount, 1);
  });

  testWidgets('仅恢复数据时明确跳过账号恢复', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => confirmAndRestore(
                  context,
                  fake,
                  '{"app":"lancloud","tables":{"favorites":[]}}',
                  restoreAccounts: false,
                ),
                child: const Text('恢复数据'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('恢复数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    expect(fake.restoreCount, 1);
    expect(fake.lastRestoreAccounts, isFalse);
  });

  testWidgets('未配置地址时 WebDAV 操作禁用', (tester) async {
    await pumpPage(tester);

    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '测试连接')).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '自动备份'))
          .onChanged,
      isNull,
    );
  });

  testWidgets('WebDAV 密码丢失时提示补录并禁用相关操作', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'webdav_url': 'https://dav.example.com/blue/',
      'webdav_user': 'user',
      'webdav_auto': true,
    });
    await pumpPage(tester);

    expect(find.text('WebDAV 账号配置不完整，请重新填写'), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '测试连接')).enabled,
      isFalse,
    );
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '上传备份')).enabled,
      isFalse,
    );
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '从云端恢复')).enabled,
      isFalse,
    );
    expect(fake.webdav.autoBackup, isFalse);
  });

  testWidgets('配置地址后 WebDAV 操作可用', (tester) async {
    await fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    await pumpPage(tester);

    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '测试连接')).enabled,
      isTrue,
    );
    expect(find.text('未选择备份内容'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '自动备份'))
          .onChanged,
      isNull,
    );

    await fake.webdav.setBackupSections({BackupSection.settings});
    await tester.pumpWidget(const SizedBox());
    await pumpPage(tester);
    expect(find.text('上次备份：尚未备份'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '自动备份'))
          .onChanged,
      isNotNull,
    );
  });

  testWidgets('重置 WebDAV 账号同时清空备份选项和自动备份', (tester) async {
    await fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    await fake.webdav.setBackupOptions(
      sections: {BackupSection.favorites},
      backupPassphrase: 'backup-secret',
    );
    await fake.webdav.setAutoBackup(true);
    await fake.webdav.markBackup(error: 'network failed');
    await pumpPage(tester);

    await tester.tap(find.text('WebDAV 账号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();

    expect(fake.webdav.url, isEmpty);
    expect(fake.webdav.backupPassphrase, isEmpty);
    expect(fake.webdav.backupSections, isEmpty);
    expect(fake.webdav.autoBackup, isFalse);
    expect(fake.webdav.lastBackupAt, 0);
    expect(fake.webdav.lastBackupError, isEmpty);
    expect(find.text('未配置 WebDAV'), findsOneWidget);
  });

  testWidgets('备份频率弹窗：MD3E 单选列表组（radio 指示），选中即写入', (tester) async {
    await fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    await fake.webdav.setBackupSections({BackupSection.settings});
    await fake.webdav.setAutoBackup(true);
    await pumpPage(tester);

    // 自动备份打开后才有「备份频率」这一行
    await tester.tap(find.text('备份频率'));
    await tester.pumpAndSettle();

    // 新的单选样式：默认 MD3 弹窗 + 连接式列表组，不是旧的 SimpleDialog
    expect(find.byType(SimpleDialog), findsNothing);
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.byType(DialogListGroup)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.byType(M3ePickTile)),
      findsNWidgets(2),
    );
    // 单选控件是 radio
    expect(
      find.descendant(of: dialog, matching: find.byType(Radio<bool>)),
      findsNWidgets(2),
    );

    // 选「每周」：弹窗关闭并写入，行副标题跟着变
    await tester.tap(find.text('每周'));
    await tester.pumpAndSettle();
    expect(fake.webdav.interval, 'weekly');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('每周'), findsOneWidget);
  });

  testWidgets('测试连接与上传备份调用服务', (tester) async {
    await fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    await fake.webdav.setBackupSections({BackupSection.favorites});
    await pumpPage(tester);

    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(fake.testCount, 1);
    expect(find.text('连接成功'), findsOneWidget);

    // 等第一个提示消失，避免第二条提示排队等待
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('上传备份'));
    await tester.pumpAndSettle();
    expect(fake.uploadCount, 1);
    expect(
      find.text('已上传 lancloud-backup-20261002-181500.json'),
      findsOneWidget,
    );
  });

  testWidgets('上传备份：生成阶段弹窗，随后显示上传进度线', (tester) async {
    await fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    await fake.webdav.setBackupSections({BackupSection.favorites});
    fake.uploadGenerationGate = Completer<void>();
    fake.uploadGate = Completer<void>();
    await pumpPage(tester);

    await tester.tap(find.text('上传备份'));
    await tester.pump();
    await tester.pump();
    expect(find.text('正在生成备份'), findsOneWidget);
    expect(find.byType(M3eLinearProgressIndicator), findsNothing);

    fake.uploadGenerationGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('正在生成备份'), findsNothing);
    expect(find.byType(M3eLinearProgressIndicator), findsOneWidget);

    fake.uploadGate!.complete();
    await tester.pumpAndSettle();
    expect(fake.uploadCount, 1);
    expect(find.byType(M3eLinearProgressIndicator), findsNothing);
    expect(
      find.text('已上传 lancloud-backup-20261002-181500.json'),
      findsOneWidget,
    );
  });

  testWidgets('云端恢复：选择版本弹窗带标题、分层时间与最新标记；进度线不残留', (tester) async {
    await fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    final now = DateTime.now();
    final newest = now.subtract(const Duration(minutes: 10));
    final older = now.subtract(const Duration(days: 3));
    fake.remoteEntries = [
      WebdavEntry(
        name: BackupService.latestName,
        href: '',
        size: 2048,
        modified: newest,
      ),
      WebdavEntry(
        name: 'lancloud-backup-20261010-120000.json',
        href: '',
        size: 0,
        modified: older,
      ),
    ];
    fake.remoteGate = Completer<void>();
    await pumpPage(tester);

    await tester.tap(find.text('从云端恢复'));
    await tester.pump();
    // 列表还在拉取：顶栏进度线显示（粗细与 WebView 进度条一致，4dp）
    expect(find.byType(M3eLinearProgressIndicator), findsOneWidget);
    expect(kBackupProgressBar.preferredSize.height, 4);

    fake.remoteGate!.complete();
    await tester.pumpAndSettle();

    // 弹窗打开时进度线已经收起
    expect(find.byType(M3eLinearProgressIndicator), findsNothing);
    expect(find.text('选择恢复版本'), findsOneWidget);
    // 最新一条（列表第一行）带「· 最新版本」；时间用分层相对格式
    final l10n = AppLocalizationsZh();
    expect(
      find.text('${formatRelativeTime(l10n, newest)} · 2.0 KB · 最新版本'),
      findsOneWidget,
    );
    // 其它条目没有「最新版本」标记，时间同样走分层格式（如「10月14日」）
    final olderTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'lancloud-backup-20261010-120000.json'),
    );
    final olderSubtitle = (olderTile.subtitle! as Text).data!;
    expect(olderSubtitle.contains('最新版本'), isFalse);
    expect(olderSubtitle, matches(RegExp(r'^\d{1,2}月\d{1,2}日$')));

    // 点空白处关掉弹窗
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('选择恢复版本'), findsNothing);
  });

  testWidgets('「上次备份」日期：今天 / 昨天 / yyyy-MM-dd', (tester) async {
    final now = DateTime.now();
    await fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    // 页面 initState 会重新 load 存储，所以把状态放进 mock 的 SharedPreferences
    Future<void> pumpWith(int millis) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'webdav_backup_sections': ['settings'],
        'webdav_last_backup_at': millis,
      });
      // 先卸载旧页面：否则同类型 widget 复用 State，不会重新 load 存储
      await tester.pumpWidget(const SizedBox());
      await pumpPage(tester);
    }

    await pumpWith(now.millisecondsSinceEpoch);
    expect(find.text('上次备份：今天'), findsOneWidget);

    await pumpWith(
      now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
    );
    expect(find.text('上次备份：昨天'), findsOneWidget);

    final old = now.subtract(const Duration(days: 3)).millisecondsSinceEpoch;
    await pumpWith(old);
    expect(find.text('上次备份：${formatDateShort(old)}'), findsOneWidget);
  });

  testWidgets('敏感云端备份上传前不再重复验证身份', (tester) async {
    await fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    await fake.webdav.setBackupOptions(
      sections: {BackupSection.cookies},
      backupPassphrase: 'backup-secret',
    );
    fakeAuth.result = CookieAuthResult.canceled;
    await pumpPage(tester);

    // 敏感分项在“备份选项”阶段已授权；手动上传与自动备份一致，不再重复验证。
    await tester.tap(find.text('上传备份'));
    await tester.pumpAndSettle();
    expect(fakeAuth.calls, 0);
    expect(fake.uploadCount, 1);
    expect(fake.lastSections, contains(BackupSection.cookies));
  });
}
