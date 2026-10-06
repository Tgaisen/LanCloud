import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/account_store.dart';

/// 内存版安全存储，避免测试环境去调插件。
class _MemoryStorage extends FlutterSecureStorage {
  const _MemoryStorage(this.data);

  final Map<String, String> data;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
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
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
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
}
