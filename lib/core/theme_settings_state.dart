import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';
import 'dynamic_color_support.dart';
import 'system_motion.dart';

/// 主题、动态取色和全局动画设置的明确读写入口。
class ThemeSettingsState {
  ThemeSettingsState(
    this.store, {
    Future<bool> Function({bool refresh})? dynamicColorSupported,
  }) : dynamicColorSupported =
           dynamicColorSupported ?? DynamicColorSupport.isSupported;

  final SettingsStore store;
  final Future<bool> Function({bool refresh}) dynamicColorSupported;
  final ValueNotifier<int> revision = ValueNotifier(0);

  String get themeMode => store.themeMode;
  int get themeSeed => store.themeSeed;
  bool get oledBlack => store.oledBlack;
  bool get dynamicColor => store.dynamicColor;
  bool get dynamicColorChosen => store.dynamicColorChosen;
  String get motionMode => store.motionMode;

  Future<void> setThemeMode(String value) async {
    await store.setThemeMode(value);
    revision.value += 1;
  }

  Future<void> setThemeSeed(int value) async {
    await store.setThemeSeed(value);
    revision.value += 1;
  }

  Future<void> setOledBlack(bool value) async {
    await store.setOledBlack(value);
    revision.value += 1;
  }

  Future<void> setDynamicColor(bool value) async {
    await store.setDynamicColor(value);
    revision.value += 1;
  }

  /// 设备支持动态取色且用户从未手动选择时，默认开启一次。
  Future<void> enableDynamicColorIfUnset() async {
    if (dynamicColorChosen || dynamicColor) return;
    if (!await dynamicColorSupported()) return;
    // 探测期间用户可能已经手动选择。
    if (dynamicColorChosen || dynamicColor) return;
    await setDynamicColor(true);
  }

  /// 备份恢复后重新校验系统主题色；不支持时落回默认蓝并清除跟随系统状态。
  Future<void> normalizeDynamicColorAfterRestore() async {
    if (!dynamicColor) return;
    if (await dynamicColorSupported(refresh: true)) return;
    // 探测期间用户可能已手动改过主题色，避免覆盖新的选择。
    if (!dynamicColor) return;
    await setDynamicColor(false);
    if (store.themeSeed != 0xFF2E6BE6) await setThemeSeed(0xFF2E6BE6);
  }

  Future<void> setMotionMode(String value) async {
    await store.setMotionMode(value);
    SystemMotion.motionMode.value = store.motionMode;
    revision.value += 1;
  }

  /// 设置已从其他入口重新加载后，通知订阅者重新读取。
  void refresh() => revision.value += 1;
}

final themeSettingsStateProvider = Provider<ThemeSettingsState>(
  (ref) => ThemeSettingsState(ref.watch(settingsStoreProvider)),
);
