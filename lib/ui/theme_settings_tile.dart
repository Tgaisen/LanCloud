import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/theme_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';

/// 可独立订阅主题设置的控件类型。
enum ThemeSettingsTileType { mode, oledBlack }

/// 主题色弹窗的选择结果。
typedef ThemeColorSelection = ({bool dynamicColor, int? seed});

/// 将预设主题色 seed 映射为当前语言下的名称。
String themeSeedLabel(AppLocalizations l10n, int seed) => switch (seed) {
  0xFF2E6BE6 => l10n.classicBlue,
  0xFF00897B => l10n.teal,
  0xFF7B4DFF => l10n.violet,
  0xFFE5533D => l10n.vermilion,
  0xFF3F7D20 => l10n.olive,
  0xFF6750A4 => l10n.colorMd3Purple,
  0xFF0B57D0 => l10n.colorRoyalBlue,
  0xFF984061 => l10n.colorRose,
  0xFF8B5000 => l10n.colorAmber,
  _ => l10n.custom,
};

/// 选择动态取色或一个预设主题色。
Future<ThemeColorSelection?> showThemeColorPicker(
  BuildContext context, {
  required bool dynamicSupported,
  required bool dynamicColor,
  required int seed,
}) {
  final l10n = context.l10n;
  final presets = <int, String>{
    0xFF2E6BE6: l10n.classicBlue,
    0xFF00897B: l10n.teal,
    0xFF7B4DFF: l10n.violet,
    0xFFE5533D: l10n.vermilion,
    0xFF3F7D20: l10n.olive,
    0xFF6750A4: l10n.colorMd3Purple,
    0xFF0B57D0: l10n.colorRoyalBlue,
    0xFF984061: l10n.colorRose,
    0xFF8B5000: l10n.colorAmber,
  };
  // 不支持时动态取色按未选中处理（也点不动）。
  final dynamicSelected = dynamicSupported && dynamicColor;
  return showDialog<ThemeColorSelection>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.themeColor),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 与其它选择弹窗同一套列表组样式：选中 = 主容器色 + 对勾
            // 比弹窗底（surfaceContainerHigh）再高一档容器色。
            DialogListGroup(
              children: [
                M3ePickTile(
                  label: l10n.dynamicColor,
                  subtitle: dynamicSupported
                      ? l10n.dynamicColorSubtitle
                      : l10n.dynamicColorUnsupported,
                  selected: dynamicSelected,
                  singleSelect: true,
                  enabled: dynamicSupported,
                  leading: const Icon(Icons.wallpaper_outlined),
                  onTap: () => Navigator.of(dialogContext).pop<ThemeColorSelection>(
                    (dynamicColor: true, seed: null),
                  ),
                ),
                for (final entry in presets.entries)
                  M3ePickTile(
                    label: entry.value,
                    selected: !dynamicSelected && seed == entry.key,
                    singleSelect: true,
                    leading: CircleAvatar(
                      radius: 12,
                      backgroundColor: Color(entry.key),
                    ),
                    onTap: () =>
                        Navigator.of(dialogContext).pop<ThemeColorSelection>(
                      (dynamicColor: false, seed: entry.key),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

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

/// 主题色入口；弹窗返回选择后，通过唯一主题状态写入。
class ThemeColorSettingsTile extends ConsumerWidget {
  const ThemeColorSettingsTile({
    super.key,
    required this.dynamicSupported,
  });

  final bool dynamicSupported;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeSettingsStateProvider);
    final l10n = context.l10n;
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) {
        final dynamicColor = settings.dynamicColor;
        return ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(l10n.themeColor),
          subtitle: Text(
            dynamicColor
                ? l10n.dynamicColor
                : themeSeedLabel(l10n, settings.themeSeed),
          ),
          // 动态取色时没有固定颜色可展示，尾部不再画色块。
          trailing: dynamicColor
              ? null
              : CircleAvatar(
                  radius: 12,
                  backgroundColor: Color(settings.themeSeed),
                ),
          onTap: () => unawaited(_pickColor(context, settings)),
        );
      },
    );
  }

  Future<void> _pickColor(
    BuildContext context,
    ThemeSettingsState settings,
  ) async {
    final selection = await showThemeColorPicker(
      context,
      dynamicSupported: dynamicSupported,
      dynamicColor: settings.dynamicColor,
      seed: settings.themeSeed,
    );
    if (!context.mounted || selection == null) return;
    if (selection.dynamicColor) {
      await settings.setDynamicColor(true);
      return;
    }
    final seed = selection.seed;
    if (seed == null) return;
    // 与动态取色互斥：选具体颜色即关闭动态取色。
    await settings.setDynamicColor(false);
    await settings.setThemeSeed(seed);
  }
}
