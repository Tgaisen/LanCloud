import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/account_session.dart';
import 'package:lancloud/core/account_state.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:lancloud/core/drive_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('账号切换与移除统一通知账号状态', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final accountState = AccountState(
      store: AccountStore()
        ..accounts = [
          Account(uid: 'a', cookie: 'cookie-a'),
          Account(uid: 'b', cookie: 'cookie-b'),
        ]
        ..activeUid = 'a',
    );
    addTearDown(accountState.dispose);
    final session = AccountSession(
      accountState: accountState,
      clients: LanzouClientRegistry(),
      driveCache: DriveCache(),
      db: AppDb.instance,
    );
    var notifications = 0;
    accountState.addListener(() => notifications += 1);

    await session.switchAccount('b');
    expect(accountState.store.activeUid, 'b');
    expect(notifications, 1);

    await session.removeAccount('a');
    expect(accountState.store.accounts.map((account) => account.uid), ['b']);
    expect(accountState.store.activeUid, 'b');
    expect(notifications, 2);
  });

  test('账号会话 provider 必须由应用入口覆盖', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(accountSessionProvider),
      throwsA(isA<ProviderException>()),
    );
  });
}
