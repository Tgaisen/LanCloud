import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/data/account_store.dart';

/// 网页版个人中心（myfile.php?item=1）里的昵称与用户等级。
void main() {
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
