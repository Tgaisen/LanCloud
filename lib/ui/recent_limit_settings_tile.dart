import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/list_home_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'settings_slider_tile.dart';

/// 最近使用条数设置滑杆。
class RecentLimitSettingsTile extends ConsumerWidget {
  const RecentLimitSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(listHomeSettingsStateProvider);
    final l10n = context.l10n;
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => SettingsSliderTile<int>(
        icon: Icons.history,
        title: l10n.recentLimit,
        values: const [0, 10, 50, 100, 200],
        current: settings.recentLimit,
        labelOf: (value) =>
            value <= 0 ? l10n.recentLimitOff : l10n.recentLimitValue(value),
        onChanged: (value) => unawaited(settings.setRecentLimit(value)),
      ),
    );
  }
}
