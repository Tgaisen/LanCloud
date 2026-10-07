import 'package:flutter/services.dart';

import 'platform_support.dart';
import 'system_open.dart';

/// 导出：把文本交给系统分享面板（可发送到其他应用，或经文件管理器另存）。
///
/// 桌面端（Windows）没有系统分享面板，退化成等效操作：
/// 文本复制到剪贴板、文件用资源管理器定位。
class SystemShare {
  SystemShare._();

  static const _channel = MethodChannel('lancloud/share');

  static Future<bool> shareText(String text, {String subject = ''}) async {
    if (PlatformSupport.isDesktop) {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    }
    return _invoke('shareText', {'text': text, 'subject': subject});
  }

  /// 导出文件：交给系统分享面板（可另存到文件管理器、发送到其他应用）。
  static Future<bool> shareFile(
    String path, {
    String subject = '',
    String mime = 'application/json',
  }) {
    if (PlatformSupport.isDesktop) return revealInExplorer(path);
    return _invoke('shareFile', {
      'path': path,
      'subject': subject,
      'mime': mime,
    });
  }

  static Future<bool> _invoke(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final ok = await _channel.invokeMethod<bool>(method, arguments);
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
