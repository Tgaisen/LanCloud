import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account_state.dart';
import 'account_store.dart';

/// 应用账号存储入口。
///
/// `AccountStore` 是可写持久化对象，不是可监听状态；这里只负责提供已加载的
/// 唯一实例。生产环境必须由入口覆盖。
final accountStoreProvider = Provider<AccountStore>(
  (ref) => ref.watch(accountStateProvider).store,
);
