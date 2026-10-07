import 'dart:io';

import 'package:open_filex/open_filex.dart';

import 'platform_support.dart';

/// 用系统默认程序打开本地文件。
///
/// - Android / iOS：open_filex（FileProvider / UIDocumentInteractionController）
/// - 桌面端：open_filex 没有 Windows 实现，交给资源管理器按文件关联打开
///   （等价于在资源管理器里双击该文件）
Future<void> openFileWithSystem(String path) async {
  if (!PlatformSupport.isDesktop) {
    await OpenFilex.open(path);
    return;
  }
  await _shellOpen(path);
}

/// 在资源管理器里定位文件（桌面端的「分享」退化成这个）。
Future<bool> revealInExplorer(String path) async {
  if (PlatformSupport.isWindows) {
    try {
      await Process.start('explorer.exe', ['/select,$path']);
      return true;
    } catch (_) {
      return false;
    }
  }
  // 其它桌面平台：打开所在目录
  try {
    await _shellOpen(File(path).parent.path);
    return true;
  } catch (_) {
    return false;
  }
}

/// 交给 shell 打开路径（文件按关联程序，目录用文件管理器）。
Future<void> _shellOpen(String path) async {
  if (PlatformSupport.isWindows) {
    await Process.start('explorer.exe', [path]);
    return;
  }
  await Process.start('open', [path]);
}
