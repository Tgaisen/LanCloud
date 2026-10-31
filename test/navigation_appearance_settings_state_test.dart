import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
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

  test('Riverpod 直属关闭隐藏栏时仍按少动效立即展开', () async {
    final navigation = NavigationState();
    addTearDown(navigation.dispose);
    final state = NavigationAppearanceSettingsState(
      SettingsStore(),
      navigation: navigation,
      reduceMotion: () => true,
    );
    navigation.barsHide.value = 1;
    navigation.topBarHide.value = 1;

    await state.setHideTopBar(false);
    expect(navigation.barsHide.value, 0);
    expect(navigation.topBarHide.value, 0);
  });

  test('批量设置底栏显示项只产生一次 revision', () async {
    final state = NavigationAppearanceSettingsState(SettingsStore());

    await state.setNavItems(transfers: true, favorites: true);

    expect(state.revision.value, 1);
    expect(state.navShowTransfers, isTrue);
    expect(state.navShowFavorites, isTrue);
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
