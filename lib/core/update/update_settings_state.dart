import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_store.dart';
import '../data/settings_store_provider.dart';

/// 更新通道与自动检查开关的单一读写入口。
///
/// 数据仍持久化在 [SettingsStore]；本状态不复制字段，只收窄更新功能的设置边界。
class UpdateSettingsState {
  UpdateSettingsState(this.store);

  final SettingsStore store;
  final ValueNotifier<int> revision = ValueNotifier(0);

  String get channel => store.updateChannel;

  bool get autoCheck => store.updateAutoCheck;

  Future<bool> setChannel(String value) async {
    if (store.updateChannel == value) return false;
    await store.setUpdateChannel(value);
    revision.value += 1;
    return true;
  }

  Future<void> setAutoCheck(bool value) async {
    await store.setUpdateAutoCheck(value);
    revision.value += 1;
  }
}

final updateSettingsStateProvider = Provider<UpdateSettingsState>(
  (ref) => UpdateSettingsState(ref.watch(settingsStoreProvider)),
);
