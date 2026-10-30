import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/navigation_appearance_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';

/// 底栏可选显示项的多选结果。
typedef NavBarItemsSelection = ({bool transfers, bool favorites});

/// 底栏显示项摘要：首页 · 网盘 [· 传输] [· 收藏] · 我的。
String navItemsLabel(
  AppLocalizations l10n, {
  required bool transfers,
  required bool favorites,
}) => [
  l10n.tabHome,
  l10n.tabDrive,
  if (transfers) l10n.tabTransfers,
  if (favorites) l10n.favorite,
  l10n.tabProfile,
].join(' · ');

/// 选择“传输”和“收藏”是否显示在底栏。
Future<NavBarItemsSelection?> showNavBarItemsPicker(
  BuildContext context, {
  required bool transfers,
  required bool favorites,
}) {
  final l10n = context.l10n;
  var draftTransfers = transfers;
  var draftFavorites = favorites;
  return showDialog<NavBarItemsSelection>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(l10n.navBarItems),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.navBarItemsHint,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            DialogListGroup(
              children: [
                M3ePickTile(
                  label: l10n.tabTransfers,
                  leading: const Icon(Icons.swap_vert),
                  selected: draftTransfers,
                  onTap: () => setDialogState(
                    () => draftTransfers = !draftTransfers,
                  ),
                ),
                M3ePickTile(
                  label: l10n.favorite,
                  leading: const Icon(Icons.star_border),
                  selected: draftFavorites,
                  onTap: () => setDialogState(
                    () => draftFavorites = !draftFavorites,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop<NavBarItemsSelection>(
              (transfers: draftTransfers, favorites: draftFavorites),
            ),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    ),
  );
}

/// 可独立订阅导航外观设置的开关类型。
enum NavigationAppearanceSetting {
  hideTopBar,
  hideBottomBar,
  floatingNav,
  swipeTabs,
  transitionAnimations,
}

/// 悬浮导航、滑动切页或转场动画设置行。
class NavigationAppearanceSettingsTile extends ConsumerWidget {
  const NavigationAppearanceSettingsTile({
    super.key,
    required this.setting,
  });

  final NavigationAppearanceSetting setting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(navigationAppearanceSettingsStateProvider);
    final l10n = context.l10n;
    final config = switch (setting) {
      NavigationAppearanceSetting.hideTopBar => (
        icon: Icons.vertical_align_top,
        title: l10n.hideTopBar,
        subtitle: null,
      ),
      NavigationAppearanceSetting.hideBottomBar => (
        icon: Icons.vertical_align_bottom,
        title: l10n.hideBottomBar,
        subtitle: null,
      ),
      NavigationAppearanceSetting.floatingNav => (
        icon: Icons.smart_button,
        title: l10n.floatingNav,
        subtitle: null,
      ),
      NavigationAppearanceSetting.swipeTabs => (
        icon: Icons.swipe,
        title: l10n.swipeTabs,
        subtitle: l10n.swipeTabsSubtitle,
      ),
      NavigationAppearanceSetting.transitionAnimations => (
        icon: Icons.auto_awesome_motion,
        title: l10n.transitionAnimations,
        subtitle: l10n.transitionAnimationsSubtitle,
      ),
    };

    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => SwitchListTile(
        secondary: Icon(config.icon),
        title: Text(config.title),
        subtitle: config.subtitle == null ? null : Text(config.subtitle!),
        value: switch (setting) {
          NavigationAppearanceSetting.hideTopBar => settings.hideTopBar,
          NavigationAppearanceSetting.hideBottomBar => settings.hideBottomBar,
          NavigationAppearanceSetting.floatingNav => settings.floatingNavBar,
          NavigationAppearanceSetting.swipeTabs => settings.swipeTabs,
          NavigationAppearanceSetting.transitionAnimations =>
            settings.transitionAnimations,
        },
        onChanged: (value) => unawaited(_setValue(settings, value)),
      ),
    );
  }

  Future<void> _setValue(
    NavigationAppearanceSettingsState settings,
    bool value,
  ) {
    return switch (setting) {
      NavigationAppearanceSetting.hideTopBar => settings.setHideTopBar(value),
      NavigationAppearanceSetting.hideBottomBar =>
        settings.setHideBottomBar(value),
      NavigationAppearanceSetting.floatingNav =>
        settings.setFloatingNavBar(value),
      NavigationAppearanceSetting.swipeTabs => settings.setSwipeTabs(value),
      NavigationAppearanceSetting.transitionAnimations =>
        settings.setTransitionAnimations(value),
    };
  }
}

/// 底栏显示项多选设置行。
class NavBarItemsSettingsTile extends ConsumerWidget {
  const NavBarItemsSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(navigationAppearanceSettingsStateProvider);
    final l10n = context.l10n;
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => ListTile(
        leading: const Icon(Icons.bottom_navigation),
        title: Text(l10n.navBarItems),
        subtitle: Text(
          navItemsLabel(
            l10n,
            transfers: settings.navShowTransfers,
            favorites: settings.navShowFavorites,
          ),
        ),
        onTap: () => unawaited(_pick(context, settings)),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    NavigationAppearanceSettingsState settings,
  ) async {
    final selection = await showNavBarItemsPicker(
      context,
      transfers: settings.navShowTransfers,
      favorites: settings.navShowFavorites,
    );
    if (selection == null) return;
    await settings.setNavItems(
      transfers: selection.transfers,
      favorites: selection.favorites,
    );
  }
}
