import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../core/drag_drop.dart';
import '../core/platform_support.dart';

/// 桌面端窗口级拖拽：把文件从资源管理器拖进窗口。
///
/// Android 那边是原生通道直接把事件推进来（见 [DragDropChannel]），
/// 这里用 desktop_drop 的窗口 drop target 接住桌面事件，转成同一套
/// [DropHover] / [DropPayload]，后面的处理流程完全共用。
///
/// 注意：desktop_drop 在 Windows 上拿不到拖拽的文本内容（rawText 为 null），
/// 所以桌面端只支持拖文件，不支持把链接文字拖进来（仍可用粘贴 / 剪贴板识别）。
class DesktopDropTarget extends StatelessWidget {
  const DesktopDropTarget({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!PlatformSupport.isDesktop) return child;
    final hover = DragDropChannel.instance.hover;
    return DropTarget(
      onDragEntered: (_) => hover.value = const DropHover(files: 1),
      onDragExited: (_) => hover.value = null,
      onDragDone: (details) {
        hover.value = null;
        unawaited(_dispatch(details.files));
      },
      child: child,
    );
  }

  /// 拖入的目录展开成里面的文件（上传任务只认文件路径）。
  static Future<void> _dispatch(List<DropItem> items) async {
    final files = <DropFile>[];
    for (final item in items) {
      if (item is DropItemDirectory) {
        for (final child in item.children) {
          files.add(await _toDropFile(child));
        }
        continue;
      }
      files.add(await _toDropFile(item));
    }
    if (files.isEmpty) return;
    DragDropChannel.instance.onDrop?.call(DropPayload(files: files));
  }

  static Future<DropFile> _toDropFile(DropItem item) async {
    var size = 0;
    try {
      size = await item.length();
    } catch (_) {
      // 读不到大小不影响上传（上传时按文件本身算）
    }
    return DropFile(
      uri: Uri.file(item.path).toString(),
      name: item.name,
      // 桌面端拖进来的是真实本地路径，不需要再复制到缓存
      path: item.path,
      size: size,
      mime: item.mimeType ?? '',
    );
  }
}
