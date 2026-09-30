/// 蓝奏云分享页人机校验：从挑战页面计算 acw_sc__v2 cookie。
String calcAcwScV2(String html) {
  final m = RegExp(r"arg1='([0-9A-Za-z]+)'").firstMatch(html);
  if (m == null) return '';
  return _hexXor(_unsbox(m.group(1)!), '3000176000856006061501533003690027800375');
}

String _unsbox(String input) {
  const v1 = [
    15, 35, 29, 24, 33, 16, 1, 38, 10, 9, 19, 31, 40, 27, 22, 23, 25, 13, 6,
    11, 39, 18, 20, 8, 14, 21, 32, 26, 2, 30, 7, 4, 17, 5, 3, 28, 34, 37, 12,
    36,
  ];
  final v2 = List<String>.filled(v1.length, '');
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    for (var j = 0; j < v1.length; j++) {
      if (v1[j] == i + 1) v2[j] = ch;
    }
  }
  return v2.join();
}

String _hexXor(String a, String b) {
  final buf = StringBuffer();
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i + 1 < n; i += 2) {
    final x = int.parse(a.substring(i, i + 2), radix: 16);
    final y = int.parse(b.substring(i, i + 2), radix: 16);
    buf.write(((x ^ y) & 0xFF).toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}
