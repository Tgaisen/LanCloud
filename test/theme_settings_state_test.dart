import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/settings_state.dart';
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

    expect(state.themeMode, 'dark');
    expect(state.themeSeed, 0xFF112233);
    expect(state.oledBlack, isTrue);
    expect(state.dynamicColor, isTrue);
    expect(state.dynamicColorChosen, isTrue);
    expect(state.motionMode, 'off');
  });

  test('AppController 修改全局动画时仍同步 SystemMotion', () async {
    final app = AppController(settingsState: SettingsState());
    addTearDown(app.dispose);

    await app.setMotionMode('off');

    expect(app.settings.motionMode, 'off');
    expect(SystemMotion.motionMode.value, 'off');
  });

  test('themeSettingsStateProvider 可被共享实例覆盖', () {
    final state = ThemeSettingsState(SettingsStore());
    final container = ProviderContainer(
      overrides: [themeSettingsStateProvider.overrideWithValue(state)],
    );
    addTearDown(container.dispose);

    expect(identical(container.read(themeSettingsStateProvider), state), isTrue);
  });
}
