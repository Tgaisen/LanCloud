import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/system_motion.dart';
import 'package:lancloud/core/theme_settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SystemMotion.motionMode.value = 'auto';
  });

  tearDown(() => SystemMotion.motionMode.value = 'auto');

  test('ThemeSettingsState 读写主题、动态取色和动画设置', () async {
    final settings = SettingsStore();
    final state = ThemeSettingsState(settings);

    await state.setThemeMode('dark');
    await state.setThemeSeed(0xFF112233);
    await state.setOledBlack(true);
    await state.setDynamicColor(true);
    await state.setMotionMode('off');
    state.refresh();

    expect(state.revision.value, 6);
    expect(state.themeMode, 'dark');
    expect(state.themeSeed, 0xFF112233);
    expect(state.oledBlack, isTrue);
    expect(state.dynamicColor, isTrue);
    expect(state.dynamicColorChosen, isTrue);
    expect(state.motionMode, 'off');
    expect(SystemMotion.motionMode.value, 'off');
  });

  test('themeSettingsStateProvider 可被共享实例覆盖', () {
    final state = ThemeSettingsState(SettingsStore());
    final container = ProviderContainer(
      overrides: [themeSettingsStateProvider.overrideWithValue(state)],
    );
    addTearDown(container.dispose);

    expect(
      identical(container.read(themeSettingsStateProvider), state),
      isTrue,
    );
  });

  test('恢复备份后系统不支持系统主题色：回退默认蓝并记为已选择', () async {
    SharedPreferences.setMockInitialValues({
      'dynamic_color': true,
      'theme_seed': 0xFF7B4DFF,
    });
    final settings = SettingsStore();
    await settings.load();
    final state = ThemeSettingsState(
      settings,
      dynamicColorSupported: ({bool refresh = false}) async {
        expect(refresh, isTrue);
        return false;
      },
    );

    await state.normalizeDynamicColorAfterRestore();

    expect(state.dynamicColor, isFalse);
    expect(state.dynamicColorChosen, isTrue);
    expect(state.themeSeed, 0xFF2E6BE6);
    expect(state.revision.value, 2);
  });
}
