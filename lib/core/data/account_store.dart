import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Account {
  Account({required this.uid, required this.cookie, this.nickname = ''});

  final String uid;
  final String cookie;
  String nickname;

  Map<String, dynamic> toJson() => {'uid': uid, 'cookie': cookie, 'nickname': nickname};

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
    if (accounts.isNotEmpty && (activeUid == null || byUid(activeUid!) == null)) {
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
      existing.nickname = account.nickname.isEmpty ? existing.nickname : account.nickname;
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
    if (activeUid == uid) activeUid = accounts.isEmpty ? null : accounts.first.uid;
    await _save();
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
