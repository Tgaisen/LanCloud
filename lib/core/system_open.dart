import 'dart:io';

import 'package:open_filex/open_filex.dart';

import 'file_open_result.dart';
import 'platform_support.dart';
import 'saf_storage.dart';
import 'saved_file.dart';

typedef ProcessStarter = Future<void> Function(
  String executable,
  List<String> arguments,
);

/// 系统文件打开与定位动作的窄接口。
abstract interface class SystemOpenAdapter {
  Future<FileOpenResult> openFile(String path, {String? name});

  Future<bool> revealInExplorer(String path);
}

/// Android：普通路径和 Content URI 统一交给原生 FileProvider。
final class AndroidSystemOpenAdapter implements SystemOpenAdapter {
  const AndroidSystemOpenAdapter();

  @override
  Future<FileOpenResult> openFile(String path, {String? name}) {
    return SafStorage.openFile(
      path,
      mime: name == null ? null : mimeForFileName(name),
      displayName: name,
    );
  }

  @override
  Future<bool> revealInExplorer(String path) => Future<bool>.value(false);
}

/// iOS 与其它非桌面平台：交给 open_filex 按文件关联打开。
final class OpenFilexSystemOpenAdapter implements SystemOpenAdapter {
  const OpenFilexSystemOpenAdapter();

  @override
  Future<FileOpenResult> openFile(String path, {String? name}) async {
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

  @override
  Future<bool> revealInExplorer(String path) => Future<bool>.value(false);
}

/// Windows：资源管理器按文件关联打开，或在选中状态下定位。
final class WindowsSystemOpenAdapter implements SystemOpenAdapter {
  WindowsSystemOpenAdapter({ProcessStarter? startProcess})
    : _startProcess = startProcess ?? _startPlatformProcess;

  final ProcessStarter _startProcess;

  @override
  Future<FileOpenResult> openFile(String path, {String? name}) async {
    if (!await File(path).exists()) {
      return const FileOpenResult.failed(FileOpenFailure.fileNotFound);
    }
    try {
      await _startProcess('explorer.exe', [path]);
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

  @override
  Future<bool> revealInExplorer(String path) async {
    try {
      await _startProcess('explorer.exe', ['/select,$path']);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// macOS / Linux：通过系统 `open` 打开文件或所在目录。
final class PosixDesktopSystemOpenAdapter implements SystemOpenAdapter {
  PosixDesktopSystemOpenAdapter({ProcessStarter? startProcess})
    : _startProcess = startProcess ?? _startPlatformProcess;

  final ProcessStarter _startProcess;

  @override
  Future<FileOpenResult> openFile(String path, {String? name}) {
    return _openDesktopFile(path, startProcess: _startProcess);
  }

  @override
  Future<bool> revealInExplorer(String path) async {
    try {
      await _startProcess('open', [File(path).parent.path]);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// 按当前运行平台选择文件系统动作 adapter；调用方无需感知实现差异。
SystemOpenAdapter systemOpenAdapterForCurrentPlatform() {
  if (PlatformSupport.isAndroid) return const AndroidSystemOpenAdapter();
  if (PlatformSupport.isWindows) return WindowsSystemOpenAdapter();
  if (PlatformSupport.isDesktop) return PosixDesktopSystemOpenAdapter();
  return const OpenFilexSystemOpenAdapter();
}

/// 用系统默认程序打开本地文件。
///
/// - Android 普通路径 / Content URI：统一交给原生 FileProvider，带上读权限
///   转授打开，避免 open_filex 在 Android 11+ 申请宽泛存储权限；
/// - iOS：open_filex（UIDocumentInteractionController）
/// - 桌面端：open_filex 没有 Windows 实现，交给资源管理器按文件关联打开
///   （等价于在资源管理器里双击该文件）
Future<FileOpenResult> openFileWithSystem(
  String path, {
  String? name,
  SystemOpenAdapter? adapter,
}) {
  return (adapter ?? systemOpenAdapterForCurrentPlatform()).openFile(
    path,
    name: name,
  );
}

/// 在资源管理器里定位文件（桌面端的「分享」退化成这个）。
Future<bool> revealInExplorer(String path, {SystemOpenAdapter? adapter}) {
  return (adapter ?? systemOpenAdapterForCurrentPlatform()).revealInExplorer(
    path,
  );
}

Future<FileOpenResult> _openDesktopFile(
  String path, {
  required ProcessStarter startProcess,
}) async {
  if (!await File(path).exists()) {
    return const FileOpenResult.failed(FileOpenFailure.fileNotFound);
  }
  try {
    await startProcess('open', [path]);
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

Future<void> _startPlatformProcess(
  String executable,
  List<String> arguments,
) async {
  await Process.start(executable, arguments);
}
