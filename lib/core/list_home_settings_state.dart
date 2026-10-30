import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

/// 列表排序与首页展示设置的明确读写入口。
class ListHomeSettingsState {
  ListHomeSettingsState(this.store);

  final SettingsStore store;
  final ValueNotifier<int> revision = ValueNotifier(0);

  String get sortMode => store.sortMode;
  bool get quickExpanded => store.quickExpanded;
  bool get recentsExpanded => store.recentsExpanded;
  int get recentLimit => store.recentLimit;
  String get homeFolderOpenMode => store.homeFolderOpenMode;

  Future<void> setSortMode(String value) async {
    await store.setSortMode(value);
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
    revision.value += 1;
  }

  Future<void> setHomeFolderOpenMode(String value) async {
    await store.setHomeFolderOpenMode(value);
    revision.value += 1;
  }
}

final listHomeSettingsStateProvider = Provider<ListHomeSettingsState>(
  (ref) => ListHomeSettingsState(ref.watch(settingsStoreProvider)),
);
