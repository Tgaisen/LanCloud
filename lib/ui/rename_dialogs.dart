import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/rename_rule.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'reduce_motion.dart';

/// 单个条目的名称修改。
Future<String?> showRenameDialog(
  BuildContext context, {
  required String initialName,
  String? supportingText,
  String keyPrefix = 'rename',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _SingleRenameDialog(
      initialName: initialName,
      supportingText: supportingText,
      keyPrefix: keyPrefix,
    ),
  );
}

/// 批量条目的查找替换与预览。
Future<List<RenameChange>?> showBatchRenameDialog(
  BuildContext context, {
  required List<RenameTarget> targets,
  String? supportingText,
  String keyPrefix = 'batch-rename',
}) {
  return showDialog<List<RenameChange>>(
    context: context,
    builder: (_) => _BatchRenameDialog(
      targets: targets,
      supportingText: supportingText,
      keyPrefix: keyPrefix,
    ),
  );
}

class _SingleRenameDialog extends StatefulWidget {
  const _SingleRenameDialog({
    required this.initialName,
    required this.supportingText,
    required this.keyPrefix,
  });

  final String initialName;
  final String? supportingText;
  final String keyPrefix;

  @override
  State<_SingleRenameDialog> createState() => _SingleRenameDialogState();
}

class _SingleRenameDialogState extends State<_SingleRenameDialog> {
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.supportingText case final text?) ...[
            Text(
              text,
              key: ValueKey('${widget.keyPrefix}-supporting-text'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            key: ValueKey('${widget.keyPrefix}-field'),
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: ValueKey('${widget.keyPrefix}-confirm'),
          onPressed: _submit,
          child: Text(l10n.modify),
        ),
      ],
    );
  }
}

class _BatchRenameDialog extends StatefulWidget {
  const _BatchRenameDialog({
    required this.targets,
    required this.supportingText,
    required this.keyPrefix,
  });

  final List<RenameTarget> targets;
  final String? supportingText;
  final String keyPrefix;

  @override
  State<_BatchRenameDialog> createState() => _BatchRenameDialogState();
}

class _BatchRenameDialogState extends State<_BatchRenameDialog> {
  static const _stepDuration = Duration(milliseconds: 200);

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  RenameError? _error;
  RenamePreview? _preview;
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
    final preview = BatchRenameRule(
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
    RenameError.emptySearch => l10n.searchContentRequired,
    RenameError.invalidPattern => l10n.invalidRegularExpression,
    RenameError.noMatches => l10n.renameNoMatches,
    RenameError.emptyName => l10n.renameEmptyName,
    null => '',
  };

  Widget _buildConfigContent(BuildContext context, AppLocalizations l10n) {
    final prefix = widget.keyPrefix;
    return Column(
      key: ValueKey('$prefix-config-content'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.supportingText case final text?) ...[
          Text(
            text,
            key: ValueKey('$prefix-supporting-text'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          key: ValueKey('$prefix-search'),
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
          key: ValueKey('$prefix-replacement'),
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
    );
  }

  Widget _buildPreviewContent(BuildContext context, RenamePreview preview) {
    final prefix = widget.keyPrefix;
    return ConstrainedBox(
      key: ValueKey('$prefix-preview-content'),
      constraints: BoxConstraints(
        maxHeight: math.min(360, MediaQuery.sizeOf(context).height * 0.52),
      ),
      child: SingleChildScrollView(
        key: ValueKey('$prefix-preview-list'),
        child: DialogListGroup(
          children: [
            for (final change in preview.changes)
              ListTile(
                key: ValueKey('$prefix-preview-${change.id}'),
                title: Text('${change.originalName} → ${change.newName}'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    AppLocalizations l10n,
    RenamePreview? preview,
  ) {
    final prefix = widget.keyPrefix;
    final previewing = preview != null;
    return Wrap(
      key: ValueKey(
        previewing ? '$prefix-preview-actions' : '$prefix-config-actions',
      ),
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 4,
      children: previewing
          ? [
              TextButton(
                key: ValueKey('$prefix-back'),
                onPressed: () => setState(() => _preview = null),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                key: ValueKey('$prefix-confirm'),
                onPressed: () => Navigator.of(context).pop(preview.changes),
                child: Text(l10n.modify),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                key: ValueKey('$prefix-preview'),
                onPressed: _buildPreview,
                child: Text(l10n.preview),
              ),
            ],
    );
  }

  Widget _stepTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.02, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  Widget _stepLayout(Widget? current, List<Widget> previous) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [...previous, ?current],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preview = _preview;
    final duration = reduceMotionOf(context) ? Duration.zero : _stepDuration;
    final prefix = widget.keyPrefix;
    return formDialog(
      context,
      title: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: _stepTransition,
        layoutBuilder: _stepLayout,
        child: SizedBox(
          key: ValueKey(
            preview == null ? '$prefix-config-title' : '$prefix-preview-title',
          ),
          width: double.infinity,
          child: Text(
            preview == null ? l10n.batchRename : l10n.renamePreview,
            textAlign: TextAlign.start,
          ),
        ),
      ),
      content: AnimatedSize(
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: _stepTransition,
          layoutBuilder: _stepLayout,
          child: preview == null
              ? _buildConfigContent(context, l10n)
              : _buildPreviewContent(context, preview),
        ),
      ),
      actions: [
        AnimatedSwitcher(
          duration: duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: _stepTransition,
          layoutBuilder: _stepLayout,
          child: _buildActions(context, l10n, preview),
        ),
      ],
    );
  }
}
