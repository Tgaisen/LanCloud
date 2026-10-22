import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/backup/backup_sections.dart';
import 'package:lancloud/core/backup/webdav_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryWebdavStore extends WebdavStore {
  Map<String, String>? secureAccount;
  String legacyPassword = '';
  bool failSecureWrite = false;

  @override
  Future<Map<String, String>?> readSecureAccount() async =>
      secureAccount == null ? null : Map.of(secureAccount!);

  @override
  Future<void> writeSecureAccount(Map<String, String> value) async {
    if (failSecureWrite) throw StateError('secure storage unavailable');
    secureAccount = Map.of(value);
  }

  @override
  Future<void> deleteSecureAccount() async => secureAccount = null;

  @override
  Future<String> readLegacyPassword() async => legacyPassword;

  @override
  Future<void> deleteLegacyPassword() async => legacyPassword = '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('路径规范化：补前导斜杠、去多余斜杠，单独的 / 表示根', () {
    expect(WebdavStore.normalizePath(''), '');
    expect(WebdavStore.normalizePath('LanCloud'), '/LanCloud');
    expect(WebdavStore.normalizePath('/LanCloud/'), '/LanCloud');
    expect(WebdavStore.normalizePath('  //LanCloud//  '), '/LanCloud');
    expect(WebdavStore.normalizePath('/'), '/');
    expect(WebdavStore.normalizePath(' /a/b '), '/a/b');
  });

  test('备份目录 = 地址 + 路径（路径为 / 时直接用地址）', () {
    final store = WebdavStore()
      ..url = 'https://dav.example.com/dav/'
      ..path = '/LanCloud';
    expect(store.backupUrl, 'https://dav.example.com/dav/LanCloud/');

    store.url = 'https://dav.example.com/dav';
    expect(store.backupUrl, 'https://dav.example.com/dav/LanCloud/');

    store.path = '/';
    expect(store.backupUrl, 'https://dav.example.com/dav');

    store.url = '';
    expect(store.backupUrl, '');
  });

  test('默认路径：新配置 /LanCloud；旧配置（只有地址）保持原目录 /', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final fresh = WebdavStore();
    await fresh.load();
    expect(fresh.path, '/LanCloud');

    SharedPreferences.setMockInitialValues(<String, Object>{
      'webdav_url': 'https://dav.example.com/dav/',
    });
    final upgraded = WebdavStore();
    await upgraded.load();
    expect(upgraded.path, '/');
    expect(upgraded.backupUrl, 'https://dav.example.com/dav/');
  });

  test('保存与加载：路径会持久化并规范化', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _MemoryWebdavStore();
    await store.saveServer(
      url: 'https://dav.example.com/dav/',
      username: 'u',
      password: 'p',
      path: 'LanCloud/',
      backupPassphrase: 'backup-secret',
    );
    expect(store.path, '/LanCloud');
    expect(store.backupPassphrase, 'backup-secret');

    final reloaded = _MemoryWebdavStore()
      ..secureAccount = Map.of(store.secureAccount!);
    await reloaded.load();
    expect(reloaded.path, '/LanCloud');
    expect(reloaded.backupUrl, 'https://dav.example.com/dav/LanCloud/');
    expect(reloaded.configured, isTrue);
    expect(reloaded.backupPassphrase, 'backup-secret');
  });

  test('密码丢失：禁用 WebDAV 操作并关闭自动备份', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'webdav_url': 'https://dav.example.com/dav/',
      'webdav_user': 'u',
      'webdav_auto': true,
    });
    final store = _MemoryWebdavStore();
    await store.load();

    expect(store.needsConfiguration, isTrue);
    expect(store.configured, isFalse);
    expect(store.autoBackup, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('webdav_auto'), isFalse);
    expect(prefs.getString('webdav_url'), isNull);
    expect(prefs.getString('webdav_user'), isNull);
    expect(store.secureAccount?['url'], 'https://dav.example.com/dav/');
  });

  test('地址、用户名、密码、路径任一缺失时都不可用', () {
    WebdavStore complete() => WebdavStore()
      ..url = 'https://dav.example.com/dav/'
      ..username = 'u'
      ..password = 'p'
      ..path = '/LanCloud';

    expect(complete().configured, isTrue);
    expect((complete()..url = '').configured, isFalse);
    expect((complete()..username = '').configured, isFalse);
    expect((complete()..password = '').configured, isFalse);
    expect((complete()..path = '').configured, isFalse);
  });

  test('只有普通备份项时不需要口令也能自动备份', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _MemoryWebdavStore();
    await store.saveServer(
      url: 'https://dav.example.com/dav/',
      username: 'u',
      password: 'p',
      path: '/LanCloud',
    );
    await store.setBackupSections({BackupSection.favorites});
    await store.setAutoBackup(true);

    expect(store.hasBackupPassphrase, isFalse);
    expect(store.autoBackup, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('webdav_auto'), isTrue);
  });

  test('未选择备份内容时不能开启自动备份', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _MemoryWebdavStore();
    await store.saveServer(
      url: 'https://dav.example.com/dav/',
      username: 'u',
      password: 'p',
      path: '/LanCloud',
    );
    await store.setAutoBackup(true);

    expect(store.configured, isTrue);
    expect(store.backupSections, isEmpty);
    expect(store.autoBackup, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('webdav_auto'), isFalse);
  });

  test('重置账号会同时清空备份选项、自动备份和上次执行状态', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _MemoryWebdavStore();
    await store.saveServer(
      url: 'https://dav.example.com/dav/',
      username: 'u',
      password: 'p',
      path: '/Backups',
      backupPassphrase: 'backup-secret',
    );
    await store.setBackupSections({BackupSection.favorites});
    await store.setAutoBackup(true);
    await store.setInterval('weekly');
    await store.markBackup(error: 'network failed');

    await store.reset();

    expect(store.url, isEmpty);
    expect(store.username, isEmpty);
    expect(store.password, isEmpty);
    expect(store.backupPassphrase, isEmpty);
    expect(store.path, WebdavStore.defaultPath);
    expect(store.backupSections, isEmpty);
    expect(store.autoBackup, isFalse);
    expect(store.interval, 'daily');
    expect(store.lastBackupAt, 0);
    expect(store.lastBackupError, isEmpty);
    expect(store.secureAccount, isNull);
  });

  test('敏感备份选项没有口令时拒绝保存', () async {
    final store = _MemoryWebdavStore();
    await expectLater(
      store.setBackupOptions(
        sections: {BackupSection.cookies},
        backupPassphrase: '',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('旧版分散字段完整迁移到安全存储后才删除原数据', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'webdav_url': 'https://dav.example.com/dav/',
      'webdav_user': 'u',
      'webdav_path': '/Backups',
    });
    final store = _MemoryWebdavStore()..legacyPassword = 'p';
    await store.load();

    expect(store.configured, isTrue);
    expect(store.secureAccount, {
      'url': 'https://dav.example.com/dav/',
      'username': 'u',
      'password': 'p',
      'backupPassphrase': '',
      'path': '/Backups',
    });
    expect(store.legacyPassword, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('webdav_url'), isNull);
    expect(prefs.getString('webdav_user'), isNull);
    expect(prefs.getString('webdav_path'), isNull);
  });

  test('迁移写入失败时保留旧数据并允许下次重试', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'webdav_url': 'https://dav.example.com/dav/',
      'webdav_user': 'u',
      'webdav_path': '/Backups',
    });
    final store = _MemoryWebdavStore()
      ..legacyPassword = 'p'
      ..failSecureWrite = true;
    await store.load();

    expect(store.configured, isTrue);
    expect(store.secureAccount, isNull);
    expect(store.legacyPassword, 'p');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('webdav_url'), 'https://dav.example.com/dav/');
    expect(prefs.getString('webdav_user'), 'u');
    expect(prefs.getString('webdav_path'), '/Backups');
  });
}
