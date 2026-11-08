import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';

class _PageClient extends LanzouClient {
  _PageClient(this.html, {this.pages = const {}}) : super(uid: '0');

  final String html;
  final Map<String, String> pages;
  final List<String> requests = [];

  @override
  Future<String> fetchSharePage(String url, {String? referer}) async {
    requests.add(url);
    return pages[url] ?? html;
  }
}

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

  test('分享详情只解析元信息，不进入直链流程', () async {
    final client = _PageClient('''
<title>百度地图_15.12.22.apk - 蓝奏云</title>
<meta name="description" content="文件大小：91.5 M" />
<span class="p7">上传时间：</span>6 天前<br>
<span class="p7">分享用户：</span><font>用户</font><br>
<div class="n_box_des">文件说明</div>
''');

    final details = await client.fetchFileShareDetails(
      'https://example.com/demo',
    );

    expect(details.name, '百度地图_15.12.22.apk');
    expect(details.size, '91.5M');
    expect(details.time, '6 天前');
    expect(details.desc, '文件说明');
    expect(details.sharer, '用户');
    expect(details.requiresPassword, isFalse);
    expect(client.requests, ['https://example.com/demo']);
  });

  test('分享详情在缺少提取码时仍可返回基本信息，直链再校验密码', () async {
    final client = _PageClient('''
<html><body>
<title>文件</title>
<meta name="description" content="文件大小：24.1 K" />
<span class="user-name">用户</span>
<span class="n_file_infos">前天22:45</span>
<span class="n_file_infos">压缩文件</span>
<div id="passwddiv"></div>
</body></html>
''');

    final details = await client.fetchFileShareDetails(
      'https://example.com/secret',
    );

    // 密码页首屏没有真实文件名：不能把 URL 末段兜底成文件名。
    expect(details.name, isEmpty);
    expect(details.size, '24.1K');
    expect(details.time, '前天22:45');
    expect(details.sharer, '用户');
    expect(details.requiresPassword, isTrue);
    expect(client.requests, ['https://example.com/secret']);
  });

  test('分享者兼容普通文件页的明确标签', () {
    expect(
      shareSharerFromHtml('<span class="p7">上传者：</span><span>分享者乙</span>'),
      '分享者乙',
    );
    expect(shareSharerFromHtml('<div class="meta">作者：分享者丙</div>'), '分享者丙');
    expect(shareSharerFromHtml('<div>上传时间：2026-06-22</div>'), '');
    expect(
      shareFileTimeFromHtml(
        '<span class="n_file_infos">2026-10-04</span>'
        '<span class="n_file_infos">压缩文件</span>',
      ),
      '2026-10-04',
    );
  });

  test('分享详情会用 iframe 中的分享者补全普通文件模板', () async {
    final client = _PageClient(
      '<title>报告.pdf - 蓝奏云</title><iframe src="/frame"></iframe>',
      pages: {
        'https://example.com/frame': '<title>报告.pdf</title><span class="p7">上传者：</span><span>分享者乙</span>',
      },
    );

    final details = await client.fetchFileShareDetails(
      'https://example.com/demo',
    );

    expect(details.sharer, '分享者乙');
    expect(client.requests, [
      'https://example.com/demo',
      'https://example.com/frame',
    ]);
  });
}
