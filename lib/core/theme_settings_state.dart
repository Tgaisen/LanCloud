import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

/// 主题、动态取色和全局动画设置的明确读写入口。
class ThemeSettingsState {
  const ThemeSettingsState(this.store);

  final SettingsStore store;

  String get themeMode => store.themeMode;
  int get themeSeed => store.themeSeed;
  bool get oledBlack => store.oledBlack;
  bool get dynamicColor => store.dynamicColor;
  bool get dynamicColorChosen => store.dynamicColorChosen;
  String get motionMode => store.motionMode;

  Future<void> setThemeMode(String value) => store.setThemeMode(value);
  Future<void> setThemeSeed(int value) => store.setThemeSeed(value);
  Future<void> setOledBlack(bool value) => store.setOledBlack(value);
  Future<void> setDynamicColor(bool value) => store.setDynamicColor(value);
  Future<void> setMotionMode(String value) => store.setMotionMode(value);
}

final themeSettingsStateProvider = Provider<ThemeSettingsState>(
  (ref) => ThemeSettingsState(ref.watch(settingsStoreProvider)),
);
