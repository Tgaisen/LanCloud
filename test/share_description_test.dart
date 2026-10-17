import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';

void main() {
  test('下载页：.mdo 是上传者写的简介时取出来', () {
    const html = '''
<div class="mad"></div>
<div class="mdo">
这是简介 abc</div>
''';
    expect(tpDescriptionFromHtml(html), '这是简介 abc');
  });

  test('下载页：系统默认的「下载说明」不当作简介', () {
    // 没写简介的文件，.mdo 里是这段固定的下载提示；当成简介会显示得很奇怪
    const html = '''
<div class="mdo">
<span>下载说明:</span>
<span>1,建议使用最快的网络比如电信，联通，移动等。</span>
<span>2,如果发现文件不能下载可以给我们反馈。</span>
</div>
''';
    expect(tpDescriptionFromHtml(html), isNull);
  });

  test('下载页：没有 .mdo 或内容为空时返回 null', () {
    expect(tpDescriptionFromHtml('<html></html>'), isNull);
    expect(tpDescriptionFromHtml('<div class="mdo">\n</div>'), isNull);
  });

  test('下载页：简介保留换行并去掉标签', () {
    const html = '<div class="mdo">第一行<br>第二行</div>';
    expect(tpDescriptionFromHtml(html), '第一行\n第二行');
  });

  test('PC 分享页：文件描述表格里的简介（exe 模板）', () {
    // 取自 https://yxxdz.lanzoue.com/i31xx4b4busj 的实际结构
    const html = '''
<span class="p7">文件大小：</span>18.5 K<br>
<span class="p7">运行系统：</span>Win桌面<br>
<span class="p7">文件描述：</span><br>
这是简介 abc	  </td>
''';
    expect(pcShareDescriptionFromHtml(html), '这是简介 abc');
  });

  test('PC 分享页：没有描述字段或内容为空时返回 null', () {
    expect(pcShareDescriptionFromHtml('<span>没有</span>'), isNull);
    expect(
      pcShareDescriptionFromHtml('<span class="p7">文件描述：</span><br>   </td>'),
      isNull,
    );
  });
}
