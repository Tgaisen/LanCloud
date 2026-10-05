import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Account {
  Account({required this.uid, required this.cookie, this.nickname = ''});

  final String uid;
  String cookie;
  String nickname;

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'cookie': cookie,
    'nickname': nickname,
  };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    uid: '${j['uid']}',
    cookie: '${j['cookie']}',
    nickname: '${j['nickname'] ?? ''}',
  );
}

class AccountStore {
  static const _storage = FlutterSecureStorage();
  static const _keyAccounts = 'lancloud_accounts';
  static const _keyActive = 'lancloud_active_uid';

  List<Account> accounts = [];
  String? activeUid;

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _keyAccounts);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        accounts = list
            .map((e) => Account.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      }
      activeUid = await _storage.read(key: _keyActive);
    } catch (_) {
      accounts = [];
      activeUid = null;
    }
    if (accounts.isNotEmpty &&
        (activeUid == null || byUid(activeUid!) == null)) {
      activeUid = accounts.first.uid;
    }
    if (accounts.isEmpty) activeUid = null;
  }

  Account? byUid(String uid) {
    for (final a in accounts) {
      if (a.uid == uid) return a;
    }
    return null;
  }

  Account? get active => activeUid == null ? null : byUid(activeUid!);

  Future<void> upsert(Account account) async {
    final existing = byUid(account.uid);
    if (existing == null) {
      accounts.add(account);
    } else {
      existing.nickname = account.nickname.isEmpty
          ? existing.nickname
          : account.nickname;
    }
    activeUid = account.uid;
    await _save();
  }

  Future<void> setActive(String uid) async {
    activeUid = uid;
    await _save();
  }

  Future<void> setNickname(String uid, String nickname) async {
    final account = byUid(uid);
    if (account == null || account.nickname == nickname) return;
    account.nickname = nickname;
    await _save();
  }

  Future<void> remove(String uid) async {
    accounts.removeWhere((a) => a.uid == uid);
    if (activeUid == uid) {
      activeUid = accounts.isEmpty ? null : accounts.first.uid;
    }
    await _save();
  }

  // ------------------------------------------------------------------ backup

  /// 备份用：默认不导出 Cookie（Cookie 等同于账号凭据）。
  List<Map<String, Object?>> exportAccounts({bool includeCookies = false}) => [
    for (final a in accounts)
      {
        'uid': a.uid,
        'nickname': a.nickname,
        if (includeCookies) 'cookie': a.cookie,
      },
  ];

  /// 恢复账号：按 uid 合并，备份里没有 Cookie 时保留本地已登录的 Cookie；
  /// 本地不存在的账号只有在备份带了 Cookie 时才会新增（否则无法登录）。
  /// 返回受影响的账号数量。
  Future<int> importAccounts(
    List<dynamic> raw, {
    String? activeSnapshot,
  }) async {
    var changed = 0;
    for (final entry in raw) {
      if (entry is! Map) continue;
      final uid = '${entry['uid'] ?? ''}';
      if (uid.isEmpty) continue;
      final nickname = '${entry['nickname'] ?? ''}';
      final cookie = entry['cookie'] == null ? '' : '${entry['cookie']}';
      final existing = byUid(uid);
      if (existing == null) {
        if (cookie.isEmpty) continue;
        accounts.add(Account(uid: uid, cookie: cookie, nickname: nickname));
        changed += 1;
        continue;
      }
      if (nickname.isNotEmpty && nickname != existing.nickname) {
        existing.nickname = nickname;
        changed += 1;
      }
      if (cookie.isNotEmpty && cookie != existing.cookie) {
        existing.cookie = cookie;
        changed += 1;
      }
    }
    if (activeSnapshot != null &&
        activeSnapshot.isNotEmpty &&
        byUid(activeSnapshot) != null &&
        activeUid != activeSnapshot) {
      activeUid = activeSnapshot;
      changed += 1;
    }
    if (changed > 0) await _save();
    return changed;
  }

  Future<void> _save() async {
    await _storage.write(
      key: _keyAccounts,
      value: jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
    if (activeUid == null) {
      await _storage.delete(key: _keyActive);
    } else {
      await _storage.write(key: _keyActive, value: activeUid);
    }
  }
}
