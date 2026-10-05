import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/lanzou_link.dart';

void main() {
  test('识别带协议头的分享链接', () {
    final link = LanzouLink.parse('https://wwa.lanzoua.com/iAbCdEf');
    expect(link, isNotNull);
    expect(link!.url, 'https://wwa.lanzoua.com/iAbCdEf');
    expect(link.pwd, isNull);
  });

  test('识别链接里的访问密码', () {
    final link = LanzouLink.parse(
      '这里有个文件 https://www.lanzoue.com/ix1234 密码: 8zb9',
    );
    expect(link?.url, 'https://www.lanzoue.com/ix1234');
    expect(link?.pwd, '8zb9');
  });

  test('去掉链接结尾的中文标点', () {
    final link = LanzouLink.parse(
      '看看这个（https://www.lanzoub.com/iQ7w8e），提取码：abcd',
    );
    expect(link?.url, 'https://www.lanzoub.com/iQ7w8e');
    expect(link?.pwd, 'abcd');
  });

  test('兼容没有协议头的链接', () {
    final link = LanzouLink.parse('www.lanzouz.com/iy8888');
    expect(link?.url, 'https://www.lanzouz.com/iy8888');
  });

  test('非蓝奏云内容返回 null', () {
    expect(LanzouLink.parse('https://example.com/share'), isNull);
    expect(LanzouLink.parse('淘口令 abcdefg'), isNull);
    expect(LanzouLink.parse(''), isNull);
    expect(LanzouLink.parse(null), isNull);
  });
}
