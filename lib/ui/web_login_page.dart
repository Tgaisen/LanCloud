import 'dart:async';

import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../core/api/lanzou_client.dart';
import '../core/app_controller.dart';
import '../core/platform_support.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';
import '../l10n/l10n.dart';

/// 用内嵌浏览器完成登录，登录成功后读取系统 Cookie 并保存账号。
class WebLoginPage extends StatefulWidget {
  const WebLoginPage({super.key});

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  static const _loginUrl = 'https://pc.woozooo.com/account.php';

  bool _checking = false;
  bool _done = false;
  double _progress = 0;
  String? _error;

  Future<void> _tryCapture() async {
    if (_checking || _done) return;
    final app = context.read<AppController>();
    setState(() {
      _checking = true;
      _error = null;
    });
    // 检测登录时显示与「解析中」同款的进度弹窗
    unawaited(showLoadingDialog(context, context.l10n.checking));
    var success = false;
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(_loginUrl),
      );
      final map = <String, String>{};
      for (final cookie in cookies) {
        if (cookie.name.isNotEmpty && cookie.value != null) {
          map[cookie.name] = cookie.value!;
        }
      }
      final header = map.entries.map((e) => '${e.key}=${e.value}').join('; ');
      if ((map['ylogin'] ?? '').isEmpty ||
          (map['phpdisk_info'] ?? '').isEmpty) {
        setState(() {
          _checking = false;
          _error = context.l10n.noLoginDetected;
        });
        return;
      }
      await app.addAccountFromCookie(header);
      if (!mounted) return;
      setState(() {
        _done = true;
        _checking = false;
      });
      success = true;
    } on CookieFormatException {
      setState(() {
        _checking = false;
        _error = context.l10n.cookieMissingYlogin;
      });
    } on CookieInvalidException {
      setState(() {
        _checking = false;
        _error = context.l10n.cookieInvalid;
      });
    } on LanzouException catch (e) {
      setState(() {
        _checking = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _checking = false;
        _error = '$e';
      });
    } finally {
      // 先关掉进度弹窗，再决定是否关闭本页
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (success && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.webLogin),
        leading: const AppBarBackButton(),
        actions: [
          TextButton(
            onPressed: _checking ? null : _tryCapture,
            child: Text(_checking ? l10n.checking : l10n.finishLogin),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: scheme.secondaryContainer,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text(
              l10n.webLoginGuide,
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
          if (_progress < 1) M3eLinearProgressIndicator(value: _progress),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_loginUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                useHybridComposition: true,
                // 移动端伪装成手机浏览器，拿到的是移动版登录页；
                // 桌面端（WebView2）用默认 UA，避免被当成手机渲染。
                userAgent: PlatformSupport.isMobile
                    ? 'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
                          'AppleWebKit/537.36 (KHTML, like Gecko) '
                          'Chrome/124.0.0.0 Mobile Safari/537.36'
                    : null,
              ),
              onProgressChanged: (controller, progress) {
                setState(() => _progress = progress / 100);
              },
              onLoadStop: (controller, url) async {
                final target = url?.toString() ?? '';
                if (target.contains('mydisk')) {
                  await _tryCapture();
                }
              },
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: scheme.errorContainer,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: scheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
