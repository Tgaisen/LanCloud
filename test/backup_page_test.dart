import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/webdav_store.dart';
import 'package:lancloud/core/cookie_auth.dart';
import 'package:lancloud/l10n/app_localizations.dart';
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

  @override
  Future<File> saveLocal({bool includeCookies = false, DateTime? now}) async {
    saveCount += 1;
    return File('${Directory.systemTemp.path}/lancloud-backup-test.json');
  }

  @override
  Future<void> testConnection() async {
    testCount += 1;
  }

  @override
  Future<String> uploadNow({bool? includeCookies, DateTime? now}) async {
    uploadCount += 1;
    return 'lancloud-backup-20261002-181500.json';
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

  final CookieAuthResult result;

  @override
  Future<CookieAuthResult> verify(
    String reason, {
    Iterable<AuthMessages> messages = const <AuthMessages>[],
  }) async =>
      result;
}

void main() {
  late _FakeBackupService fake;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fake = _FakeBackupService(AppController());
    // 备份包含 Cookie 需要生物验证，测试里直接放行
    CookieAuth.instance = _FakeCookieAuth(CookieAuthResult.ok);
  });

  tearDown(() {
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
    expect(find.text('备份包含 Cookie'), findsOneWidget);
    expect(find.text('WebDAV 账号'), findsOneWidget);
    expect(find.text('自动备份'), findsOneWidget);
    expect(find.textContaining('尚未备份'), findsOneWidget);
    // 云端备份已并入 WebDAV 分组，不再单独显示小标题
    expect(find.text('云端备份'), findsNothing);
  });

  testWidgets('立即备份写入本地文件并提示路径', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('立即备份'));
    await tester.pumpAndSettle();

    expect(fake.saveCount, 1);
    expect(
      find.textContaining('lancloud-backup-test.json'),
      findsOneWidget,
    );
  });

  testWidgets('备份包含 Cookie 开关会持久化到配置', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('备份包含 Cookie'));
    await tester.pumpAndSettle();

    expect(fake.webdav.includeCookies, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('webdav_include_cookies'), isTrue);
  });

  testWidgets('未配置地址时 WebDAV 操作禁用', (tester) async {
    await pumpPage(tester);

    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '测试连接')).enabled,
      isFalse,
    );
    expect(
      tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '自动备份')).onChanged,
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
    expect(find.text('已上传 lancloud-backup-20261002-181500.json'), findsOneWidget);
  });
}
