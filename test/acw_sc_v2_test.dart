import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/acw_sc_v2.dart';

void main() {
  test('calcAcwScV2 returns a 40-char hex string for a 40-char arg1', () {
    // 真实的 arg1 是 40 位十六进制字符串
    const input = '0123456789ABCDEF0123456789ABCDEF01234567';
    final result = calcAcwScV2("var arg1='$input';");
    expect(result.length, 40);
    expect(RegExp(r'^[0-9a-f]{40}$').hasMatch(result), isTrue);
  });

  test('calcAcwScV2 returns empty string when arg1 is missing', () {
    expect(calcAcwScV2('<html>no challenge</html>'), '');
  });
}
