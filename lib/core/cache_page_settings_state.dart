import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

/// 页面展示、启动页和目录缓存策略的明确读写入口。
class CachePageSettingsState {
  const CachePageSettingsState(this.store);

  final SettingsStore store;

  bool get gridView => store.gridView;
  String get launchPage => store.launchPage;
  bool get cacheFolders => store.cacheFolders;
  bool get loadAllPages => store.loadAllPages;

  Future<void> setGridView(bool value) => store.setGridView(value);
  Future<void> setLaunchPage(String value) => store.setLaunchPage(value);
  Future<void> setCacheFolders(bool value) => store.setCacheFolders(value);
  Future<void> setLoadAllPages(bool value) => store.setLoadAllPages(value);
}

final cachePageSettingsStateProvider = Provider<CachePageSettingsState>(
  (ref) => CachePageSettingsState(ref.watch(settingsStoreProvider)),
);
