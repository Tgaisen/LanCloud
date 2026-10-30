import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/language_clipboard_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';

/// 将语言设置值映射为当前界面语言下的名称。
String languageLabel(AppLocalizations l10n, String language) =>
    switch (language) {
      'zh' => l10n.chinese,
      'en' => l10n.english,
      _ => l10n.followSystem,
    };

/// 选择跟随系统、中文或英文。
Future<String?> showLanguagePicker(
  BuildContext context, {
  required String current,
}) {
  final l10n = context.l10n;
  final options = <(String, String)>[
    ('system', l10n.followSystem),
    ('zh', l10n.chinese),
    ('en', l10n.english),
  ];
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.language),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DialogListGroup(
              children: [
                for (final entry in options)
                  M3ePickTile(
                    label: entry.$2,
                    selected: current == entry.$1,
                    singleSelect: true,
                    onTap: () =>
                        Navigator.of(dialogContext).pop<String>(entry.$1),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 界面语言设置行。
class LanguageSettingsTile extends ConsumerWidget {
  const LanguageSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(languageClipboardSettingsStateProvider);
    final l10n = context.l10n;
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => ListTile(
        leading: const Icon(Icons.translate),
        title: Text(l10n.language),
        subtitle: Text(languageLabel(l10n, settings.language)),
        onTap: () => unawaited(_pickLanguage(context, settings)),
      ),
    );
  }

  Future<void> _pickLanguage(
    BuildContext context,
    LanguageClipboardSettingsState settings,
  ) async {
    final selected = await showLanguagePicker(
      context,
      current: settings.language,
    );
    if (selected != null) await settings.setLanguage(selected);
  }
}
