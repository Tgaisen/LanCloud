import 'package:flutter/material.dart' hide Icons;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';

/// 统一 WebView 页：个人中心与分享页在应用内打开，
/// 通过 CookieManager 注入账号 Cookie 免二次登录。
class WebPage extends StatefulWidget {
  const WebPage({
    super.key,
    required this.title,
    required this.url,
    this.cookie,
  });

  final String title;
  final String url;
  final String? cookie;

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  InAppWebViewController? _controller;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _injectCookie();
  }

  Future<void> _injectCookie() async {
    final cookie = widget.cookie;
    if (cookie == null || cookie.isEmpty) return;
    final uri = WebUri(widget.url);
    for (final part in cookie.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final name = part.substring(0, i).trim();
      final value = part.substring(i + 1).trim();
      if (name.isEmpty) continue;
      await CookieManager.instance().setCookie(
        url: uri,
        name: name,
        value: value,
        isSecure: uri.scheme == 'https',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final large = isLargeLayout(context);
    return Scaffold(
      // 大屏（横屏 / 平板）：顶栏留在 navigation area 的 surfaceContainer 上，
      // 内容套 MD3E 圆角 surface 卡片；小屏保持整页铺满
      backgroundColor:
          large ? Theme.of(context).colorScheme.surfaceContainer : null,
      appBar: AppBar(
        backgroundColor: large ? Colors.transparent : null,
        scrolledUnderElevation: 0,
        title: Text(widget.title),
        leading: const AppBarBackButton(),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller?.reload(),
          ),
          IconButton(
            tooltip: l10n.openLink,
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(
              Uri.parse(widget.url),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
      body: Md3eBodyCard(
        // WebView 是不透明内容，裁到卡片圆角里
        clipContent: true,
        // 小屏：正文区整体让开左右挖孔 / 侧边导航栏（大屏时卡片已经让过，
        // 这里的 inset 会被卡片清成 0，不会二次让位）
        child: BodySideInset(
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  supportZoom: true,
                  useHybridComposition: true,
                ),
                onWebViewCreated: (controller) => _controller = controller,
                onProgressChanged: (controller, progress) {
                  if (mounted) setState(() => _progress = progress / 100);
                },
              ),
              if (_progress < 1)
                Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
