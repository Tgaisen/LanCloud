import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

/// 主题、动态取色和全局动画设置的明确读写入口。
class ThemeSettingsState {
  ThemeSettingsState(this.store);

  final SettingsStore store;
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

  Future<void> setMotionMode(String value) async {
    await store.setMotionMode(value);
    revision.value += 1;
  }
}

final themeSettingsStateProvider = Provider<ThemeSettingsState>(
  (ref) => ThemeSettingsState(ref.watch(settingsStoreProvider)),
);
