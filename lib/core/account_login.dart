import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_state.dart';
import 'api/lanzou_client.dart';
import 'api/lanzou_client_registry.dart';
import 'data/account_store.dart';
import 'drive_cache.dart';
import 'drive_state.dart';

/// Cookie 登录流程：验证账号、落盘、缓存客户端并切换当前网盘缓存。
class AccountLogin {
  AccountLogin({
    required this.accountState,
    required this.clients,
    required this.driveCache,
  });

  final AccountState accountState;
  final LanzouClientRegistry clients;
  final DriveCache driveCache;

  Future<void> addAccountFromCookie(String rawCookie) async {
    final cookie = rawCookie.trim();
    final uid = RegExp(r'ylogin=(\d+)').firstMatch(cookie)?.group(1);
    if (uid == null) {
      throw const CookieFormatException();
    }
    final client = clients.create(uid, cookie: cookie);
    final ok = await client.verify();
    if (!ok) throw const CookieInvalidException();
    var nickname = '';
    var level = '';
    try {
      final info = await client.fetchAccountInfo();
      nickname = info.nickname ?? '';
      level = info.level;
    } catch (_) {}
    await accountState.store.upsert(
      Account(uid: uid, cookie: cookie, nickname: nickname, level: level),
    );
    clients.store(uid, client);
    await driveCache.bindAccount(accountState.store.activeUid);
    accountState.notifyAccountChanged();
  }
}

/// 应用级 Cookie 登录服务；依赖既有账号、客户端和网盘缓存所有者。
final accountLoginProvider = Provider<AccountLogin>(
  (ref) => AccountLogin(
    accountState: ref.watch(accountStateProvider),
    clients: ref.watch(lanzouClientRegistryProvider),
    driveCache: ref.watch(driveCacheProvider),
  ),
);
