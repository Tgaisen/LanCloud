import 'dart:typed_data';

import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/external_link.dart';
import '../core/platform_support.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';

/// 统一 WebView 页：个人中心与分享页在应用内打开，
/// 通过 CookieManager 注入账号 Cookie 免二次登录。
///
/// 进出转场避免平台视图卡顿（WebView 跟随转场逐帧移动/缩放很贵）：
/// 1. 进入：push 动画期间 WebView 不绘制（照常创建、开始加载），
///    动画结束后再显示；
/// 2. 退出：先给 WebView 截一张静态帧顶替它，再开始 pop——
///    退出动画里只剩一张图片。
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

  /// push 转场是否已结束：结束前 WebView 只加载、不参与绘制。
  bool _entered = false;

  /// 退出时顶替 WebView 的静态帧；非空时 WebView 从画面里摘掉。
  Uint8List? _snapshot;

  /// 防止重复触发「截图 → pop」。
  bool _popping = false;

  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    _injectCookie();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!identical(route, _route)) {
      _route?.animation?.removeListener(_handleRouteAnimation);
      _route = route;
      _route?.animation?.addListener(_handleRouteAnimation);
      _handleRouteAnimation();
    }
  }

  @override
  void dispose() {
    _route?.animation?.removeListener(_handleRouteAnimation);
    super.dispose();
  }

  void _handleRouteAnimation() {
    if (_entered) return;
    final animation = _route?.animation;
    if (animation == null || animation.value >= 1) {
      if (mounted) setState(() => _entered = true);
    }
  }

  /// 返回：先截当前帧，用静态帧顶替 WebView，再 pop。
  /// 截图失败时保持 WebView 显示，转场退化成原样（会卡一点，但不会白屏）。
  Future<void> _popWithSnapshot() async {
    if (_popping) return;
    _popping = true;
    final bytes = await _controller?.takeScreenshot(
      screenshotConfiguration: ScreenshotConfiguration(
        compressFormat: CompressFormat.JPEG,
        quality: 80,
      ),
    );
    if (!mounted) return;
    if (bytes != null) setState(() => _snapshot = bytes);
    if (mounted) Navigator.of(context).pop();
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
    return PopScope(
      // 退出统一走 [_popWithSnapshot]（系统返回 / 预测性返回也走这里）：
      // 代价是这个页面没有预测性返回的预览动画，换退出转场的平滑
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _popWithSnapshot();
      },
      child: Scaffold(
        // 大屏（横屏 / 平板）：顶栏留在 navigation area 的 surfaceContainer 上，
        // 内容套 MD3E 圆角 surface 卡片；小屏保持整页铺满
        backgroundColor: large
            ? Theme.of(context).colorScheme.surfaceContainer
            : null,
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
              onPressed: () => openExternalUrl(Uri.parse(widget.url)),
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
                // 转场期间把平台视图摘出画面（Offstage 仍会布局它、只是不绘制）
                Offstage(
                  offstage: !_entered || _snapshot != null,
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      supportZoom: true,
                      // Android 10+ 才启用混合合成（官方：更低版本动画掉帧）
                      useHybridComposition:
                          PlatformSupport.useHybridComposition,
                    ),
                    onWebViewCreated: (controller) => _controller = controller,
                    onProgressChanged: (controller, progress) {
                      if (mounted) setState(() => _progress = progress / 100);
                    },
                  ),
                ),
                // 退出期间用静态帧顶替 WebView
                if (_snapshot != null)
                  Positioned.fill(
                    child: Image.memory(
                      _snapshot!,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                  ),
                if (_progress < 1 && _snapshot == null)
                  Align(
                    alignment: Alignment.topCenter,
                    child: M3eLinearProgressIndicator(value: _progress),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
