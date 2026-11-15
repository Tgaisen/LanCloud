import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

enum FavoriteCheckFrequency {
  daily,
  weekly,
  monthly;

  static FavoriteCheckFrequency fromName(String value) => values.firstWhere(
    (frequency) => frequency.name == value,
    orElse: () => FavoriteCheckFrequency.weekly,
  );
}

/// 收藏文件夹自动检测的配置读写边界。
class FavoriteMonitorSettingsState {
  FavoriteMonitorSettingsState(this.store);

  final SettingsStore store;
  final ValueNotifier<int> revision = ValueNotifier(0);

  bool get autoCheck => store.favoriteAutoCheck;

  FavoriteCheckFrequency get frequency =>
      FavoriteCheckFrequency.fromName(store.favoriteCheckFrequency);

  bool get checkAll => store.favoriteCheckAll;

  Set<String> get checkRefs {
    try {
      final value = jsonDecode(store.favoriteCheckRefsJson);
      if (value is! List) return const <String>{};
      return {
        for (final item in value)
          if (item is String && item.isNotEmpty) item,
      };
    } catch (_) {
      return const <String>{};
    }
  }

  bool get notifyUpdates => store.favoriteUpdateNotify;

  Future<void> setAutoCheck(bool value) async {
    await store.setFavoriteAutoCheck(value);
    revision.value += 1;
  }

  Future<void> setFrequency(FavoriteCheckFrequency value) async {
    await store.setFavoriteCheckFrequency(value.name);
    revision.value += 1;
  }

  Future<void> setScope({required bool all, required Set<String> refs}) async {
    final sorted = refs.where((ref) => ref.isNotEmpty).toList()..sort();
    await store.setFavoriteCheckScope(all: all, refsJson: jsonEncode(sorted));
    revision.value += 1;
  }

  Future<void> setNotifyUpdates(bool value) async {
    await store.setFavoriteUpdateNotify(value);
    revision.value += 1;
  }
}

final favoriteMonitorSettingsStateProvider =
    Provider<FavoriteMonitorSettingsState>(
      (ref) => FavoriteMonitorSettingsState(ref.watch(settingsStoreProvider)),
    );
