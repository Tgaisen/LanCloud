import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/backup/backup_sections.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/webdav_store.dart';
import 'package:lancloud/core/cookie_auth.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/app_localizations_zh.dart';
import 'package:lancloud/ui/backup_page.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBackupService extends BackupService {
  _FakeBackupService(super.app);

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
  Set<BackupSection>? lastSections;

  @override
  Future<File> exportFile({
    Set<BackupSection> sections = const {},
    DateTime? now,
  }) async {
    saveCount += 1;
    lastSections = sections;
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
  }) async {
    uploadCount += 1;
    lastSections = sections ?? _store.backupSections;
    return 'lancloud-backup-20261002-181500.json';
  }

  @override
  Future<void> restoreFromString(
    String content, {
    bool mergeFavorites = false,
  }) async {
    restoreCount += 1;
    lastRestoredContent = content;
    lastMergeFavorites = mergeFavorites;
  }
}

/// 测试环境没有安全存储插件，密码改放内存。
class _FakeWebdavStore extends WebdavStore {
  String _password = '';

  @override
  Future<String> readPassword() async => _password;

  @override
  Future<void> writePassword(String value) async {
    _password = value;
  }
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
    fake = _FakeBackupService(AppController());
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
    BackupService.instance = null;
    CookieAuth.instance = CookieAuth();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    BackupService.instance = fake;
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: fake.app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
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
    expect(find.text('备份内容'), findsOneWidget);
    expect(find.text('自动备份'), findsOneWidget);
    expect(find.textContaining('尚未备份'), findsOneWidget);
    // 旧的两个开关搬进「备份内容」弹窗
    expect(find.text('备份包含 Cookie'), findsNothing);
    expect(find.text('备份包含 WebDAV 账号'), findsNothing);
    // 还没选备份内容时显示「未选择」
    expect(find.text('未选择'), findsOneWidget);
    // 云端备份已并入 WebDAV 分组，不再单独显示小标题
    expect(find.text('云端备份'), findsNothing);
  });

  testWidgets('立即备份：先勾选备份内容，再交给系统保存对话框', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('立即备份'));
    await tester.pumpAndSettle();

    // 弹窗默认一项都不勾，确定按钮不可用
    final dialog = find.byType(AlertDialog);
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: dialog, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
    );
    // 常规 2 + 账号信息 2 + 敏感信息 2；账号条目只在勾 Cookie 时随备份写入，
    // 所以没有单独的「账号列表」分项
    final l10n = AppLocalizationsZh();
    expect(
      find.descendant(of: dialog, matching: find.byType(CheckboxListTile)),
      findsNWidgets(6),
    );
    expect(
      find.descendant(of: dialog, matching: find.text(l10n.backupSectionQuick)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(l10n.backupSectionCookies),
      ),
      findsOneWidget,
    );

    await tester.tap(find.descendant(of: dialog, matching: find.text('设置项')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: dialog, matching: find.text('确定')));
    await tester.pumpAndSettle();

    expect(fake.saveCount, 1);
    expect(fake.lastSections, {BackupSection.settings});
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
      find.descendant(of: find.byType(AlertDialog), matching: find.text('收藏夹')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('确定')),
    );
    await tester.pumpAndSettle();

    expect(savedCalls, hasLength(1));
    expect(find.textContaining('已保存到'), findsNothing);
  });

  testWidgets('WebDAV 的备份内容会保存下来，只影响云端上传', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('备份内容'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('收藏夹')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('确定')),
    );
    await tester.pumpAndSettle();

    expect(fake.webdav.backupSections, {BackupSection.favorites});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('webdav_backup_sections'), ['favorites']);
    // 页面上显示已选内容的摘要
    expect(find.text('收藏夹'), findsOneWidget);
  });

  testWidgets('敏感项勾选前验证身份，通过后本次运行不再重复验证', (tester) async {
    fakeAuth.result = CookieAuthResult.canceled;
    await pumpPage(tester);

    await tester.tap(find.text('备份内容'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final l10n = AppLocalizationsZh();

    // 验证被取消：Cookie 保持未勾选
    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.text(l10n.backupSectionCookies),
      ),
    );
    await tester.pumpAndSettle();
    expect(fakeAuth.calls, 1);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, l10n.backupSectionCookies),
          )
          .value,
      isFalse,
    );

    // 验证通过后正常勾选
    fakeAuth.result = CookieAuthResult.ok;
    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.text(l10n.backupSectionCookies),
      ),
    );
    await tester.pumpAndSettle();
    expect(fakeAuth.calls, 2);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, l10n.backupSectionCookies),
          )
          .value,
      isTrue,
    );

    // 本次运行已验证过：再勾 WebDav 账号不再弹验证
    fakeAuth.result = CookieAuthResult.canceled;
    await tester.tap(
      find.descendant(of: dialog, matching: find.text(l10n.webdavAccount)),
    );
    await tester.pumpAndSettle();
    expect(fakeAuth.calls, 2);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, l10n.webdavAccount),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('恢复确认弹窗：无图标标题，含收藏夹时给保留选项且默认勾选', (tester) async {
    RestoreDecision? decision;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  decision = await showRestoreConfirmDialog(
                    context,
                    label: 'lancloud-backup.json',
                    hasFavorites: true,
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
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, '保留原收藏夹内容'),
          )
          .value,
      isTrue,
    );

    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(decision?.keepFavorites, isTrue);
  });

  testWidgets('恢复确认弹窗：备份不含收藏夹时不显示保留选项', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showRestoreConfirmDialog(
                  context,
                  label: 'lancloud-backup.json',
                  hasFavorites: false,
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
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
                    'lancloud-backup.json',
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
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
                    'lancloud-backup.json',
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

  testWidgets('配置地址后 WebDAV 操作可用', (tester) async {
    await fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
    );
    await pumpPage(tester);

    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '测试连接')).enabled,
      isTrue,
    );
  });

  testWidgets('测试连接与上传备份调用服务', (tester) async {
    await fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
    );
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

  testWidgets('备份内容含敏感项时，上传前先验证身份', (tester) async {
    await fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
    );
    await fake.webdav.setBackupSections({BackupSection.cookies});
    fakeAuth.result = CookieAuthResult.canceled;
    await pumpPage(tester);

    // 验证被取消：不上传
    await tester.tap(find.text('上传备份'));
    await tester.pumpAndSettle();
    expect(fakeAuth.calls, 1);
    expect(fake.uploadCount, 0);

    // 验证通过后正常上传，并且只验证一次
    fakeAuth.result = CookieAuthResult.ok;
    await tester.tap(find.text('上传备份'));
    await tester.pumpAndSettle();
    expect(fakeAuth.calls, 2);
    expect(fake.uploadCount, 1);
    expect(fake.lastSections, contains(BackupSection.cookies));
  });
}
