import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/backup/backup_sections.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/webdav_client.dart';
import 'package:lancloud/core/backup/webdav_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 测试环境没有安全存储插件，密码改放内存。
class _MemoryWebdavStore extends WebdavStore {
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

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('备份分项标识可以往返解析，敏感项标记正确', () {
    expect(BackupSection.fromIds(['settings', 'cookies', 'unknown']), {
      BackupSection.settings,
      BackupSection.cookies,
    });
    expect(BackupSection.cookies.sensitive, isTrue);
    expect(BackupSection.webdavAccount.sensitive, isTrue);
    expect(BackupSection.settings.sensitive, isFalse);
    expect(BackupSection.favorites.sensitive, isFalse);
    expect(BackupSection.quick.sensitive, isFalse);
  });

  test('containsFavorites：只看备份里的收藏夹表', () {
    expect(
      BackupService.containsFavorites(
        '{"app":"lancloud","tables":{"favorites":[{"ref":"a"}]}}',
      ),
      isTrue,
    );
    expect(
      BackupService.containsFavorites('{"app":"lancloud","tables":{}}'),
      isFalse,
    );
    expect(
      BackupService.containsFavorites(
        '{"app":"lancloud","tables":{"favorites":[]}}',
      ),
      isFalse,
    );
    expect(BackupService.containsFavorites('不是 JSON'), isFalse);
  });

  test('备份预检：返回内容摘要、创建时间与首选 Cookie 账号', () {
    const content =
        '{"app":"lancloud","format":2,"createdAt":1700000000000,'
        '"sections":["settings","cookies"],"activeUid":"b",'
        '"accounts":['
        '{"uid":"a","nickname":"账号 A","cookie":"ylogin=a; phpdisk_info=x"},'
        '{"uid":"b","nickname":"账号 B","cookie":"ylogin=b; phpdisk_info=y"}'
        '],"tables":{}}';

    final preview = BackupService.inspect(content);
    expect(preview.format, 2);
    expect(preview.sections, {BackupSection.settings, BackupSection.cookies});
    expect(preview.accounts, hasLength(2));
    expect(preview.hasCookies, isTrue);
    expect(preview.suggestedAccount?.uid, 'b');
    expect(preview.suggestedAccount?.displayName, '账号 B');
    expect(preview.createdAt?.millisecondsSinceEpoch, 1700000000000);
  });

  test('WebDAV 上传：没选备份内容时提示先选', () async {
    SharedPreferences.setMockInitialValues({});
    final webdav = _MemoryWebdavStore();
    await webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'u',
      password: 'p',
      path: '/',
    );
    final service = BackupService(AppController(), webdav: webdav);
    await expectLater(
      service.uploadNow(),
      throwsA(
        isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('备份内容'),
        ),
      ),
    );
  });

  test('WebDAV 备份内容会持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final store = _MemoryWebdavStore();
    await store.load();
    expect(store.backupSections, isEmpty);

    await store.setBackupSections({
      BackupSection.favorites,
      BackupSection.cookies,
    });
    final reloaded = _MemoryWebdavStore();
    await reloaded.load();
    expect(reloaded.backupSections, {
      BackupSection.favorites,
      BackupSection.cookies,
    });

    await reloaded.addBackupSection(BackupSection.webdavAccount);
    expect(reloaded.backupSections, contains(BackupSection.webdavAccount));
  });

  test('备份 WebDAV 账号时一并带上「备份内容」勾选项与「自动备份」开关', () async {
    SharedPreferences.setMockInitialValues({});
    final store = _MemoryWebdavStore()
      ..url = 'https://dav.example.com/blue/'
      ..username = 'u'
      ..password = 'p'
      ..path = '/LanCloud'
      ..autoBackup = true
      ..backupSections = {BackupSection.favorites, BackupSection.webdavAccount};
    final service = BackupService(AppController(), webdav: store);

    final payload = jsonDecode(
      await service.encode(sections: {BackupSection.webdavAccount}),
    ) as Map;
    final webdav = payload['webdav'] as Map;
    expect(webdav['path'], '/LanCloud');
    expect(webdav['autoBackup'], isTrue);
    expect(
      webdav['backupSections'],
      containsAll(['favorites', 'webdavAccount']),
    );
  });

  test('恢复 WebDAV 账号时一并恢复「备份内容」与「自动备份」开关', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppController();
    await app.settings.load();
    final store = _MemoryWebdavStore();
    await store.load();
    final service = BackupService(app, webdav: store);

    const content =
        '{"app":"lancloud","format":2,"sections":["webdavAccount"],'
        '"tables":{},'
        '"webdav":{"url":"https://dav.example.com/blue/","username":"u",'
        '"password":"p","path":"/LanCloud","autoBackup":true,'
        '"backupSections":["favorites","cookies"]}}';
    await service.restoreFromString(content);

    expect(store.url, 'https://dav.example.com/blue/');
    expect(store.path, '/LanCloud');
    expect(store.autoBackup, isTrue);
    expect(
      store.backupSections,
      containsAll([
        BackupSection.favorites,
        BackupSection.cookies,
        BackupSection.webdavAccount,
      ]),
    );
  });

  test('不勾 Cookie 不写 activeUid / accounts，勾 Cookie 才带上账号条目', () async {
    SharedPreferences.setMockInitialValues({});
    final service = BackupService(
      AppController(),
      webdav: _MemoryWebdavStore(),
    );

    final plain = jsonDecode(
      await service.encode(sections: {BackupSection.settings}),
    ) as Map;
    expect(plain.containsKey('accounts'), isFalse);
    expect(plain.containsKey('activeUid'), isFalse);

    // 不勾 Cookie 时，即使备份了快速访问 / 最近使用也不写账号条目
    final withoutCookies = jsonDecode(
      await service.encode(
        sections: {BackupSection.quick, BackupSection.recents},
      ),
    ) as Map;
    expect(withoutCookies.containsKey('accounts'), isFalse);
    expect(withoutCookies.containsKey('activeUid'), isFalse);

    // Cookie 存在账号条目里：勾 Cookie 时才写账号条目（activeUid + accounts）
    final cookies = jsonDecode(
      await service.encode(sections: {BackupSection.cookies}),
    ) as Map;
    expect(cookies['accounts'], isA<List>());
    expect(cookies['includeCookies'], isTrue);
    expect(cookies.containsKey('activeUid'), isTrue);
  });

  test('恢复：设置项与收藏夹真的写回本机（回归：嵌套忙碌保护曾把恢复吞掉）', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppController();
    await app.settings.load();
    final service = BackupService(app, webdav: _MemoryWebdavStore());

    // 用当前配置做底，改一个开关当作"备份里的旧设置"
    final settings = Map<String, Object?>.from(app.settings.toJson());
    final restoredTransitions = !app.settings.transitionAnimations;
    settings['transition_animations'] = restoredTransitions;
    final content = jsonEncode({
      'app': 'lancloud',
      'format': 2,
      'sections': ['settings', 'favorites'],
      'settings': settings,
      'tables': {
        'favorites': [
          {
            'kind': 'shareFile',
            'name': '恢复进来的收藏',
            'ref': 'restored-ref',
            'created_at': 1,
          },
        ],
      },
    });

    await service.restoreFromString(content);

    expect(app.settings.transitionAnimations, restoredTransitions);
    final favorites = await app.db.favorites();
    expect(favorites.map((f) => f.ref), contains('restored-ref'));
  });
}
