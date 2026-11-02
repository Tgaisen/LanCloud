import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/transfer_connection_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'settings_slider_tile.dart';

/// 上传、任务下载或单文件连接数设置。
enum TransferConcurrencySetting { uploads, downloads, singleFileConnections }

/// 传输并发数滑杆；松手时通过唯一设置状态写入。
class TransferConcurrencySettingsTile extends ConsumerWidget {
  const TransferConcurrencySettingsTile({super.key, required this.setting});

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
          TransferConcurrencySetting.singleFileConnections => (
            icon: Icons.speed,
            title: l10n.singleFileDownloadConnections,
            values: const [1, 2, 3, 4],
            current: settings.downloadConnections,
          ),
        };
        return SettingsSliderTile<int>(
          icon: config.icon,
          title: config.title,
          subtitle: setting == TransferConcurrencySetting.singleFileConnections
              ? l10n.singleFileDownloadConnectionsSubtitle
              : null,
          values: config.values,
          current: config.current,
          labelOf: (value) => '$value',
          onChanged: (value) => unawaited(_setValue(settings, value)),
        );
      },
    );
  }

  Future<void> _setValue(TransferConnectionSettingsState settings, int value) {
    return switch (setting) {
      TransferConcurrencySetting.uploads => settings.setMaxUploads(value),
      TransferConcurrencySetting.downloads => settings.setMaxDownloads(value),
      TransferConcurrencySetting.singleFileConnections =>
        settings.setDownloadConnections(value),
    };
  }
}
