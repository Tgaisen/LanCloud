import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/data/app_db.dart';
import '../core/data/app_db_provider.dart';
import '../core/favorite_monitor_settings_state.dart';
import '../core/favorites/favorite_monitor.dart';
import '../core/notifications.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';

class FavoriteAutoCheckSettingsTile extends ConsumerStatefulWidget {
  const FavoriteAutoCheckSettingsTile({
    super.key,
    this.onPermissionChanged,
    this.requestPermission,
    this.runCheckOnEnable = true,
  });

  final ValueChanged<bool>? onPermissionChanged;
  final Future<bool> Function()? requestPermission;
  final bool runCheckOnEnable;

  @override
  ConsumerState<FavoriteAutoCheckSettingsTile> createState() =>
      _FavoriteAutoCheckSettingsTileState();
}

class _FavoriteAutoCheckSettingsTileState
    extends ConsumerState<FavoriteAutoCheckSettingsTile> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(favoriteMonitorSettingsStateProvider);
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => SwitchListTile(
        secondary: const Icon(Icons.folder_check),
        title: Text(context.l10n.favoriteAutoCheck),
        value: settings.autoCheck,
        onChanged: (value) => unawaited(_setEnabled(settings, value)),
      ),
    );
  }

  Future<void> _setEnabled(
    FavoriteMonitorSettingsState settings,
    bool value,
  ) async {
    if (value && settings.notifyUpdates) {
      final messenger = ScaffoldMessenger.of(context);
      final deniedText = context.l10n.notifPermissionDeniedHint;
      final request =
          widget.requestPermission ??
          NotificationService.instance.requestPermission;
      final granted = await request();
      widget.onPermissionChanged?.call(granted);
      if (!granted) {
        messenger.showSnackBar(SnackBar(content: Text(deniedText)));
      }
    }
    await settings.setAutoCheck(value);
    if (value && mounted && widget.runCheckOnEnable) {
      unawaited(ref.read(favoriteMonitorProvider.notifier).maybeAutoCheck());
    }
  }
}

class FavoriteCheckScopeSettingsTile extends ConsumerWidget {
  const FavoriteCheckScopeSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(favoriteMonitorSettingsStateProvider);
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) {
        final l10n = context.l10n;
        final subtitle = settings.checkAll
            ? l10n.favoriteCheckScopeAll
            : l10n.favoriteCheckScopeSelected(settings.checkRefs.length);
        return ListTile(
          enabled: settings.autoCheck,
          leading: const Icon(Icons.checklist),
          title: Text(l10n.favoriteCheckScope),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: settings.autoCheck
              ? () => unawaited(_chooseScope(context, ref, settings))
              : null,
        );
      },
    );
  }

  Future<void> _chooseScope(
    BuildContext context,
    WidgetRef ref,
    FavoriteMonitorSettingsState settings,
  ) async {
    final folders = (await ref.read(appDbProvider).favorites())
        .where((favorite) => favorite.kind == 'shareFolder')
        .toList();
    if (!context.mounted) return;
    final result = await showFavoriteCheckScopeDialog(
      context,
      folders: folders,
      initial: FavoriteCheckScopeSelection(
        all: settings.checkAll,
        refs: settings.checkRefs,
      ),
    );
    if (result == null) return;
    await settings.setScope(all: result.all, refs: result.refs);
  }
}

class FavoriteCheckFrequencySettingsTile extends ConsumerWidget {
  const FavoriteCheckFrequencySettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(favoriteMonitorSettingsStateProvider);
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => ListTile(
        enabled: settings.autoCheck,
        leading: const Icon(Icons.schedule),
        title: Text(context.l10n.favoriteCheckFrequency),
        subtitle: Text(
          favoriteCheckFrequencyLabel(context.l10n, settings.frequency),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: settings.autoCheck
            ? () => unawaited(_chooseFrequency(context, ref, settings))
            : null,
      ),
    );
  }

  Future<void> _chooseFrequency(
    BuildContext context,
    WidgetRef ref,
    FavoriteMonitorSettingsState settings,
  ) async {
    final monitor = ref.read(favoriteMonitorProvider);
    final selected = await showFavoriteCheckFrequencyDialog(
      context,
      selected: settings.frequency,
      lastAttemptAt: monitor.lastAttemptAt,
      failed: monitor.lastResult?.failed ?? 0,
    );
    if (selected != null) await settings.setFrequency(selected);
  }
}

class FavoriteUpdateNotificationSettingsTile extends ConsumerStatefulWidget {
  const FavoriteUpdateNotificationSettingsTile({
    super.key,
    this.onPermissionChanged,
    this.requestPermission,
  });

  final ValueChanged<bool>? onPermissionChanged;
  final Future<bool> Function()? requestPermission;

  @override
  ConsumerState<FavoriteUpdateNotificationSettingsTile> createState() =>
      _FavoriteUpdateNotificationSettingsTileState();
}

class _FavoriteUpdateNotificationSettingsTileState
    extends ConsumerState<FavoriteUpdateNotificationSettingsTile> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(favoriteMonitorSettingsStateProvider);
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => SwitchListTile(
        secondary: const Icon(Icons.cards_star),
        title: Text(context.l10n.favoriteUpdateNotify),
        subtitle: Text(context.l10n.favoriteUpdateNotifySubtitle),
        value: settings.notifyUpdates,
        onChanged: (value) => unawaited(_setValue(settings, value)),
      ),
    );
  }

  Future<void> _setValue(
    FavoriteMonitorSettingsState settings,
    bool value,
  ) async {
    if (value) {
      final messenger = ScaffoldMessenger.of(context);
      final deniedText = context.l10n.notifPermissionDeniedHint;
      final request =
          widget.requestPermission ??
          NotificationService.instance.requestPermission;
      final granted = await request();
      widget.onPermissionChanged?.call(granted);
      if (!granted) {
        messenger.showSnackBar(SnackBar(content: Text(deniedText)));
      }
    }
    await settings.setNotifyUpdates(value);
  }
}

String favoriteCheckFrequencyLabel(
  AppLocalizations l10n,
  FavoriteCheckFrequency frequency,
) => switch (frequency) {
  FavoriteCheckFrequency.daily => l10n.favoriteCheckDaily,
  FavoriteCheckFrequency.weekly => l10n.favoriteCheckWeekly,
  FavoriteCheckFrequency.monthly => l10n.favoriteCheckMonthly,
};

String favoriteLastCheckLabel(
  AppLocalizations l10n, {
  required DateTime? lastAttemptAt,
  required int failed,
}) {
  if (lastAttemptAt == null) return l10n.favoriteLastCheckNever;
  final time = formatRelativeTime(l10n, lastAttemptAt);
  return failed > 0
      ? l10n.favoriteLastCheckFailed(time, failed)
      : l10n.favoriteLastCheck(time);
}

Future<FavoriteCheckFrequency?> showFavoriteCheckFrequencyDialog(
  BuildContext context, {
  required FavoriteCheckFrequency selected,
  required DateTime? lastAttemptAt,
  required int failed,
}) {
  final l10n = context.l10n;
  return showDialog<FavoriteCheckFrequency>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.favoriteCheckFrequency),
          const SizedBox(height: 16),
          Text(
            favoriteLastCheckLabel(
              l10n,
              lastAttemptAt: lastAttemptAt,
              failed: failed,
            ),
            key: const ValueKey('favorite-check-frequency-supporting-text'),
            style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      content: SingleChildScrollView(
        child: DialogListGroup(
          children: [
            for (final frequency in FavoriteCheckFrequency.values)
              M3ePickTile(
                label: favoriteCheckFrequencyLabel(l10n, frequency),
                selected: frequency == selected,
                singleSelect: true,
                onTap: () =>
                    Navigator.of(dialogContext)
                        .pop<FavoriteCheckFrequency>(frequency),
              ),
          ],
        ),
      ),
    ),
  );
}

class FavoriteCheckScopeSelection {
  const FavoriteCheckScopeSelection({required this.all, required this.refs});

  final bool all;
  final Set<String> refs;
}

Future<FavoriteCheckScopeSelection?> showFavoriteCheckScopeDialog(
  BuildContext context, {
  required List<FavoriteItem> folders,
  required FavoriteCheckScopeSelection initial,
}) {
  final l10n = context.l10n;
  final allRefs = {for (final folder in folders) folder.ref};
  var all = initial.all;
  var refs = {...initial.refs};

  bool canSave() => all || refs.isNotEmpty;

  return showDialog<FavoriteCheckScopeSelection>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(l10n.favoriteCheckScope),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        content: SingleChildScrollView(
          child: DialogListGroup(
            children: [
              M3ePickTile(
                label: l10n.favoriteCheckScopeAll,
                selected: all,
                onTap: () => setDialogState(() {
                  all = !all;
                  refs = <String>{};
                }),
              ),
              for (final folder in folders)
                M3ePickTile(
                  label: folder.displayName,
                  selected: all || refs.contains(folder.ref),
                  onTap: () => setDialogState(() {
                    if (all) {
                      all = false;
                      refs = {...allRefs};
                    }
                    if (!refs.remove(folder.ref)) refs.add(folder.ref);
                  }),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: canSave()
                ? () => Navigator.of(dialogContext)
                      .pop(FavoriteCheckScopeSelection(all: all, refs: refs))
                : null,
            child: Text(l10n.confirm),
          ),
        ],
      ),
    ),
  );
}
