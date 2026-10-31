import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/language_clipboard_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';

/// 复制分享链接后是否提示打开的设置行。
class ClipboardLinkPromptTile extends ConsumerWidget {
  const ClipboardLinkPromptTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(languageClipboardSettingsStateProvider);
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => SwitchListTile(
        secondary: const Icon(Icons.content_paste_go),
        title: Text(context.l10n.clipboardLinkPrompt),
        subtitle: Text(context.l10n.clipboardLinkPromptSubtitle),
        value: settings.clipboardLinkPrompt,
        onChanged: (value) => unawaited(settings.setClipboardLinkPrompt(value)),
      ),
    );
  }
}
