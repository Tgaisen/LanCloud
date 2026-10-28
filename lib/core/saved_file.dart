import 'dart:io';

import 'saf_storage.dart';

/// 按文件名猜测 MIME。用于把下载好的文件写入 SAF 授权目录时告诉系统
/// 文件类型（多数 DocumentsProvider 最终仍按扩展名落盘）。
String mimeForFileName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return 'application/octet-stream';
  return switch (name.substring(dot + 1).toLowerCase()) {
    'apk' => 'application/vnd.android.package-archive',
    'zip' => 'application/zip',
    'rar' => 'application/vnd.rar',
    '7z' => 'application/x-7z-compressed',
    'txt' || 'log' => 'text/plain',
    'json' => 'application/json',
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'mp3' => 'audio/mpeg',
    'mp4' => 'video/mp4',
    'mkv' => 'video/x-matroska',
    _ => 'application/octet-stream',
  };
}

/// 删除已下载的文件：
/// - Content URI（SAF 或 MediaStore 公共 Downloads）交给原生删除；
/// - 其它路径直接用 File 删除。
/// 文件不存在 / 已经删过都算完成，失败静默（与传输页原有口径一致）。
Future<void> deleteSavedFile(String path) async {
  if (path.isEmpty) return;
  if (SafStorage.isContentUri(path)) {
    try {
      await SafStorage.deleteFile(path);
    } catch (_) {}
    return;
  }
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {}
}
