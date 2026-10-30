import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/account_store.dart';

/// 账号列表与当前账号状态的唯一所有者。
///
/// 阶段 3 过渡期仍复用现有 [AccountStore]：它继续负责持久化、登录信息和当前
/// uid，`AccountState` 负责生命周期与后续响应式依赖的挂载点。
class AccountState extends ChangeNotifier {
  AccountState({AccountStore? store}) : store = store ?? AccountStore();

  final AccountStore store;

  /// 登录 / 登出等账号集合变化后通知应用级兼容监听者。
  void notifyAccountChanged() => notifyListeners();
}

/// 应用级账号状态；不使用 `autoDispose`。
final accountStateProvider = Provider<AccountState>((ref) {
  throw StateError('accountStateProvider 必须由应用入口覆盖');
});
