import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'platform_support.dart';

const MethodChannel _channel = MethodChannel('lancloud/external_link');

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
Future<bool> openExternalUrl(Uri url) async {
  if (PlatformSupport.isAndroid) {
    try {
      final opened = await _channel.invokeMethod<bool>('openCustomTab', {
        'url': url.toString(),
      });
      if (opened ?? false) return true;
    } on PlatformException {
      // 通道报错：落回系统默认方式
    } on MissingPluginException {
      // 测试环境 / 原生侧未注册：同上
    }
  }
  return launchUrl(url, mode: LaunchMode.externalApplication);
}
