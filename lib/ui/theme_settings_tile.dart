import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/theme_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'm3e.dart';

/// 可独立订阅主题设置的控件类型。
enum ThemeSettingsTileType { mode, oledBlack }

/// 主题模式或纯黑深色设置行。
class ThemeSettingsTile extends ConsumerWidget {
  const ThemeSettingsTile({
    super.key,
    required this.type,
  });

  final ThemeSettingsTileType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeSettingsStateProvider);
    final l10n = context.l10n;
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => switch (type) {
        ThemeSettingsTileType.mode => ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: Text(l10n.themeMode),
          // MD3E：行内直接放一颗 tonal 连接式按钮组，点一下即切换。
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: M3eConnectedButtonGroup<String>(
              values: const ['system', 'light', 'dark'],
              selected: settings.themeMode,
              onSelected: (value) => unawaited(settings.setThemeMode(value)),
              labelOf: (value) => Text(
                switch (value) {
                  'light' => l10n.light,
                  'dark' => l10n.dark,
                  _ => l10n.system,
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              semanticLabel: l10n.themeMode,
            ),
          ),
        ),
        ThemeSettingsTileType.oledBlack => SwitchListTile(
          secondary: const Icon(Icons.contrast),
          title: Text(l10n.oled),
          value: settings.oledBlack,
          onChanged: (value) => unawaited(settings.setOledBlack(value)),
        ),
      },
    );
  }
}
