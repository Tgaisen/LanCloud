import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/api/models.dart';
import '../core/duplicate_files.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';

/// 展示当前目录中的同名文件组，并返回用户确认要删除的文件 id。
///
/// 返回 `null` 表示取消；空集合不会返回。
Future<Set<String>?> showSameNamedFilesSheet(
  BuildContext context, {
  required DuplicateFileScan scan,
  required bool hasMore,
}) {
  return showAppSheet<Set<String>>(
    context,
    child: _SameNamedFilesSheet(scan: scan, hasMore: hasMore),
  );
}

/// 删除同名文件前的类型化确认入口。
Future<bool> showDeleteSameNamedFilesConfirm(
  BuildContext context,
  int count,
) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.deleteConfirmTitle),
      content: Text(l10n.sameNamedFilesDeleteConfirm(count)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class _SameNamedFilesSheet extends StatefulWidget {
  const _SameNamedFilesSheet({required this.scan, required this.hasMore});

  final DuplicateFileScan scan;
  final bool hasMore;

  @override
  State<_SameNamedFilesSheet> createState() => _SameNamedFilesSheetState();
}

class _SameNamedFilesSheetState extends State<_SameNamedFilesSheet> {
  final Set<String> _selected = <String>{};
  late final Map<String, DuplicateFileGroup> _groupByFileId;

  @override
  void initState() {
    super.initState();
    _groupByFileId = {
      for (final group in widget.scan.groups)
        for (final file in group.files) file.id: group,
    };
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  void _toggleFile(String fileId) {
    final group = _groupByFileId[fileId];
    if (group == null) return;
    if (_selected.contains(fileId)) {
      setState(() => _selected.remove(fileId));
      return;
    }

    final selectedInGroup = group.files
        .where((file) => _selected.contains(file.id))
        .length;
    if (selectedInGroup >= group.files.length - 1) {
      showAppToast(context, context.l10n.sameNamedFilesKeepOne);
      return;
    }
    setState(() => _selected.add(fileId));
  }

  void _keepLatest(DuplicateFileGroup group) {
    setState(() {
      _selected.removeAll(group.files.map((file) => file.id));
      _selected.addAll(group.newestOnlySelection);
    });
  }

  Future<void> _confirmDelete() async {
    if (_selected.isEmpty) return;
    final confirmed = await showDeleteSameNamedFilesConfirm(
      context,
      _selected.length,
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop(Set<String>.unmodifiable(_selected));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scan = widget.scan;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  l10n.sameNamedFilesTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: _cancel, child: Text(l10n.cancel)),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _selected.isEmpty ? null : _confirmDelete,
                child: Text(l10n.delete),
              ),
            ],
          ),
          if (widget.hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InfoHintCard(text: l10n.sameNamedFilesIncomplete),
            ),
          if (scan.isEmpty)
            EmptyHint(icon: Icons.file_copy, text: l10n.sameNamedFilesEmpty)
          else
            for (final group in scan.groups) ...[
              SectionHeader(
                title: group.name,
                count: group.files.length,
                countLabel: l10n.sameNamedFilesItemCount(group.files.length),
                compact: !isLargeLayout(context),
                actions: [
                  TextButton(
                    onPressed: () => _keepLatest(group),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: Text(l10n.keepLatest),
                  ),
                ],
              ),
              SegmentedList(
                margin: EdgeInsets.zero,
                children: [
                  for (final (index, file) in group.files.indexed)
                    _DuplicateFileTile(
                      key: ValueKey('same-name-file-${file.id}'),
                      file: file,
                      index: index,
                      selected: _selected.contains(file.id),
                      onTap: () => _toggleFile(file.id),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          if (!scan.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                l10n.sameNamedFilesSummary(scan.groupCount, scan.fileCount),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DuplicateFileTile extends StatelessWidget {
  const _DuplicateFileTile({
    super.key,
    required this.file,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final LzFile file;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      checked: selected,
      child: Md3ListItem(
        icon: iconForFile(file.name),
        iconColor: fileIconColor(file.name, brightness: scheme.brightness),
        title: file.name,
        subtitle: lzFileListSubtitle(context, file),
        selected: selected,
        index: index,
        animateIn: false,
        onTap: onTap,
        trailing: ExcludeSemantics(
          child: IgnorePointer(
            child: Checkbox(value: selected, onChanged: (_) => onTap()),
          ),
        ),
      ),
    );
  }
}
