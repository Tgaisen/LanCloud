import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/navigation_appearance_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';

/// 可独立订阅导航外观设置的开关类型。
enum NavigationAppearanceSetting {
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
      NavigationAppearanceSetting.floatingNav =>
        settings.setFloatingNavBar(value),
      NavigationAppearanceSetting.swipeTabs => settings.setSwipeTabs(value),
      NavigationAppearanceSetting.transitionAnimations =>
        settings.setTransitionAnimations(value),
    };
  }
}
