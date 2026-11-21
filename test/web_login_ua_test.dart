import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/platform_capabilities.dart';
import 'package:lancloud/ui/web_login_page.dart';

void main() {
  test('Web 登录 UA 应该跟随 usesMobileWebUserAgent', () {
    const mobileUa =
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Mobile Safari/537.36';

    expect(webLoginUserAgentFor(PlatformCapabilities.android), mobileUa);
    expect(webLoginUserAgentFor(PlatformCapabilities.ios), mobileUa);
    expect(webLoginUserAgentFor(PlatformCapabilities.windows), isNull);
    expect(webLoginUserAgentFor(PlatformCapabilities.macOS), isNull);
    expect(webLoginUserAgentFor(PlatformCapabilities.linux), isNull);
    expect(webLoginUserAgentFor(PlatformCapabilities.unsupported), isNull);
  });
}
