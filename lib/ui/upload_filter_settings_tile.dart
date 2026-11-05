import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/transfer_connection_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';

enum UploadFilterSetting { oversize, unsupported }

/// 上传前筛选设置行；被筛掉的任务仍会保留在传输页的「被跳过」分栏。
class UploadFilterSettingsTile extends ConsumerWidget {
  const UploadFilterSettingsTile({super.key, required this.setting});

  final UploadFilterSetting setting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(transferConnectionSettingsStateProvider);
    final l10n = context.l10n;
    final oversize = setting == UploadFilterSetting.oversize;
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => SwitchListTile(
        secondary: Icon(
          oversize ? Icons.upload_file_outlined : Icons.file_present,
        ),
        title: Text(
          oversize ? l10n.skipOversizeUploads : l10n.skipUnsupportedUploads,
        ),
        subtitle: Text(
          oversize
              ? l10n.skipOversizeUploadsSubtitle
              : l10n.skipUnsupportedUploadsSubtitle,
        ),
        value: oversize
            ? settings.skipOversizeUploads
            : settings.skipUnsupportedUploads,
        onChanged: (value) => unawaited(
          oversize
              ? settings.setSkipOversizeUploads(value)
              : settings.setSkipUnsupportedUploads(value),
        ),
      ),
    );
  }
}
