import 'dart:io';

import 'package:open_filex/open_filex.dart';

import 'file_open_result.dart';
import 'platform_support.dart';
import 'saf_storage.dart';
import 'saved_file.dart';

/// 用系统默认程序打开本地文件。
///
/// - Android 普通路径 / Content URI：统一交给原生 FileProvider，带上读权限
///   转授打开，避免 open_filex 在 Android 11+ 申请宽泛存储权限；
/// - iOS：open_filex（UIDocumentInteractionController）
/// - 桌面端：open_filex 没有 Windows 实现，交给资源管理器按文件关联打开
///   （等价于在资源管理器里双击该文件）
Future<FileOpenResult> openFileWithSystem(String path, {String? name}) async {
  if (PlatformSupport.isAndroid) {
    return SafStorage.openFile(
      path,
      mime: name == null ? null : mimeForFileName(name),
      displayName: name,
    );
  }
  if (!PlatformSupport.isDesktop) {
    try {
      final result = await OpenFilex.open(path);
      return switch (result.type) {
        ResultType.done => const FileOpenResult.success(),
        ResultType.fileNotFound => const FileOpenResult.failed(
          FileOpenFailure.fileNotFound,
        ),
        ResultType.permissionDenied => const FileOpenResult.failed(
          FileOpenFailure.permissionDenied,
        ),
        ResultType.noAppToOpen => const FileOpenResult.failed(
          FileOpenFailure.noAssociatedApp,
        ),
        ResultType.error => const FileOpenResult.failed(
          FileOpenFailure.systemError,
        ),
      };
    } catch (_) {
      return const FileOpenResult.failed(FileOpenFailure.systemError);
    }
  }
  if (!await File(path).exists()) {
    return const FileOpenResult.failed(FileOpenFailure.fileNotFound);
  }
  try {
    await _shellOpen(path);
    return const FileOpenResult.success();
  } on FileSystemException catch (error) {
    return FileOpenResult.failed(switch (error.osError?.errorCode) {
      5 || 13 => FileOpenFailure.permissionDenied,
      _ => FileOpenFailure.systemError,
    });
  } catch (_) {
    return const FileOpenResult.failed(FileOpenFailure.systemError);
  }
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
