import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_state.dart';
import 'data/app_db_provider.dart';
import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

/// 列表排序与首页展示设置的明确读写入口。
class ListHomeSettingsState {
  ListHomeSettingsState(this.store, {this.trimRecents, this.activeUid});

  final SettingsStore store;
  final Future<void> Function(String uid, int limit)? trimRecents;
  final String? Function()? activeUid;
  final ValueNotifier<int> revision = ValueNotifier(0);

  String get sortMode => store.sortMode;
  bool get sortAscending => store.sortAscending;
  String get favoritesSortMode => store.favoritesSortMode;
  bool get favoritesSortAscending => store.favoritesSortAscending;
  String get folderPickerSortMode => store.folderPickerSortMode;
  bool get folderPickerSortAscending => store.folderPickerSortAscending;
  bool get quickExpanded => store.quickExpanded;
  bool get recentsExpanded => store.recentsExpanded;
  int get recentLimit => store.recentLimit;
  String get homeFolderOpenMode => store.homeFolderOpenMode;

  Future<void> setSortMode(String value) async {
    await store.setSortMode(value);
    revision.value += 1;
  }

  Future<void> setSortAscending(bool value) async {
    await store.setSortAscending(value);
    revision.value += 1;
  }

  Future<void> setFavoritesSortMode(String value) async {
    await store.setFavoritesSortMode(value);
    revision.value += 1;
  }

  Future<void> setFavoritesSortAscending(bool value) async {
    await store.setFavoritesSortAscending(value);
    revision.value += 1;
  }

  Future<void> setFolderPickerSortMode(String value) async {
    await store.setFolderPickerSortMode(value);
    revision.value += 1;
  }

  Future<void> setFolderPickerSortAscending(bool value) async {
    await store.setFolderPickerSortAscending(value);
    revision.value += 1;
  }

  Future<void> setQuickExpanded(bool value) async {
    await store.setQuickExpanded(value);
    revision.value += 1;
  }

  Future<void> setRecentsExpanded(bool value) async {
    await store.setRecentsExpanded(value);
    revision.value += 1;
  }

  Future<void> setRecentLimit(int value) async {
    await store.setRecentLimit(value);
    final uid = activeUid?.call();
    if (uid != null) await trimRecents?.call(uid, value);
    revision.value += 1;
  }

  Future<void> setHomeFolderOpenMode(String value) async {
    await store.setHomeFolderOpenMode(value);
    revision.value += 1;
  }
}

final listHomeSettingsStateProvider = Provider<ListHomeSettingsState>((ref) {
  final accounts = ref.watch(accountStateProvider).store;
  final db = ref.watch(appDbProvider);
  return ListHomeSettingsState(
    ref.watch(settingsStoreProvider),
    trimRecents: db.trimRecents,
    activeUid: () => accounts.activeUid,
  );
});
