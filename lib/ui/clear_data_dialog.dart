import 'package:material_ui/material_ui.dart' hide Icons;

import '../l10n/l10n.dart';
import 'app_icons.dart' as app_icons;
import 'common.dart';
import 'm3e.dart';

enum ClearDataOption { quickAccess, recents, otherAccounts, logs, registry }

enum ClearDataAction {
  clearSelected,
  openAppDataDirectory,
  openLogsDirectory,
  deleteAll,
}

final class ClearDataDialogResult {
  const ClearDataDialogResult({required this.action, this.selected = const {}});

  final ClearDataAction action;
  final Set<ClearDataOption> selected;
}

Future<ClearDataDialogResult?> showClearDataDialog(
  BuildContext context, {
  required bool signedIn,
  required bool showWindowsActions,
}) {
  final l10n = context.l10n;
  final selected = <ClearDataOption>{};
  return showDialog<ClearDataDialogResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        Widget group(String name, List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            M3eSectionHeader(name, horizontalInset: 0),
            DialogListGroup(children: children),
          ],
        );

        List<Widget> selectionRows(List<ClearDataOption> options) => [
          for (final option in options)
            M3ePickTile(
              label: _clearDataName(l10n, option),
              subtitle: _clearDataSubtitle(l10n, option),
              selected: selected.contains(option),
              onTap: () => setDialogState(() {
                if (!selected.remove(option)) selected.add(option);
              }),
            ),
        ];

        return AlertDialog(
          title: Text(l10n.clearData),
          contentPadding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (signedIn)
                  group(l10n.clearDataGroupAccount, [
                    ...selectionRows(const [
                      ClearDataOption.quickAccess,
                      ClearDataOption.recents,
                    ]),
                  ]),
                group(l10n.clearDataGroupOthers, [
                  ...selectionRows([
                    ClearDataOption.otherAccounts,
                    ClearDataOption.logs,
                    if (showWindowsActions) ClearDataOption.registry,
                  ]),
                ]),
                if (showWindowsActions) ...[
                  group(l10n.clearDataGroupDataDirectory, [
                    _openDirectoryRow(
                      label: l10n.clearDataAppDataDirectory,
                      subtitle: l10n.clearDataAppDataDirectorySubtitle,
                      onTap: () => Navigator.of(dialogContext).pop(
                        const ClearDataDialogResult(
                          action: ClearDataAction.openAppDataDirectory,
                        ),
                      ),
                    ),
                    _openDirectoryRow(
                      label: l10n.clearDataLogsDirectory,
                      subtitle: l10n.clearDataLogsDirectorySubtitle,
                      onTap: () => Navigator.of(dialogContext).pop(
                        const ClearDataDialogResult(
                          action: ClearDataAction.openLogsDirectory,
                        ),
                      ),
                    ),
                  ]),
                  group(l10n.clearDataGroupDanger, [
                    _deleteAllDataRow(
                      context: dialogContext,
                      onTap: () => Navigator.of(dialogContext).pop(
                        const ClearDataDialogResult(
                          action: ClearDataAction.deleteAll,
                        ),
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(
                      ClearDataDialogResult(
                        action: ClearDataAction.clearSelected,
                        selected: Set<ClearDataOption>.of(selected),
                      ),
                    ),
              child: Text(l10n.clear),
            ),
          ],
        );
      },
    ),
  );
}

Future<bool?> showDeleteAllDataConfirmation(
  BuildContext context, {
  required bool hasActiveTransfers,
}) {
  final l10n = context.l10n;
  final colorScheme = Theme.of(context).colorScheme;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.clearDataDeleteAllTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.clearDataDeleteAllBody),
          if (hasActiveTransfers) ...[
            const SizedBox(height: 12),
            Text(
              l10n.clearDataDeleteAllTransferWarning,
              style: TextStyle(color: colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('clear-data-delete-all-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.clearDataDeleteAll),
        ),
      ],
    ),
  );
}

Widget _openDirectoryRow({
  required String label,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return ListTile(
    title: Text(label),
    subtitle: Text(subtitle),
    trailing: Icon(app_icons.Icons.open_in_new),
    onTap: onTap,
  );
}

Widget _deleteAllDataRow({
  required BuildContext context,
  required VoidCallback onTap,
}) {
  final l10n = context.l10n;
  final color = Theme.of(context).colorScheme.error;
  return ListTile(
    key: const ValueKey('clear-data-delete-all'),
    title: Text(l10n.clearDataDeleteAll, style: TextStyle(color: color)),
    subtitle: Text(l10n.clearDataDeleteAllSubtitle),
    onTap: onTap,
  );
}

String _clearDataName(AppLocalizations l10n, ClearDataOption option) =>
    switch (option) {
      ClearDataOption.quickAccess => l10n.quickAccess,
      ClearDataOption.recents => l10n.recent,
      ClearDataOption.otherAccounts => l10n.clearDataOtherAccounts,
      ClearDataOption.logs => l10n.clearDataLogs,
      ClearDataOption.registry => l10n.clearDataRegistry,
    };

String? _clearDataSubtitle(AppLocalizations l10n, ClearDataOption option) =>
    switch (option) {
      ClearDataOption.otherAccounts => l10n.clearDataOtherAccountsSubtitle,
      ClearDataOption.registry => l10n.clearDataRegistrySubtitle,
      _ => null,
    };
