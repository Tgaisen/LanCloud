import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/theme_settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('设备支持动态取色且用户没选过：自动开启并记为用户已选', () async {
    final settings = SettingsStore();
    await settings.load();
    final state = ThemeSettingsState(
      settings,
      dynamicColorSupported: () async => true,
    );

    await state.enableDynamicColorIfUnset();

    expect(settings.dynamicColor, isTrue);
    expect(settings.dynamicColorChosen, isTrue);
  });

  test('设备不支持动态取色：保持关闭', () async {
    final settings = SettingsStore();
    await settings.load();
    final state = ThemeSettingsState(
      settings,
      dynamicColorSupported: () async => false,
    );

    await state.enableDynamicColorIfUnset();

    expect(settings.dynamicColor, isFalse);
    expect(settings.dynamicColorChosen, isFalse);
  });

  test('用户手动关掉后：不再自动开启', () async {
    SharedPreferences.setMockInitialValues({
      'dynamic_color': false,
      'dynamic_color_chosen': true,
    });
    final settings = SettingsStore();
    await settings.load();
    final state = ThemeSettingsState(
      settings,
      dynamicColorSupported: () async => true,
    );

    await state.enableDynamicColorIfUnset();

    expect(settings.dynamicColor, isFalse);
  });
}
