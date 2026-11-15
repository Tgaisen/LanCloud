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
        secondary: const Icon(Icons.history),
        title: Text(context.l10n.favoriteAutoCheck),
        subtitle: Text(context.l10n.favoriteAutoCheckSubtitle),
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
      unawaited(ref.read(favoriteMonitorProvider.notifier).checkFolders());
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
      builder: (context, _, _) => Builder(
        builder: (tileContext) => ListTile(
          enabled: settings.autoCheck,
          leading: const Icon(Icons.schedule),
          title: Text(context.l10n.favoriteCheckFrequency),
          subtitle: Text(
            favoriteCheckFrequencyLabel(context.l10n, settings.frequency),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: settings.autoCheck
              ? () => unawaited(_chooseFrequency(tileContext, ref, settings))
              : null,
        ),
      ),
    );
  }

  Future<void> _chooseFrequency(
    BuildContext context,
    WidgetRef ref,
    FavoriteMonitorSettingsState settings,
  ) async {
    final anchor = m3eMenuAnchorOf(context);
    if (anchor == null) return;
    final selected =
        await showAdaptiveM3eSingleSelectMenu<FavoriteCheckFrequency>(
          context: context,
          anchor: anchor,
          selected: settings.frequency,
          alignEnd: true,
          items: [
            for (final frequency in FavoriteCheckFrequency.values)
              M3eMenuItem(
                value: frequency,
                label: favoriteCheckFrequencyLabel(context.l10n, frequency),
                icon: Icons.schedule,
              ),
          ],
        );
    if (selected != null) await settings.setFrequency(selected);
  }
}

class FavoriteLastCheckSettingsTile extends ConsumerWidget {
  const FavoriteLastCheckSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(
      favoriteMonitorProvider.select(
        (state) => (state.lastAttemptAt, state.lastResult?.failed ?? 0),
      ),
    );
    final (:lastAttemptAt, :failed) = (
      lastAttemptAt: snapshot.$1,
      failed: snapshot.$2,
    );
    final l10n = context.l10n;
    final text = switch (lastAttemptAt) {
      null => l10n.favoriteLastCheckNever,
      final time when failed > 0 => l10n.favoriteLastCheckFailed(
        formatRelativeTime(l10n, time),
        failed,
      ),
      final time => l10n.favoriteLastCheck(formatRelativeTime(l10n, time)),
    };
    return ListTile(
      enabled: false,
      leading: const Icon(Icons.history),
      title: Text(text),
    );
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
        secondary: const Icon(Icons.notifications_outlined),
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

class FavoriteCheckScopeSelection {
  const FavoriteCheckScopeSelection({required this.all, required this.refs});

  final bool all;
  final Set<String> refs;
}

Future<FavoriteCheckScopeSelection?> showFavoriteCheckScopeDialog(
  BuildContext context, {
  required List<FavoriteItem> folders,
  required FavoriteCheckScopeSelection initial,
}) => showAppSheet<FavoriteCheckScopeSelection>(
  context,
  child: _FavoriteCheckScopeSheet(folders: folders, initial: initial),
);

class _FavoriteCheckScopeSheet extends StatefulWidget {
  const _FavoriteCheckScopeSheet({
    required this.folders,
    required this.initial,
  });

  final List<FavoriteItem> folders;
  final FavoriteCheckScopeSelection initial;

  @override
  State<_FavoriteCheckScopeSheet> createState() =>
      _FavoriteCheckScopeSheetState();
}

class _FavoriteCheckScopeSheetState extends State<_FavoriteCheckScopeSheet> {
  late bool _all = widget.initial.all;
  late Set<String> _refs = widget.initial.refs;

  Set<String> get _allRefs => {for (final folder in widget.folders) folder.ref};

  bool get _canSave => _all || _refs.isNotEmpty;

  void _toggleAll(bool checked) {
    setState(() {
      _all = checked;
      _refs = <String>{};
    });
  }

  void _toggleFolder(String ref, bool checked) {
    setState(() {
      if (_all) {
        _all = false;
        _refs = _allRefs;
      }
      if (checked) {
        _refs.add(ref);
      } else {
        _refs.remove(ref);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            l10n.favoriteCheckScopeTitle,
            style: context.m3eEmphasizedTheme.titleLarge,
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              SheetListGroup(
                margin: SheetListGroup.endMargin,
                children: [
                  CheckboxListTile(
                    value: _all,
                    onChanged: (value) => _toggleAll(value ?? false),
                    secondary: const Icon(Icons.select_all),
                    title: Text(l10n.favoriteCheckScopeAll),
                  ),
                  for (final folder in widget.folders)
                    CheckboxListTile(
                      value: _all || _refs.contains(folder.ref),
                      onChanged: (value) =>
                          _toggleFolder(folder.ref, value ?? false),
                      secondary: const Icon(Icons.folder),
                      title: Text(folder.displayName),
                    ),
                ],
              ),
              if (widget.folders.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: EmptyHint(
                    icon: Icons.folder_outlined,
                    text: l10n.favoriteCheckNoFolders,
                    frameSize: 64,
                    iconSize: 32,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _canSave
                ? () => Navigator.of(context)
                      .pop(FavoriteCheckScopeSelection(all: _all, refs: _refs))
                : null,
            child: Text(l10n.save),
          ),
        ),
      ],
    );
  }
}
