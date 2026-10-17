import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/backup/webdav_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final store = WebdavStore();
    await store.saveServer(
      url: 'https://dav.example.com/dav/',
      username: 'u',
      password: 'p',
      path: 'LanCloud/',
    );
    expect(store.path, '/LanCloud');

    final reloaded = WebdavStore();
    await reloaded.load();
    expect(reloaded.path, '/LanCloud');
    expect(reloaded.backupUrl, 'https://dav.example.com/dav/LanCloud/');
  });
}
