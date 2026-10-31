import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/cache_page_settings_state.dart';
import '../core/list_home_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';

String launchPageLabel(AppLocalizations l10n, String page) =>
    page == 'drive' ? l10n.tabDrive : l10n.tabHome;

String homeFolderOpenLabel(AppLocalizations l10n, String mode) =>
    mode == 'drive' ? l10n.openInDriveTab : l10n.openInNewPage;

Future<String?> showLaunchPagePicker(
  BuildContext context, {
  required String current,
}) {
  final l10n = context.l10n;
  return _showChoice(
    context,
    title: l10n.launchPage,
    options: [('home', l10n.tabHome), ('drive', l10n.tabDrive)],
    current: current,
  );
}

Future<String?> showHomeFolderOpenPicker(
  BuildContext context, {
  required String current,
}) {
  final l10n = context.l10n;
  return _showChoice(
    context,
    title: l10n.homeFolderOpen,
    options: [('drive', l10n.openInDriveTab), ('page', l10n.openInNewPage)],
    current: current,
  );
}

Future<T?> _showChoice<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T current,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
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
                    onTap: () => Navigator.of(dialogContext).pop<T>(entry.$1),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 默认启动页设置行。
class LaunchPageSettingsTile extends ConsumerWidget {
  const LaunchPageSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(cachePageSettingsStateProvider);
    final l10n = context.l10n;
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => ListTile(
        leading: const Icon(Icons.home_outlined),
        title: Text(l10n.launchPage),
        subtitle: Text(launchPageLabel(l10n, settings.launchPage)),
        onTap: () => unawaited(_pick(context, settings)),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    CachePageSettingsState settings,
  ) async {
    final selected = await showLaunchPagePicker(
      context,
      current: settings.launchPage,
    );
    if (selected != null) await settings.setLaunchPage(selected);
  }
}

/// 首页目录打开方式设置行。
class HomeFolderOpenSettingsTile extends ConsumerWidget {
  const HomeFolderOpenSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(listHomeSettingsStateProvider);
    final l10n = context.l10n;
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => ListTile(
        leading: const Icon(Icons.open_in_new),
        title: Text(l10n.homeFolderOpen),
        subtitle: Text(homeFolderOpenLabel(l10n, settings.homeFolderOpenMode)),
        onTap: () => unawaited(_pick(context, settings)),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    ListHomeSettingsState settings,
  ) async {
    final selected = await showHomeFolderOpenPicker(
      context,
      current: settings.homeFolderOpenMode,
    );
    if (selected != null) await settings.setHomeFolderOpenMode(selected);
  }
}
