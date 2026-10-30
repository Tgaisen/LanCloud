import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('NavigationAppearanceSettingsState 读写全部导航外观字段', () async {
    final settings = SettingsStore();
    final state = NavigationAppearanceSettingsState(settings);

    await state.setSwipeTabs(true);
    await state.setHideTopBar(true);
    await state.setHideBottomBar(true);
    await state.setFloatingNavBar(true);
    await state.setTransitionAnimations(false);
    await state.setNavShowTransfers(true);
    await state.setNavShowFavorites(true);

    expect(state.revision.value, 7);
    expect(state.swipeTabs, isTrue);
    expect(state.hideTopBar, isTrue);
    expect(state.hideBottomBar, isTrue);
    expect(state.floatingNavBar, isTrue);
    expect(state.transitionAnimations, isFalse);
    expect(state.navShowTransfers, isTrue);
    expect(state.navShowFavorites, isTrue);
  });

  test('关闭隐藏顶栏/底栏时旧 API 仍立即把进度归零', () async {
    final app = AppController(settingsState: SettingsState());
    addTearDown(app.dispose);
    app.systemReduceMotion = true;
    app.barsHide.value = 1;
    app.topBarHide.value = 1;

    await app.setHideTopBar(false);
    expect(app.barsHide.value, 0);
    expect(app.topBarHide.value, 0);

    app.barsHide.value = 1;
    app.topBarHide.value = 1;
    await app.setHideBottomBar(false);
    expect(app.barsHide.value, 0);
    expect(app.topBarHide.value, 0);
  });

  test('Riverpod 侧设置变更会转发到旧 AppController 监听者', () async {
    final app = AppController(settingsState: SettingsState());
    addTearDown(app.dispose);
    var notifications = 0;
    app.addListener(() => notifications += 1);

    await app.navigationAppearanceSettings.setFloatingNavBar(true);

    expect(notifications, 1);
    expect(app.settings.floatingNavBar, isTrue);
  });

  test('navigationAppearanceSettingsStateProvider 可被共享实例覆盖', () {
    final state = NavigationAppearanceSettingsState(SettingsStore());
    final container = ProviderContainer(
      overrides: [
        navigationAppearanceSettingsStateProvider.overrideWithValue(state),
      ],
    );
    addTearDown(container.dispose);

    expect(
      identical(
        container.read(navigationAppearanceSettingsStateProvider),
        state,
      ),
      isTrue,
    );
  });
}
