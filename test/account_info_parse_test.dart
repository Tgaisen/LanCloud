import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/upload_policy.dart';

/// 新版个人中心的上传规则，以及旧版昵称 / 等级解析兼容。
void main() {
  test('新版个人中心从 utcn 地址提取用户名', () {
    const html = '''
      function utcn(){
        url ='https://yxxdz.lanzoue.com/u/excited233?t2';
      }
    ''';
    expect(LanzouClient.parseProfileNickname(html), 'excited233');
  });

  test('上传限制从网页读取，格式异常时回退 100 MB', () {
    const html = '单个文件大小<span>2G</span></div>';
    expect(LanzouClient.parseUploadLimitBytes(html), 2 * 1024 * 1024 * 1024);
    expect(
      LanzouClient.parseUploadLimitBytes('单个文件大小<span>未知</span>'),
      kFallbackUploadLimitBytes,
    );
  });

  test('允许上传类型从 mf2 区块读取，缺失时使用完整内置列表', () {
    const html = '''
      <div class="mf">
        <div class="mf1">允许上传类型: </div>
        <div class="mf2">doc,docx,zip<br>apk,7z,png</div>
      </div>
    ''';
    expect(
      LanzouClient.parseAllowedUploadExtensions(html),
      containsAll(<String>['doc', 'docx', 'zip', 'apk', '7z', 'png']),
    );
    expect(
      LanzouClient.parseAllowedUploadExtensions('<div></div>'),
      containsAll(<String>['brushset', 'mobileconfig', 'imazingapp']),
    );
  });

  test('昵称旁边的等级标记：普通用户是「普」', () {
    const html =
        '<div class="c_topr">土豆<span class="ulv1">普</span><a>退出</a></div>';
    final info = LanzouClient.parseAccountInfoHtml(html);
    expect(info.nickname, '土豆');
    expect(info.level, '普');
  });

  test('会员等级原样取出（例如「白」）', () {
    const html = '<div class="c_topr">土豆<span class="ulv2">白</span></div>';
    expect(LanzouClient.parseAccountInfoHtml(html).level, '白');
  });

  test('等级标记只认顶栏那块，页面别处的 ulv 不算', () {
    const html =
        '<span class="ulv9">别处</span>'
        '<div class="c_topr">土豆<span class="ulv1">普</span></div>';
    expect(LanzouClient.parseAccountInfoHtml(html).level, '普');
  });

  test('顶栏没有用户名时退回 shownames', () {
    const html =
        '<input id="shownames" value="发布者">'
        '<span class="ulv1">普</span>';
    final info = LanzouClient.parseAccountInfoHtml(html);
    expect(info.nickname, '发布者');
    expect(info.level, '普');
  });

  test('等级标记取不到时为空串（界面按「普」处理）', () {
    const html = '<div class="c_topr">土豆<span class="other">x</span></div>';
    expect(LanzouClient.parseAccountInfoHtml(html).level, isEmpty);
  });

  test('账号等级为空 = 普通用户：显示「普」且算免费账号', () {
    final account = Account(uid: '556911', cookie: 'c');
    expect(account.levelLabel, '普');
    expect(account.isFreeTier, isTrue);
    account.level = '白';
    expect(account.levelLabel, '白');
    expect(account.isFreeTier, isFalse);
  });
}
