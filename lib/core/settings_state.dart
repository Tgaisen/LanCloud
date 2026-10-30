import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';

/// 设置状态的唯一所有者。
///
/// 首片仍复用现有 [SettingsStore]：字段、默认值、SharedPreferences 格式和
/// setter 都不变；后续再按设置类别逐步迁出细粒度状态。
class SettingsState {
  SettingsState({SettingsStore? store}) : store = store ?? SettingsStore();

  final SettingsStore store;
}

/// 应用级设置状态；不使用 `autoDispose`。
final settingsStateProvider = Provider<SettingsState>((ref) {
  throw StateError('settingsStateProvider 必须由应用入口覆盖');
});
