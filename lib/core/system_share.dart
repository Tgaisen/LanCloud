import 'package:flutter/services.dart';

/// 导出：把文本交给系统分享面板（可发送到其他应用，或经文件管理器另存）。
class SystemShare {
  SystemShare._();

  static const _channel = MethodChannel('lancloud/share');

  static Future<bool> shareText(String text, {String subject = ''}) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'shareText',
        {'text': text, 'subject': subject},
      );
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
