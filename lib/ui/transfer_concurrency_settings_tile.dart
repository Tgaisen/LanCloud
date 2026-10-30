import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/transfer_connection_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'settings_slider_tile.dart';

/// 上传或下载并发数设置。
enum TransferConcurrencySetting { uploads, downloads }

/// 传输并发数滑杆；松手时通过唯一设置状态写入。
class TransferConcurrencySettingsTile extends ConsumerWidget {
  const TransferConcurrencySettingsTile({
    super.key,
    required this.setting,
  });

  final TransferConcurrencySetting setting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(transferConnectionSettingsStateProvider);
    final l10n = context.l10n;
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) {
        final config = switch (setting) {
          TransferConcurrencySetting.uploads => (
            icon: Icons.upload_outlined,
            title: l10n.maxUploads,
            values: const [1, 2, 3],
            current: settings.maxUploads,
          ),
          TransferConcurrencySetting.downloads => (
            icon: Icons.download_outlined,
            title: l10n.maxDownloads,
            values: const [1, 2, 3, 4, 5],
            current: settings.maxDownloads,
          ),
        };
        return SettingsSliderTile<int>(
          icon: config.icon,
          title: config.title,
          values: config.values,
          current: config.current,
          labelOf: (value) => '$value',
          onChanged: (value) => unawaited(_setValue(settings, value)),
        );
      },
    );
  }

  Future<void> _setValue(
    TransferConnectionSettingsState settings,
    int value,
  ) {
    return switch (setting) {
      TransferConcurrencySetting.uploads => settings.setMaxUploads(value),
      TransferConcurrencySetting.downloads =>
        settings.setMaxDownloads(value),
    };
  }
}
