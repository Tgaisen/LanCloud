import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/transfer_connection_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';

/// 控制新添加上传任务是否立即进入调度；关闭后先保留在「待开始」。
class AutoStartUploadSettingsTile extends ConsumerWidget {
  const AutoStartUploadSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(transferConnectionSettingsStateProvider);
    final l10n = context.l10n;
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => SwitchListTile(
        secondary: const Icon(Icons.play_arrow),
        title: Text(l10n.autoStartUploads),
        subtitle: Text(l10n.autoStartUploadsSubtitle),
        value: settings.autoStartUploads,
        onChanged: (value) => unawaited(settings.setAutoStartUploads(value)),
      ),
    );
  }
}
