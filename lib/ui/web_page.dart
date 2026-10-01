import 'package:flutter/material.dart' hide Icons;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import 'app_icons.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
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
      body: Stack(
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
    );
  }
}
