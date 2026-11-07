/// 批量重命名的一个输入任务。
class UploadRenameTarget {
  const UploadRenameTarget({required this.id, required this.name});

  final String id;
  final String name;
}

/// 名称实际发生变化的任务。
class UploadRenameChange {
  const UploadRenameChange({
    required this.id,
    required this.originalName,
    required this.newName,
  });

  final String id;
  final String originalName;
  final String newName;
}

enum UploadRenameError {
  emptySearch,
  invalidPattern,
  noMatches,
  emptyName,
  duplicateNames,
}

/// 批量重命名预览；错误存在时不能应用。
class UploadRenamePreview {
  const UploadRenamePreview._({required this.changes, this.error});

  const UploadRenamePreview.ready(List<UploadRenameChange> changes)
    : this._(changes: changes);

  const UploadRenamePreview.failure(UploadRenameError error)
    : this._(changes: const <UploadRenameChange>[], error: error);

  final List<UploadRenameChange> changes;
  final UploadRenameError? error;

  bool get canApply => error == null && changes.isNotEmpty;
}

/// PowerRename 风格的文本替换规则：默认替换全部匹配项。
class UploadRenameRule {
  const UploadRenameRule({
    required this.search,
    required this.replacement,
    required this.useRegex,
    required this.matchCase,
  });

  final String search;
  final String replacement;
  final bool useRegex;
  final bool matchCase;

  UploadRenamePreview preview(Iterable<UploadRenameTarget> targets) {
    if (search.isEmpty) {
      return const UploadRenamePreview.failure(UploadRenameError.emptySearch);
    }

    RegExp? expression;
    if (useRegex) {
      try {
        expression = RegExp(search, caseSensitive: matchCase);
      } on FormatException {
        return const UploadRenamePreview.failure(
          UploadRenameError.invalidPattern,
        );
      }
    }

    final targetList = targets.toList(growable: false);
    final nameCounts = <String, int>{};
    final changes = <UploadRenameChange>[];
    for (final target in targetList) {
      final newName = _replace(target.name, expression);
      if (newName.trim().isEmpty) {
        return const UploadRenamePreview.failure(UploadRenameError.emptyName);
      }
      final normalized = newName.toLowerCase();
      nameCounts.update(normalized, (count) => count + 1, ifAbsent: () => 1);
      if (newName != target.name) {
        changes.add(
          UploadRenameChange(
            id: target.id,
            originalName: target.name,
            newName: newName,
          ),
        );
      }
    }

    if (changes.isEmpty) {
      return const UploadRenamePreview.failure(UploadRenameError.noMatches);
    }
    if (changes.any(
      (change) => (nameCounts[change.newName.toLowerCase()] ?? 0) > 1,
    )) {
      return const UploadRenamePreview.failure(
        UploadRenameError.duplicateNames,
      );
    }
    return UploadRenamePreview.ready(changes);
  }

  String _replace(String name, RegExp? expression) {
    if (useRegex) {
      return name.replaceAllMapped(
        expression!,
        (match) => _expandCaptures(replacement, match),
      );
    }
    if (matchCase) return name.replaceAll(search, replacement);
    return name.replaceAllMapped(
      RegExp(RegExp.escape(search), caseSensitive: false),
      (_) => replacement,
    );
  }

  String _expandCaptures(String replacement, Match match) {
    return replacement.replaceAllMapped(RegExp(r'\$(\d+)'), (reference) {
      final index = int.tryParse(reference.group(1) ?? '');
      if (index == null || index >= match.groupCount + 1) {
        return reference.group(0)!;
      }
      return match.group(index) ?? '';
    });
  }
}
