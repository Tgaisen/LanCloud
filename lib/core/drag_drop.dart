import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 其它应用拖进来的一个文件（content:// URI，读权限是临时的）。
class DropFile {
  const DropFile({
    required this.uri,
    required this.name,
    this.path = '',
    this.size = 0,
    this.mime = '',
  });

  final String uri;
  final String name;

  /// 原生在 drop 那一刻复制到应用缓存的本地路径（拖拽读权限是临时的）。
  /// 复制失败时为空，需要退回 [DragDropChannel.copyToCache] 再试一次。
  final String path;
  final int size;
  final String mime;
}

/// 一次拖拽落下时的内容。
class DropPayload {
  const DropPayload({
    this.texts = const <String>[],
    this.files = const <DropFile>[],
  });

  /// 文本条目（分享链接、复制的文字等）。
  final List<String> texts;

  /// content:// 文件条目。
  final List<DropFile> files;

  bool get hasFiles => files.isNotEmpty;
  bool get hasText => texts.any((t) => t.trim().isNotEmpty);
}

/// 拖拽悬停概览：进入窗口时用来提示"松开后会做什么"。
class DropHover {
  const DropHover({this.texts = 0, this.files = 0});

  static const empty = DropHover();

  final int texts;
  final int files;

  bool get isEmpty => texts == 0 && files == 0;
  bool get hasFiles => files > 0;
  bool get hasText => texts > 0;
  bool get isMixed => texts > 0 && files > 0;

  @override
  bool operator ==(Object other) =>
      other is DropHover && other.texts == texts && other.files == files;

  @override
  int get hashCode => Object.hash(texts, files);
}

/// 原生拖拽通道：Android 侧接住别的应用拖进窗口的事件，转成
/// [DropHover] / [DropPayload] 交给 RootShell 处理（拖拽/分享/剪贴板
/// 三条入口最终都走同一套外部内容处理逻辑）。
class DragDropChannel {
  DragDropChannel._();

  static final DragDropChannel instance = DragDropChannel._();

  static const MethodChannel _channel = MethodChannel('lancloud/drag_drop');

  void Function(DropHover hover)? onHover;
  void Function(DropPayload payload)? onDrop;

  void attach() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'dragEntered':
          onHover?.call(_hoverFrom(call.arguments));
        case 'dragExited':
          onHover?.call(DropHover.empty);
        case 'dropped':
          onDrop?.call(_payloadFrom(call.arguments));
      }
      return null;
    });
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    onHover = null;
    onDrop = null;
  }

  /// 把拖进来的文件复制到应用缓存，返回本地路径（失败返回 null）。
  /// 拖拽授予的读权限只在会话内有效，所以真正要上传前必须先复制一份。
  Future<String?> copyToCache(DropFile file) async {
    try {
      final path = await _channel.invokeMethod<String>('copyToCache', {
        'uri': file.uri,
        'name': file.name,
      });
      return (path == null || path.isEmpty) ? null : path;
    } catch (_) {
      return null;
    }
  }

  static DropHover _hoverFrom(Object? arguments) {
    if (arguments is! Map) return DropHover.empty;
    return DropHover(
      texts: (arguments['texts'] as num?)?.toInt() ?? 0,
      files: (arguments['files'] as num?)?.toInt() ?? 0,
    );
  }

  @visibleForTesting
  static DropPayload payloadFrom(Object? arguments) => _payloadFrom(arguments);

  static DropPayload _payloadFrom(Object? arguments) {
    if (arguments is! Map) return const DropPayload();
    final texts = <String>[
      for (final value in (arguments['texts'] as List? ?? const []))
        if (value != null && '$value'.trim().isNotEmpty) '$value',
    ];
    final files = <DropFile>[
      for (final value in (arguments['files'] as List? ?? const []))
        if (value is Map)
          DropFile(
            uri: '${value['uri'] ?? ''}',
            name: '${value['name'] ?? ''}',
            path: '${value['path'] ?? ''}',
            size: (value['size'] as num?)?.toInt() ?? 0,
            mime: '${value['mime'] ?? ''}',
          ),
    ]..removeWhere((f) => f.uri.isEmpty);
    return DropPayload(texts: texts, files: files);
  }
}
