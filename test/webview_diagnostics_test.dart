import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/webview_diagnostics.dart';

void main() {
  test('WebView 日志只记录 host，不写路径、查询参数或分享密码', () {
    final lines = <String>[];
    final diagnostics = WebViewDiagnostics(
      name: 'web-page:分享',
      writer: lines.add,
    );

    diagnostics.opened(
      'https://example.lanzoua.com/file/path?pwd=secret#fragment',
    );

    expect(lines, ['web-page:分享: opened endpoint=example.lanzoua.com']);
    expect(lines.single, isNot(contains('/file/path')));
    expect(lines.single, isNot(contains('secret')));
    expect(lines.single, isNot(contains('fragment')));
  });

  test('WebView 进度只在 25/50/75/100 里程碑各记录一次', () {
    final lines = <String>[];
    final diagnostics = WebViewDiagnostics(
      name: 'web-login',
      writer: lines.add,
    );

    for (final progress in [1, 24, 25, 26, 50, 74, 75, 99, 100, 100]) {
      diagnostics.progress(progress);
    }

    expect(lines, [
      'web-login: progress=25%',
      'web-login: progress=50%',
      'web-login: progress=75%',
      'web-login: progress=100%',
    ]);
  });

  test('WebView 事件包含创建、加载、结束和销毁', () {
    final lines = <String>[];
    final diagnostics = WebViewDiagnostics(
      name: 'web-page:个人中心',
      writer: lines.add,
    );

    diagnostics.opened('https://pc.woozooo.com/mydisk.php');
    diagnostics.created();
    diagnostics.loadRequested('https://pc.woozooo.com/mydisk.php');
    diagnostics.loadStarted('https://pc.woozooo.com/mydisk.php');
    diagnostics.loadStopped('https://pc.woozooo.com/mydisk.php');
    diagnostics.closed();

    expect(lines, [
      'web-page:个人中心: opened endpoint=pc.woozooo.com',
      'web-page:个人中心: created',
      'web-page:个人中心: load-requested endpoint=pc.woozooo.com',
      'web-page:个人中心: load-started endpoint=pc.woozooo.com',
      'web-page:个人中心: load-stopped endpoint=pc.woozooo.com',
      'web-page:个人中心: closed',
    ]);
  });
}
