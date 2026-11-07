import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/transfer/transfer_manager.dart';
import '../core/transfer/upload_rename.dart';
import '../l10n/l10n.dart';
import 'common.dart';

/// 单个上传任务的名称修改。
Future<String?> showSingleUploadRenameDialog(
  BuildContext context, {
  required TransferTask task,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _SingleUploadRenameDialog(initialName: task.name),
  );
}

/// 批量上传任务的查找替换与预览。
Future<List<UploadRenameChange>?> showBatchUploadRenameDialog(
  BuildContext context, {
  required List<TransferTask> tasks,
}) {
  return showDialog<List<UploadRenameChange>>(
    context: context,
    builder: (_) => _BatchUploadRenameDialog(
      targets: [
        for (final task in tasks)
          UploadRenameTarget(id: task.id, name: task.name),
      ],
    ),
  );
}

class _SingleUploadRenameDialog extends StatefulWidget {
  const _SingleUploadRenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_SingleUploadRenameDialog> createState() =>
      _SingleUploadRenameDialogState();
}

class _SingleUploadRenameDialogState extends State<_SingleUploadRenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.l10n.pleaseEnterName);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return formDialog(
      context,
      title: Text(l10n.rename),
      content: TextField(
        key: const ValueKey('upload-rename-field'),
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: errorState(
          context,
          InputDecoration(
            border: const OutlineInputBorder(),
            labelText: l10n.nameLabel,
          ),
          _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('upload-rename-confirm'),
          onPressed: _submit,
          child: Text(l10n.modify),
        ),
      ],
    );
  }
}

class _BatchUploadRenameDialog extends StatefulWidget {
  const _BatchUploadRenameDialog({required this.targets});

  final List<UploadRenameTarget> targets;

  @override
  State<_BatchUploadRenameDialog> createState() =>
      _BatchUploadRenameDialogState();
}

class _BatchUploadRenameDialogState extends State<_BatchUploadRenameDialog> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  UploadRenameError? _error;
  UploadRenamePreview? _preview;
  bool _useRegex = false;
  bool _matchCase = false;

  @override
  void dispose() {
    _searchController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  void _buildPreview() {
    final preview = UploadRenameRule(
      search: _searchController.text,
      replacement: _replaceController.text,
      useRegex: _useRegex,
      matchCase: _matchCase,
    ).preview(widget.targets);
    if (!preview.canApply) {
      setState(() => _error = preview.error);
      return;
    }
    setState(() {
      _error = null;
      _preview = preview;
    });
  }

  String _errorText(AppLocalizations l10n) => switch (_error) {
    UploadRenameError.emptySearch => l10n.searchContentRequired,
    UploadRenameError.invalidPattern => l10n.invalidRegularExpression,
    UploadRenameError.noMatches => l10n.renameNoMatches,
    UploadRenameError.emptyName => l10n.renameEmptyName,
    UploadRenameError.duplicateNames => l10n.renameDuplicateNames,
    null => '',
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preview = _preview;
    if (preview != null) {
      return formDialog(
        context,
        title: Text(l10n.renamePreview),
        content: SizedBox(
          width: dialogFormWidth(context),
          height: math.min(360, MediaQuery.sizeOf(context).height * 0.52),
          child: SingleChildScrollView(
            child: DialogListGroup(
              children: [
                for (final change in preview.changes)
                  ListTile(
                    key: ValueKey('upload-rename-preview-${change.id}'),
                    title: Text('${change.originalName} → ${change.newName}'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('upload-batch-rename-back'),
            onPressed: () => setState(() => _preview = null),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('upload-batch-rename-confirm'),
            onPressed: () => Navigator.of(context).pop(preview.changes),
            child: Text(l10n.modify),
          ),
        ],
      );
    }

    return formDialog(
      context,
      title: Text(l10n.batchRename),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('upload-batch-rename-search'),
            controller: _searchController,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: errorState(
              context,
              InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.findContent,
              ),
              _error == null ? null : _errorText(l10n),
            ),
            onChanged: (_) => _clearError(),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('upload-batch-rename-replacement'),
            controller: _replaceController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: l10n.replaceWith,
            ),
            onChanged: (_) => _clearError(),
            onSubmitted: (_) => _buildPreview(),
          ),
          const SizedBox(height: 12),
          DialogListGroup(
            children: [
              CheckboxListTile(
                value: _useRegex,
                title: Text(l10n.useRegularExpression),
                onChanged: (value) {
                  setState(() {
                    _useRegex = value ?? false;
                    _error = null;
                  });
                },
              ),
              CheckboxListTile(
                value: _matchCase,
                title: Text(l10n.matchCase),
                onChanged: (value) {
                  setState(() {
                    _matchCase = value ?? false;
                    _error = null;
                  });
                },
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('upload-batch-rename-preview'),
          onPressed: _buildPreview,
          child: Text(l10n.preview),
        ),
      ],
    );
  }
}
