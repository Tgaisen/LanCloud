import 'dart:async';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'platform_capabilities.dart';

/// 其他应用分享进来的内容收件箱：
/// 冷启动读取初始分享，运行中通过流接收新分享，交给 RootShell 处理。
///
/// 只有当前实现具备接收分享能力时，才会读取初始内容或订阅运行中媒体流。
class SharedInbox {
  SharedInbox({PlatformCapabilities? capabilities})
    : _capabilities = capabilities ?? PlatformCapabilities.current;

  static final SharedInbox instance = SharedInbox();

  final PlatformCapabilities _capabilities;

  String? pendingText;
  List<String> pendingFiles = [];
  void Function(String text)? onText;
  void Function(List<String> files)? onFiles;

  StreamSubscription<List<SharedMediaFile>>? _mediaSub;

  Future<void> init() async {
    if (!_capabilities.supportsIncomingShare) return;
    try {
      final media = await ReceiveSharingIntent.instance.getInitialMedia();
      for (final m in media) {
        if (m.type == SharedMediaType.text || m.type == SharedMediaType.url) {
          if (m.path.trim().isNotEmpty) pendingText ??= m.path.trim();
        } else {
          pendingFiles.add(m.path);
        }
      }
    } catch (_) {}
  }

  void attach() {
    if (!_capabilities.supportsIncomingShare) return;
    _mediaSub ??= ReceiveSharingIntent.instance.getMediaStream().listen((
      files,
    ) {
      final texts = <String>[];
      final paths = <String>[];
      for (final f in files) {
        if (f.type == SharedMediaType.text || f.type == SharedMediaType.url) {
          if (f.path.trim().isNotEmpty) texts.add(f.path.trim());
        } else {
          paths.add(f.path);
        }
      }
      if (texts.isNotEmpty) onText?.call(texts.join(' '));
      if (paths.isNotEmpty) onFiles?.call(paths);
    });
  }

  void dispose() {
    _mediaSub?.cancel();
    _mediaSub = null;
  }
}
