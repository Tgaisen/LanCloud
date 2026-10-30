import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

/// 列表排序与首页展示设置的明确读写入口。
class ListHomeSettingsState {
  const ListHomeSettingsState(this.store);

  final SettingsStore store;

  String get sortMode => store.sortMode;
  bool get quickExpanded => store.quickExpanded;
  bool get recentsExpanded => store.recentsExpanded;
  int get recentLimit => store.recentLimit;
  String get homeFolderOpenMode => store.homeFolderOpenMode;

  Future<void> setSortMode(String value) => store.setSortMode(value);
  Future<void> setQuickExpanded(bool value) => store.setQuickExpanded(value);
  Future<void> setRecentsExpanded(bool value) =>
      store.setRecentsExpanded(value);
  Future<void> setRecentLimit(int value) => store.setRecentLimit(value);
  Future<void> setHomeFolderOpenMode(String value) =>
      store.setHomeFolderOpenMode(value);
}

final listHomeSettingsStateProvider = Provider<ListHomeSettingsState>(
  (ref) => ListHomeSettingsState(ref.watch(settingsStoreProvider)),
);
