import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';
import 'navigation_state.dart';

/// 导航外观与交互开关的明确读写入口。
class NavigationAppearanceSettingsState {
  NavigationAppearanceSettingsState(
    this.store, {
    this.navigation,
    this.reduceMotion,
  });

  final SettingsStore store;
  final NavigationState? navigation;
  final bool Function()? reduceMotion;
  final ValueNotifier<int> revision = ValueNotifier(0);

  bool get swipeTabs => store.swipeTabs;
  bool get hideTopBar => store.hideTopBar;
  bool get hideBottomBar => store.hideBottomBar;
  bool get floatingNavBar => store.floatingNavBar;
  bool get transitionAnimations => store.transitionAnimations;
  bool get navShowTransfers => store.navShowTransfers;
  bool get navShowFavorites => store.navShowFavorites;

  Future<void> setSwipeTabs(bool value) async {
    await store.setSwipeTabs(value);
    revision.value += 1;
  }

  Future<void> setHideTopBar(bool value) async {
    await store.setHideTopBar(value);
    if (!value) _restoreBars();
    revision.value += 1;
  }

  Future<void> setHideBottomBar(bool value) async {
    await store.setHideBottomBar(value);
    if (!value) _restoreBars();
    revision.value += 1;
  }

  Future<void> setFloatingNavBar(bool value) async {
    await store.setFloatingNavBar(value);
    revision.value += 1;
  }

  Future<void> setTransitionAnimations(bool value) async {
    await store.setTransitionAnimations(value);
    revision.value += 1;
  }

  Future<void> setNavShowTransfers(bool value) async {
    await store.setNavShowTransfers(value);
    revision.value += 1;
  }

  Future<void> setNavShowFavorites(bool value) async {
    await store.setNavShowFavorites(value);
    revision.value += 1;
  }

  Future<void> setNavItems({
    required bool transfers,
    required bool favorites,
  }) async {
    await store.setNavShowTransfers(transfers);
    await store.setNavShowFavorites(favorites);
    revision.value += 1;
  }

  void _restoreBars() {
    navigation?.animateBarsHide(
      0,
      reduceMotion: reduceMotion?.call() ?? false,
    );
  }
}

final navigationAppearanceSettingsStateProvider =
    Provider<NavigationAppearanceSettingsState>(
      (ref) => NavigationAppearanceSettingsState(
        ref.watch(settingsStoreProvider),
      ),
    );
