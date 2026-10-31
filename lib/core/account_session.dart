import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_state.dart';
import 'api/lanzou_client_registry.dart';
import 'data/app_db.dart';
import 'drive_cache.dart';

/// 账号切换与移除的唯一业务入口。
class AccountSession {
  const AccountSession({
    required this.accountState,
    required this.clients,
    required this.driveCache,
    required this.db,
  });

  final AccountState accountState;
  final LanzouClientRegistry clients;
  final DriveCache driveCache;
  final AppDb db;

  Future<void> switchAccount(String uid) async {
    await accountState.store.setActive(uid);
    await driveCache.bindAccount(uid);
    accountState.notifyAccountChanged();
  }

  Future<void> removeAccount(String uid, {bool clearData = false}) async {
    if (clearData) {
      try {
        await db.clearUsageData(uid);
      } catch (_) {
        // 本地库异常不能挡住退出登录。
      }
    }
    await accountState.store.remove(uid);
    clients.remove(uid);
    await driveCache.bindAccount(accountState.store.activeUid);
    accountState.notifyAccountChanged();
  }
}

/// 应用级账号会话服务；由 AppEnvironment 构造并通过 provider 覆盖。
final accountSessionProvider = Provider<AccountSession>((ref) {
  throw StateError('accountSessionProvider 必须由应用入口覆盖');
});
