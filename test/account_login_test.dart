import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/account_login.dart';
import 'package:lancloud/core/account_state.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/drive_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

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
      values.remove(key);
    } else {
      values[key] = value;
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
    values.remove(key);
  }
}

class _FakeClient extends LanzouClient {
  _FakeClient(String uid, {this.valid = true}) : super(uid: uid);

  final bool valid;

  @override
  Future<bool> verify() async => valid;

  @override
  Future<({String? nickname, String level})> fetchAccountInfo() async =>
      (nickname: '测试账号', level: '会员');
}

AccountLogin _login({
  required AccountState state,
  required LanzouClientRegistry clients,
}) => AccountLogin(
  accountState: state,
  clients: clients,
  driveCache: DriveCache(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Cookie 登录保存账号、缓存客户端并通知账号状态', () async {
    final state = AccountState(store: AccountStore(_MemoryStorage()));
    final clients = LanzouClientRegistry(factory: (uid) => _FakeClient(uid));
    final login = _login(state: state, clients: clients);
    var changes = 0;
    state.addListener(() => changes += 1);

    await login.addAccountFromCookie('foo=1; ylogin=556911; bar=2');

    expect(state.store.activeUid, '556911');
    expect(state.store.active?.nickname, '测试账号');
    expect(state.store.active?.level, '会员');
    expect(clients.clientFor('556911'), isA<_FakeClient>());
    expect(changes, 1);
  });

  test('Cookie 格式错误或验证失败时不改变账号状态', () async {
    final state = AccountState(store: AccountStore(_MemoryStorage()));
    var changes = 0;
    state.addListener(() => changes += 1);
    final invalidFormat = _login(
      state: state,
      clients: LanzouClientRegistry(factory: (uid) => _FakeClient(uid)),
    );
    await expectLater(
      invalidFormat.addAccountFromCookie('foo=bar'),
      throwsA(isA<CookieFormatException>()),
    );

    final invalidCookie = _login(
      state: state,
      clients: LanzouClientRegistry(
        factory: (uid) => _FakeClient(uid, valid: false),
      ),
    );
    await expectLater(
      invalidCookie.addAccountFromCookie('ylogin=556911'),
      throwsA(isA<CookieInvalidException>()),
    );
    expect(state.store.activeUid, isNull);
    expect(changes, 0);
  });
}
