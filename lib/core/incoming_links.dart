import 'package:flutter/services.dart';

/// 外部用蓝奏云分享链接打开本应用时的收件箱：
/// 冷启动读初始链接，运行中通过通道接收新链接，交给 RootShell 处理。
class IncomingLinks {
  IncomingLinks._();

  static final IncomingLinks instance = IncomingLinks._();

  static const _channel = MethodChannel('lancloud/links');

  String? pending;
  void Function(String url)? onLink;

  bool _attached = false;

  Future<void> init() async {
    try {
      pending = await _channel.invokeMethod<String>('getInitialLink');
    } on PlatformException {
      pending = null;
    } on MissingPluginException {
      pending = null;
    }
  }

  void attach() {
    if (_attached) return;
    _attached = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'link') return;
      final url = call.arguments;
      if (url is String && url.isNotEmpty) onLink?.call(url);
    });
  }

  void dispose() {
    _attached = false;
    _channel.setMethodCallHandler(null);
  }
}
