/// 名称搜索的三个可选增强条件。
enum SearchOption { matchCase, wholeWord, regex }

/// 网盘、收藏和分享文件夹共用的搜索选项。
final class SearchOptions {
  const SearchOptions({
    this.matchCase = false,
    this.wholeWord = false,
    this.regex = false,
  });

  static const disabled = SearchOptions();

  final bool matchCase;
  final bool wholeWord;
  final bool regex;

  Set<SearchOption> get enabled => {
    if (matchCase) SearchOption.matchCase,
    if (wholeWord) SearchOption.wholeWord,
    if (regex) SearchOption.regex,
  };

  SearchOptions copyWith({bool? matchCase, bool? wholeWord, bool? regex}) =>
      SearchOptions(
        matchCase: matchCase ?? this.matchCase,
        wholeWord: wholeWord ?? this.wholeWord,
        regex: regex ?? this.regex,
      );

  factory SearchOptions.fromEnabled(Set<SearchOption> enabled) => SearchOptions(
    matchCase: enabled.contains(SearchOption.matchCase),
    wholeWord: enabled.contains(SearchOption.wholeWord),
    regex: enabled.contains(SearchOption.regex),
  );

  @override
  bool operator ==(Object other) =>
      other is SearchOptions &&
      other.matchCase == matchCase &&
      other.wholeWord == wholeWord &&
      other.regex == regex;

  @override
  int get hashCode => Object.hash(matchCase, wholeWord, regex);
}

/// 编译后的搜索条件；无效正则不会抛异常，而是返回空匹配。
final class SearchQuery {
  SearchQuery._({
    required this.isEmpty,
    required this.isValid,
    this._expression,
    this._wholeWord = false,
  });

  factory SearchQuery.parse(String rawQuery, SearchOptions options) {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return SearchQuery._(isEmpty: true, isValid: true);
    }
    try {
      final expression = RegExp(
        options.regex ? query : RegExp.escape(query),
        caseSensitive: options.matchCase,
        unicode: true,
      );
      return SearchQuery._(
        isEmpty: false,
        isValid: true,
        expression: expression,
        wholeWord: options.wholeWord,
      );
    } on FormatException {
      return SearchQuery._(isEmpty: false, isValid: false);
    }
  }

  final bool isEmpty;
  final bool isValid;
  final RegExp? _expression;
  final bool _wholeWord;

  bool matches(String value) {
    if (isEmpty) return true;
    final expression = _expression;
    if (!isValid || expression == null) return false;
    if (!_wholeWord) return expression.hasMatch(value);
    for (final match in expression.allMatches(value)) {
      if (_hasWordBoundaries(value, match.start, match.end)) return true;
    }
    return false;
  }
}

final _wordCharacter = RegExp(r'[\p{L}\p{N}_]', unicode: true);

bool _hasWordBoundaries(String value, int start, int end) {
  if (start > 0 && _wordCharacter.hasMatch(value.substring(start - 1, start))) {
    return false;
  }
  if (end < value.length &&
      _wordCharacter.hasMatch(value.substring(end, end + 1))) {
    return false;
  }
  return true;
}
