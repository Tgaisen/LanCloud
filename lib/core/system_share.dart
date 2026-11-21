import 'package:flutter/services.dart';

import 'platform_capabilities.dart';
import 'system_open.dart';

typedef ShareChannelInvoker = Future<bool> Function(
  String method,
  Map<String, Object?> arguments,
);
typedef ClipboardTextWriter = Future<void> Function(String text);
typedef ExplorerRevealer = Future<bool> Function(String path);

/// 文本、单个文件和多个文件的系统分享能力。
abstract interface class SystemShareGateway {
  Future<bool> shareText(String text, {String subject = ''});

  Future<bool> shareFile(
    String path, {
    String subject = '',
    String mime = 'application/json',
  });

  Future<bool> shareFiles(
    Iterable<String> paths, {
    String subject = '',
    String? mime,
  });
}

/// Android 原生分享面板。
final class NativeSystemShareGateway implements SystemShareGateway {
  NativeSystemShareGateway({ShareChannelInvoker? invoke})
    : _invoke = invoke ?? _invokeShareChannel;

  final ShareChannelInvoker _invoke;

  @override
  Future<bool> shareText(String text, {String subject = ''}) {
    return _invoke('shareText', {'text': text, 'subject': subject});
  }

  @override
  Future<bool> shareFile(
    String path, {
    String subject = '',
    String mime = 'application/json',
  }) {
    return _invoke('shareFile', {
      'path': path,
      'subject': subject,
      'mime': mime,
    });
  }

  @override
  Future<bool> shareFiles(
    Iterable<String> paths, {
    String subject = '',
    String? mime,
  }) {
    final files = _nonEmptyFiles(paths);
    if (files.isEmpty) return Future<bool>.value(false);
    if (files.length == 1) {
      return shareFile(
        files.single,
        subject: subject,
        mime: mime ?? 'application/octet-stream',
      );
    }
    return _invoke('shareFiles', {
      'paths': files,
      'subject': subject,
      if (mime != null && mime.isNotEmpty) 'mime': mime,
    });
  }
}

/// 桌面端没有系统分享面板时的等效降级：复制文本或定位文件。
final class DesktopSystemShareGateway implements SystemShareGateway {
  DesktopSystemShareGateway({
    ClipboardTextWriter? writeClipboard,
    ExplorerRevealer? reveal,
  }) : _writeClipboard = writeClipboard ?? _writeClipboardText,
       _reveal = reveal ?? revealInExplorer;

  final ClipboardTextWriter _writeClipboard;
  final ExplorerRevealer _reveal;

  @override
  Future<bool> shareText(String text, {String subject = ''}) async {
    await _writeClipboard(text);
    return true;
  }

  @override
  Future<bool> shareFile(
    String path, {
    String subject = '',
    String mime = 'application/json',
  }) => _reveal(path);

  @override
  Future<bool> shareFiles(
    Iterable<String> paths, {
    String subject = '',
    String? mime,
  }) {
    final files = _nonEmptyFiles(paths);
    if (files.isEmpty) return Future<bool>.value(false);
    return _reveal(files.first);
  }
}

/// 当前平台没有系统分享，也没有桌面定位降级。
final class UnsupportedSystemShareGateway implements SystemShareGateway {
  const UnsupportedSystemShareGateway();

  @override
  Future<bool> shareText(String text, {String subject = ''}) =>
      Future<bool>.value(false);

  @override
  Future<bool> shareFile(
    String path, {
    String subject = '',
    String mime = 'application/json',
  }) => Future<bool>.value(false);

  @override
  Future<bool> shareFiles(
    Iterable<String> paths, {
    String subject = '',
    String? mime,
  }) => Future<bool>.value(false);
}

/// 按静态平台矩阵选择原生、桌面降级或 unsupported 实现。
SystemShareGateway systemShareGatewayFor(PlatformCapabilities capabilities) {
  if (capabilities.supportsSystemShare) return NativeSystemShareGateway();
  if (capabilities.formFactor == PlatformFormFactor.desktop) {
    return DesktopSystemShareGateway();
  }
  return const UnsupportedSystemShareGateway();
}

/// 导出：优先交给系统分享面板；桌面端降级为剪贴板或资源管理器定位。
class SystemShare {
  SystemShare._();

  static Future<bool> shareText(
    String text, {
    String subject = '',
    PlatformCapabilities? capabilities,
    SystemShareGateway? gateway,
  }) {
    return _gateway(capabilities, gateway).shareText(text, subject: subject);
  }

  /// 导出文件：交给系统分享面板（可另存到文件管理器、发送到其他应用）。
  static Future<bool> shareFile(
    String path, {
    String subject = '',
    String mime = 'application/json',
    PlatformCapabilities? capabilities,
    SystemShareGateway? gateway,
  }) {
    return _gateway(
      capabilities,
      gateway,
    ).shareFile(path, subject: subject, mime: mime);
  }

  /// 一次导出多个文件；gateway 统一处理空列表与单文件分流。
  static Future<bool> shareFiles(
    Iterable<String> paths, {
    String subject = '',
    String? mime,
    PlatformCapabilities? capabilities,
    SystemShareGateway? gateway,
  }) {
    return _gateway(
      capabilities,
      gateway,
    ).shareFiles(paths, subject: subject, mime: mime);
  }

  static SystemShareGateway _gateway(
    PlatformCapabilities? capabilities,
    SystemShareGateway? gateway,
  ) {
    return gateway ??
        systemShareGatewayFor(capabilities ?? PlatformCapabilities.current);
  }
}

Future<bool> _invokeShareChannel(
  String method,
  Map<String, Object?> arguments,
) async {
  try {
    return await const MethodChannel('lancloud/share')
            .invokeMethod<bool>(method, arguments) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

Future<void> _writeClipboardText(String text) {
  return Clipboard.setData(ClipboardData(text: text));
}

List<String> _nonEmptyFiles(Iterable<String> paths) {
  return [
    for (final path in paths)
      if (path.isNotEmpty) path,
  ];
}
