import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'platform_support.dart';

const MethodChannel _channel = MethodChannel('lancloud/external_link');

typedef CustomTabLauncher = Future<bool> Function(Uri url);
typedef ExternalLinkLauncher = Future<bool> Function(Uri url);

/// 外部网页打开动作的窄接口。
abstract interface class ExternalLinkGateway {
  Future<bool> open(Uri url);
}

/// Android：优先 Custom Tabs，原生判定不可用时回退默认浏览器。
final class AndroidCustomTabExternalLinkGateway implements ExternalLinkGateway {
  AndroidCustomTabExternalLinkGateway({
    CustomTabLauncher? openCustomTab,
    ExternalLinkLauncher? launchExternal,
  }) : _openCustomTab = openCustomTab ?? _invokeCustomTab,
       _launchExternal = launchExternal ?? _launchExternalBrowser;

  final CustomTabLauncher _openCustomTab;
  final ExternalLinkLauncher _launchExternal;

  @override
  Future<bool> open(Uri url) async {
    if (await _openCustomTab(url)) return true;
    return _launchExternal(url);
  }
}

/// 非 Android：直接交给系统默认程序打开。
final class ExternalBrowserLinkGateway implements ExternalLinkGateway {
  ExternalBrowserLinkGateway({ExternalLinkLauncher? launchExternal})
    : _launchExternal = launchExternal ?? _launchExternalBrowser;

  final ExternalLinkLauncher _launchExternal;

  @override
  Future<bool> open(Uri url) => _launchExternal(url);
}

/// 按具体实现选择外部链接 adapter；低层平台判断不泄漏到 UI。
ExternalLinkGateway externalLinkGatewayForCurrentPlatform() =>
    PlatformSupport.isAndroid
    ? AndroidCustomTabExternalLinkGateway()
    : ExternalBrowserLinkGateway();

/// 打开外部网页链接（http / https）。
///
/// Android：优先走浏览器的 Custom Tabs（应用内轻量标签页）。原生侧只在
/// 「默认浏览器支持 Custom Tabs」时启动——判定口径与 url_launcher 的
/// inAppBrowserView 一致（CustomTabsClient 的首选包就是默认 VIEW handler）；
/// 国内 ROM 自带浏览器大多不支持，此时返回 false，落回
/// [LaunchMode.externalApplication]（普通浏览器打开），行为与改动前一致，
/// 也不会硬切到用户没在用的浏览器。
///
/// 其它平台（Windows 等）直接交给系统默认程序打开。
Future<bool> openExternalUrl(Uri url, {ExternalLinkGateway? gateway}) {
  return (gateway ?? externalLinkGatewayForCurrentPlatform()).open(url);
}

Future<bool> _invokeCustomTab(Uri url) async {
  try {
    return await _channel.invokeMethod<bool>('openCustomTab', {
          'url': url.toString(),
        }) ??
        false;
  } on PlatformException {
    // 通道报错：落回系统默认方式
    return false;
  } on MissingPluginException {
    // 测试环境 / 原生侧未注册：同上
    return false;
  }
}

Future<bool> _launchExternalBrowser(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);
