import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';
import 'drive_cache.dart';
import 'drive_state.dart';

/// 页面展示、启动页和目录缓存策略的明确读写入口。
class CachePageSettingsState {
  CachePageSettingsState(this.store, this.driveCache);

  final SettingsStore store;
  final DriveCache driveCache;
  final ValueNotifier<int> revision = ValueNotifier(0);

  bool get gridView => store.gridView;
  String get launchPage => store.launchPage;
  bool get cacheFolders => store.cacheFolders;
  bool get loadAllPages => store.loadAllPages;

  Future<void> setGridView(bool value) async {
    await store.setGridView(value);
    revision.value += 1;
  }

  Future<void> setLaunchPage(String value) async {
    await store.setLaunchPage(value);
    revision.value += 1;
  }

  Future<void> setCacheFolders(bool value) async {
    await store.setCacheFolders(value);
    if (!value) driveCache.clear();
    revision.value += 1;
  }

  Future<void> setLoadAllPages(bool value) async {
    await store.setLoadAllPages(value);
    revision.value += 1;
  }
}

final cachePageSettingsStateProvider = Provider<CachePageSettingsState>(
  (ref) => CachePageSettingsState(
    ref.watch(settingsStoreProvider),
    ref.watch(driveCacheProvider),
  ),
);
