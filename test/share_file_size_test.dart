import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';

void main() {
  test('分享文件页：大小取 meta description，不会被页内日期带偏', () {
    // 真实页面里日期 `2026-06-22` 出现在大小之后，旧正则 `大小.+?(\d...)<`
    // 会跨行匹配到日期里的 22，导致所有文件都显示 22.0 MB。
    const html = '''
<title>Yifeng2FA_1.0.apk - 蓝奏云</title>
<meta name="description" content="大小：31.5 M" />
<div class="appinfo"><span class="appinfotime">2026-06-22</span></div>
<div class="appdown"><a href="/#1" class="appa" id="ddown">下载 ( 31.5 M )</a></div>
''';
    expect(shareFileSizeFromHtml(html), '31.5M');
  });

  test('分享文件页：没有 meta 时用下载按钮里的大小', () {
    const html = '<div class="appdown"><a>下载 ( 1.1 M )</a></div>';
    expect(shareFileSizeFromHtml(html), '1.1M');
  });

  test('分享文件页：支持 GB 单位', () {
    const html = '<meta name="description" content="大小：1.2 G" />';
    expect(shareFileSizeFromHtml(html), '1.2G');
  });

  test('分享文件页：解析不到大小返回空串', () {
    expect(shareFileSizeFromHtml('<html><body>没有大小</body></html>'), '');
  });
}
