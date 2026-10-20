import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_info.dart';

void main() {
  test('构建时间显示：UTC 转本机时区，旧格式原样，空 / 非法原样', () {
    expect(formatBuildTimeForDisplay(''), '');
    expect(formatBuildTimeForDisplay('  '), '');
    // 早期构建没有时区标记：按本地时间理解并保持格式
    expect(
      formatBuildTimeForDisplay('2026-10-20 12:10:51'),
      '2026-10-20 12:10:51',
    );
    // CI 注入带 Z 的 UTC：显示成本机时间（这里用系统时区换算后比较）
    final local = DateTime.parse('2026-10-20T12:10:51Z').toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final expected =
        '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
    expect(formatBuildTimeForDisplay('2026-10-20T12:10:51Z'), expected);
    // 解析失败：原样显示
    expect(formatBuildTimeForDisplay('not a time'), 'not a time');
  });
}
