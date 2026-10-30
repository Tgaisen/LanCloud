import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

/// 导航外观与交互开关的明确读写入口。
class NavigationAppearanceSettingsState {
  const NavigationAppearanceSettingsState(this.store);

  final SettingsStore store;

  bool get swipeTabs => store.swipeTabs;
  bool get hideTopBar => store.hideTopBar;
  bool get hideBottomBar => store.hideBottomBar;
  bool get floatingNavBar => store.floatingNavBar;
  bool get transitionAnimations => store.transitionAnimations;
  bool get navShowTransfers => store.navShowTransfers;
  bool get navShowFavorites => store.navShowFavorites;

  Future<void> setSwipeTabs(bool value) => store.setSwipeTabs(value);
  Future<void> setHideTopBar(bool value) => store.setHideTopBar(value);
  Future<void> setHideBottomBar(bool value) => store.setHideBottomBar(value);
  Future<void> setFloatingNavBar(bool value) =>
      store.setFloatingNavBar(value);
  Future<void> setTransitionAnimations(bool value) =>
      store.setTransitionAnimations(value);
  Future<void> setNavShowTransfers(bool value) =>
      store.setNavShowTransfers(value);
  Future<void> setNavShowFavorites(bool value) =>
      store.setNavShowFavorites(value);
}

final navigationAppearanceSettingsStateProvider =
    Provider<NavigationAppearanceSettingsState>(
      (ref) => NavigationAppearanceSettingsState(
        ref.watch(settingsStoreProvider),
      ),
    );
