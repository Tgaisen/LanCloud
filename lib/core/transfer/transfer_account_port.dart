import '../api/lanzou_client.dart';
import '../api/lanzou_client_registry.dart';
import '../data/account_store.dart';

/// `TransferManager` 需要的账号与客户端解析能力。
abstract interface class TransferAccountPort {
  String? get activeUid;
  bool hasAccount(String uid);
  LanzouClient clientFor(String uid);
  LanzouClient get publicClient;
}

/// 包装既有账号存储与客户端注册表。
class AppTransferAccountPort implements TransferAccountPort {
  AppTransferAccountPort({
    required this.accounts,
    required this.clients,
  });

  final AccountStore accounts;
  final LanzouClientRegistry clients;

  @override
  String? get activeUid => accounts.activeUid;

  @override
  bool hasAccount(String uid) => accounts.byUid(uid) != null;

  @override
  LanzouClient clientFor(String uid) =>
      clients.clientFor(uid, cookie: accounts.byUid(uid)?.cookie);

  @override
  LanzouClient get publicClient => clients.publicClient;
}
