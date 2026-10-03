/// 蓝奏云分享链接解析：剪贴板、扫码结果、系统分享、外部打开都走这里。
class LanzouLink {
  const LanzouLink(this.url, {this.pwd});

  /// 分享地址（带 https:// 前缀）。
  final String url;

  /// 访问密码（没有则为 null）。
  final String? pwd;

  /// URL 里允许出现的字符（RFC 3986），避免把紧跟链接的中文一起吞进来。
  static const _urlChars = r"[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]";

  /// 带协议头的分享链接，例如 https://wwa.lanzoua.com/iXXXX
  static final RegExp _withScheme = RegExp(
    'https?://$_urlChars*lanzou[a-z]*\\.(?:com|cn)$_urlChars*',
    caseSensitive: false,
  );

  /// 复制时常常丢掉协议头：www.lanzoua.com/iXXXX
  static final RegExp _withoutScheme = RegExp(
    '(?:^|[\\s(（【「])(www\\.lanzou[a-z]*\\.(?:com|cn)$_urlChars*)',
    caseSensitive: false,
  );

  /// 文案里链接后面常见的标点，解析时去掉。
  static const _trailing = '),.。，;；、》】》」”"\'’!！?？';

  /// 访问密码：「密码: abcd」「提取码：abcd」「pwd=abcd」等写法。
  static final RegExp _pwd = RegExp(
    r'(?<![A-Za-z0-9])(?:密码|密\s*码|提取码|訪問密碼|访问密码|pwd|password)'
    r'\s*[:：=]?\s*([0-9A-Za-z]{1,12})',
    caseSensitive: false,
  );

  /// 从任意文本里提取分享链接与密码；不是蓝奏云链接时返回 null。
  static LanzouLink? parse(String? text) {
    final raw = text?.trim();
    if (raw == null || raw.isEmpty) return null;

    var url = _withScheme.firstMatch(raw)?.group(0);
    final bare = url == null ? _withoutScheme.firstMatch(raw) : null;
    if (bare != null) url = 'https://${bare.group(1)}';
    if (url == null) return null;

    var clean = url;
    while (clean.isNotEmpty && _trailing.contains(clean[clean.length - 1])) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.isEmpty) return null;
    return LanzouLink(clean, pwd: extractPwd(raw));
  }

  /// 提取访问密码：[extract] 时返回 null。
  static String? extractPwd(String text) {
    final match = _pwd.firstMatch(text);
    final pwd = match?.group(1)?.trim();
    return (pwd == null || pwd.isEmpty) ? null : pwd;
  }
}
