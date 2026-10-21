import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/data/secure_storage.dart';

/// 内存版安全存储，避免测试环境去调插件。
class _MemoryStorage extends FlutterSecureStorage {
  const _MemoryStorage(this.data);

  final Map<String, String> data;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data.remove(key);
  }
}

Future<AccountStore> storeWith(List<Account> accounts, {String? active}) async {
  final store = AccountStore(
    _MemoryStorage({
      'lancloud_accounts':
          '[${accounts.map((a) => '{"uid":"${a.uid}","cookie":"${a.cookie}","nickname":"${a.nickname}"}').join(',')}]',
      'lancloud_active_uid': ?active,
    }),
  );
  await store.load();
  return store;
}

void main() {
  test('安全存储保留 v9 → v10 迁移路径', () {
    expect(
      lanCloudSecureStorage.wOptions.toMap()['useBackwardCompatibility'],
      'true',
    );
    expect(lanCloudSecureStorage.aOptions.toMap()['migrateWithBackup'], 'true');
  });

  test('恢复账号：本机已有 Cookie 不被旧备份覆盖', () async {
    final store = await storeWith([
      Account(uid: '556911', cookie: '新会话', nickname: 'excited233'),
    ], active: '556911');

    await store.importAccounts([
      {'uid': '556911', 'nickname': 'excited233', 'cookie': '旧备份的会话'},
    ]);

    expect(store.byUid('556911')!.cookie, '新会话');
  });

  test('恢复账号：本机没有 Cookie 时补上，本地没有的账号才会新增', () async {
    final store = await storeWith([Account(uid: '556911', cookie: '')]);

    await store.importAccounts([
      {'uid': '556911', 'nickname': '账号一', 'cookie': 'c1'},
      {'uid': '523441', 'nickname': '账号二', 'cookie': 'c2'},
      {'uid': '999999', 'nickname': '没有凭据'},
    ]);

    expect(store.byUid('556911')!.cookie, 'c1');
    expect(store.byUid('523441')!.cookie, 'c2');
    // 备份里没带 Cookie 的账号恢复不进来（没有凭据没法登录）
    expect(store.byUid('999999'), isNull);
  });

  test('恢复账号：activeUid 只在本机存在该账号时才切换', () async {
    final store = await storeWith([
      Account(uid: '556911', cookie: 'c1'),
      Account(uid: '523441', cookie: 'c2'),
    ], active: '556911');

    await store.importAccounts([
      {'uid': '523441', 'nickname': ''},
    ], activeSnapshot: '523441');
    expect(store.activeUid, '523441');

    // 备份里的 activeUid 本机没有 → 保持当前账号
    await store.importAccounts([
      {'uid': '523441', 'nickname': ''},
    ], activeSnapshot: '999999');
    expect(store.activeUid, '523441');
  });

  test('用户等级：落盘、备份往返，空值不覆盖已有等级', () async {
    final store = await storeWith([
      Account(uid: '556911', cookie: 'c1'),
    ], active: '556911');

    // 截取到等级后落盘
    await store.setLevel('556911', '白');
    expect(store.byUid('556911')!.level, '白');
    // 没取到（空串）不覆盖
    await store.setLevel('556911', '');
    expect(store.byUid('556911')!.level, '白');

    // 备份导出带等级，恢复时合并进本机账号
    expect(store.exportAccounts().first['level'], '白');
    await store.importAccounts([
      {'uid': '556911', 'nickname': '土豆', 'level': '普'},
      {'uid': '999999', 'cookie': 'c9', 'level': '白'},
    ]);
    expect(store.byUid('556911')!.level, '普');
    expect(store.byUid('999999')!.level, '白');
  });
}
