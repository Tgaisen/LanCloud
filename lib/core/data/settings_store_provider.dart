import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_store.dart';

/// 应用设置存储入口。
///
/// `SettingsStore` 是可写持久化对象，不是可监听状态；这里只负责提供已加载的
/// 唯一实例，调用方仍通过 store 的方法读写。生产环境必须由入口覆盖。
final settingsStoreProvider = Provider<SettingsStore>((ref) {
  throw StateError('settingsStoreProvider 必须由应用入口覆盖');
});
