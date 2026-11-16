import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/api/models.dart';
import '../core/duplicate_files.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';

/// 展示当前目录中的同名文件组，并返回用户确认要删除的文件 id。
///
/// 返回 `null` 表示取消；空集合不会返回。
Future<Set<String>?> showSameNamedFilesSheet(
  BuildContext context, {
  required DuplicateFileScan scan,
  required bool hasMore,
}) {
  final sheetHeightRatio = scan.isEmpty
      ? 0.8
      : _estimatedSheetHeightRatio(context, scan, hasMore: hasMore);
  return showAppSheet<Set<String>>(
    context,
    maxHeightRatio: sheetHeightRatio,
    fitContent: scan.isEmpty,
    child: _SameNamedFilesSheet(scan: scan, hasMore: hasMore),
  );
}

double _estimatedSheetHeightRatio(
  BuildContext context,
  DuplicateFileScan scan, {
  required bool hasMore,
}) {
  final estimatedHeight =
      56 + (hasMore ? 64 : 0) + scan.groupCount * 44 + scan.fileCount * 72 + 48;
  return (estimatedHeight / MediaQuery.sizeOf(context).height)
      .clamp(0.38, 0.86)
      .toDouble();
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

  void _cancel() {
    Navigator.of(context).pop();
  }

  void _toggleFile(String fileId) {
    setState(() {
      if (!_selected.remove(fileId)) _selected.add(fileId);
    });
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

  Widget _header(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              l10n.sameNamedFilesTitle,
              style: context.m3eEmphasizedTheme.titleLarge,
            ),
          ),
          const SizedBox(width: 8),
          M3eIconButton(
            key: const ValueKey('same-name-cancel'),
            tooltip: l10n.cancel,
            icon: Icons.close,
            onPressed: _cancel,
          ),
          M3eIconButton(
            key: const ValueKey('same-name-delete'),
            tooltip: l10n.delete,
            icon: Icons.delete_outline,
            onPressed: _selected.isEmpty ? null : _confirmDelete,
          ),
        ],
      ),
    );
  }

  Widget _incompleteNotice(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: InfoHintCard(text: context.l10n.sameNamedFilesIncomplete),
  );

  Widget _groupHeader(BuildContext context, DuplicateFileGroup group) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SectionHeader(
          title: group.name,
          count: group.files.length,
          compact: !isLargeLayout(context),
          actions: [
            TextButton(
              onPressed: () => _keepLatest(group),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(context.l10n.keepLatest),
            ),
          ],
        ),
      );

  Widget _fileTile(DuplicateFileGroup group, int index) {
    final file = group.files[index];
    return _DuplicateFileTile(
      key: ValueKey('same-name-file-${file.id}'),
      file: file,
      index: index,
      selected: _selected.contains(file.id),
      onTap: () => _toggleFile(file.id),
    );
  }

  Widget _summary(BuildContext context) {
    final scan = widget.scan;
    return Text(
      context.l10n.sameNamedFilesSummary(scan.groupCount, scan.fileCount),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  Widget _buildScrollableBody(BuildContext context) {
    final scan = widget.scan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        if (widget.hasMore) _incompleteNotice(context),
        Expanded(
          child: SheetNestedScrollView(
            slivers: [
              for (final group in scan.groups)
                SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(child: _groupHeader(context, group)),
                    SegmentedSliverList(
                      itemCount: group.files.length,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      itemBuilder: (context, index) => _fileTile(group, index),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                sliver: SliverToBoxAdapter(child: _summary(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        if (widget.hasMore) _incompleteNotice(context),
        EmptyHint(
          icon: Icons.file_copy,
          text: context.l10n.sameNamedFilesEmpty,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => widget.scan.isEmpty
      ? _buildEmptyBody(context)
      : _buildScrollableBody(context);
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
      ),
    );
  }
}
