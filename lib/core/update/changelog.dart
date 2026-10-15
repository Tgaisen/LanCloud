/// 把 Release 正文转成弹窗里逐行显示的更新日志。
///
/// 正文约定（见 docs/releases/TEMPLATE.md）：先是 `## 更新日志` 小节（列表
/// 项），随后是 Full Changelog 引用行和固定的 `## 下载选择` 小节。弹窗只
/// 展示更新日志本身：
///
/// - 从「更新日志 / 更新说明 / Changelog」标题行开始，到下一个小节标题为止；
/// - 引用行（`>` 开头）不展示——那是 Full Changelog 链接，详情入口由弹窗
///   自己提供；
/// - `- ` / `* ` / `• ` 列表项转成 `• ` 前缀的行，`**粗体**` 标记剥掉，
///   `[文字](链接)` 只留文字；其余行原样保留。
///
/// 截取失败（正文里没有那个标题）时直接返回整段正文——以后发布说明改成
/// 只含列表项时也照样能显示（见用户需求：截取失败就直接显示）。
List<String> changelogLines(String body) {
  final lines = body.replaceAll('\r\n', '\n').split('\n');
  final section = RegExp(
    r'^\s{0,3}#{1,6}\s*(更新日志|更新说明|changelog)\s*$',
    caseSensitive: false,
  );
  final heading = RegExp(r'^\s{0,3}#{1,6}\s+\S');

  var start = -1;
  var end = lines.length;
  for (var i = 0; i < lines.length; i++) {
    if (start < 0) {
      if (section.hasMatch(lines[i])) start = i + 1;
      continue;
    }
    if (heading.hasMatch(lines[i])) {
      end = i;
      break;
    }
  }
  final slice = start >= 0 ? lines.sublist(start, end) : lines;

  final out = <String>[];
  final item = RegExp(r'^\s*[-*•]\s+(.*)$');
  for (final line in slice) {
    final trimmed = line.trim();
    if (trimmed.startsWith('>')) continue;
    if (trimmed.isEmpty) {
      if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
      continue;
    }
    final match = item.firstMatch(trimmed);
    final text = _plainInline(match?.group(1)?.trim() ?? trimmed);
    out.add(match == null ? text : '• $text');
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out;
}

/// 去掉行内的 markdown 标记：`**加粗**` 只留文字，`[文字](链接)` 只留文字。
String _plainInline(String text) {
  var out = text.replaceAllMapped(
    RegExp(r'\*\*(.+?)\*\*'),
    (match) => match.group(1)!,
  );
  out = out.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (match) => match.group(1)!,
  );
  return out.trim();
}
