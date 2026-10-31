import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/cache_page_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';

/// 目录缓存或自动加载全部页面的设置行。
class CachePageSettingsTile extends ConsumerWidget {
  const CachePageSettingsTile({super.key, required this.cacheFolders});

  final bool cacheFolders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(cachePageSettingsStateProvider);
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => SwitchListTile(
        secondary: Icon(
          cacheFolders
              ? Icons.cached_outlined
              : Icons.download_for_offline_outlined,
        ),
        title: Text(
          cacheFolders ? context.l10n.cacheFolders : context.l10n.loadAllPages,
        ),
        subtitle: Text(
          cacheFolders
              ? context.l10n.cacheFoldersSubtitle
              : context.l10n.loadAllPagesSubtitle,
        ),
        value: cacheFolders ? settings.cacheFolders : settings.loadAllPages,
        onChanged: (value) => unawaited(
          cacheFolders
              ? settings.setCacheFolders(value)
              : settings.setLoadAllPages(value),
        ),
      ),
    );
  }
}
