/// 批量重命名的一个输入条目。
class RenameTarget {
  const RenameTarget({required this.id, required this.name});

  final String id;
  final String name;
}

/// 名称实际发生变化的条目。
class RenameChange {
  const RenameChange({
    required this.id,
    required this.originalName,
    required this.newName,
  });

  final String id;
  final String originalName;
  final String newName;
}

enum RenameError { emptySearch, invalidPattern, noMatches, emptyName }

/// 批量重命名预览；错误存在时不能应用。
class RenamePreview {
  const RenamePreview._({required this.changes, this.error});

  const RenamePreview.ready(List<RenameChange> changes)
    : this._(changes: changes);

  const RenamePreview.failure(RenameError error)
    : this._(changes: const <RenameChange>[], error: error);

  final List<RenameChange> changes;
  final RenameError? error;

  bool get canApply => error == null && changes.isNotEmpty;
}

/// PowerRename 风格的文本替换规则：默认替换全部匹配项。
class BatchRenameRule {
  const BatchRenameRule({
    required this.search,
    required this.replacement,
    required this.useRegex,
    required this.matchCase,
  });

  final String search;
  final String replacement;
  final bool useRegex;
  final bool matchCase;

  RenamePreview preview(Iterable<RenameTarget> targets) {
    if (search.isEmpty) {
      return const RenamePreview.failure(RenameError.emptySearch);
    }

    RegExp? expression;
    if (useRegex) {
      try {
        expression = RegExp(search, caseSensitive: matchCase);
      } on FormatException {
        return const RenamePreview.failure(RenameError.invalidPattern);
      }
    }

    final targetList = targets.toList(growable: false);
    final changes = <RenameChange>[];
    for (final target in targetList) {
      final newName = _replace(target.name, expression);
      if (newName.trim().isEmpty) {
        return const RenamePreview.failure(RenameError.emptyName);
      }
      if (newName != target.name) {
        changes.add(
          RenameChange(
            id: target.id,
            originalName: target.name,
            newName: newName,
          ),
        );
      }
    }

    if (changes.isEmpty) {
      return const RenamePreview.failure(RenameError.noMatches);
    }
    return RenamePreview.ready(changes);
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
