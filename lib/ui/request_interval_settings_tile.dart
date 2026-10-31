import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/transfer_connection_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'settings_slider_tile.dart';

/// 蓝奏云网络请求间隔设置滑杆。
class RequestIntervalSettingsTile extends ConsumerWidget {
  const RequestIntervalSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(transferConnectionSettingsStateProvider);
    final l10n = context.l10n;
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => SettingsSliderTile<int>(
        icon: Icons.timer_outlined,
        title: l10n.requestInterval,
        subtitle: l10n.requestIntervalHint,
        values: const [25, 50, 75, 100, 150, 200, 300, 500, 1000],
        current: settings.requestInterval,
        labelOf: (ms) => '$ms ms',
        onChanged: (value) => unawaited(settings.setRequestInterval(value)),
      ),
    );
  }
}
