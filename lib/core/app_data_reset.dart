import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_cache.dart';
import 'app_log.dart';
import 'data/secure_storage.dart';
import 'notifications.dart';

typedef AppDataResetDirectoryProvider = Future<Directory> Function();
typedef AppDataResetAsyncCallback = Future<void> Function();
typedef AppDataResetProcessStarter = Future<void> Function(
  String executable,
  List<String> arguments,
);
typedef AppDataResetDirectoryRemover = Future<bool> Function(
  Directory directory,
);
typedef AppDataResetExit = void Function(int code);

/// Windows「删除所有数据」的清理边界。
///
/// 只处理应用自己管理的账号、设置、数据库、日志、缓存和系统集成数据；
/// 用户主动下载到其他目录的文件不在删除范围内。
abstract interface class AppDataResetService {
  Future<bool> openAppDataDirectory();

  Future<bool> openLogsDirectory();

  /// 上一次退出前未能删净时，在下次启动初始化任何存储之前补清理。
  Future<bool> completePendingReset();

  Future<void> resetAndExit({
    required Future<void> Function() cancelTransfers,
    required Future<void> Function() deleteDatabase,
  });
}

final appDataResetProvider = Provider<AppDataResetService>(
  (ref) => PlatformAppDataResetService(),
);

final class PlatformAppDataResetService implements AppDataResetService {
  PlatformAppDataResetService({
    AppDataResetDirectoryProvider? applicationSupportDirectory,
    AppDataResetDirectoryProvider? applicationDocumentsDirectory,
    AppDataResetDirectoryProvider? temporaryDirectory,
    AppDataResetAsyncCallback? clearPreferences,
    AppDataResetAsyncCallback? clearSecureStorage,
    Future<int?> Function()? clearCache,
    AppDataResetDirectoryRemover? removeDirectory,
    bool Function()? removeRegistryEntry,
    AppDataResetProcessStarter? startProcess,
    AppDataResetExit? exitApplication,
  }) : _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory,
       _applicationDocumentsDirectory =
           applicationDocumentsDirectory ?? getApplicationDocumentsDirectory,
       _temporaryDirectory =
           temporaryDirectory ?? (() async => Directory.systemTemp),
       _clearPreferences = clearPreferences ?? _defaultClearPreferences,
       _clearSecureStorage =
           clearSecureStorage ?? lanCloudSecureStorage.deleteAll,
       _clearCache = clearCache ?? AppCache.clear,
       _removeDirectory = removeDirectory ?? _defaultRemoveDirectory,
       _removeRegistryEntry =
           removeRegistryEntry ??
           NotificationService.removeWindowsRegistryEntry,
       _startProcess = startProcess ?? _startPlatformProcess,
       _exitApplication = exitApplication ?? exit;

  static const _pendingResetName = 'lancloud_reset_pending';
  static const _transferCancelTimeout = Duration(seconds: 5);

  final AppDataResetDirectoryProvider _applicationSupportDirectory;
  final AppDataResetDirectoryProvider _applicationDocumentsDirectory;
  final AppDataResetDirectoryProvider _temporaryDirectory;
  final AppDataResetAsyncCallback _clearPreferences;
  final AppDataResetAsyncCallback _clearSecureStorage;
  final Future<int?> Function() _clearCache;
  final AppDataResetDirectoryRemover _removeDirectory;
  final bool Function() _removeRegistryEntry;
  final AppDataResetProcessStarter _startProcess;
  final AppDataResetExit _exitApplication;

  Future<Directory> _logsDirectory() async {
    final documents = await _applicationDocumentsDirectory();
    return Directory(p.join(documents.path, 'logs'));
  }

  Future<File> _pendingMarker() async {
    final temporary = await _temporaryDirectory();
    return File(p.join(temporary.path, _pendingResetName));
  }

  @override
  Future<bool> openAppDataDirectory() =>
      _openDirectory(_applicationSupportDirectory);

  @override
  Future<bool> openLogsDirectory() => _openDirectory(_logsDirectory);

  Future<bool> _openDirectory(AppDataResetDirectoryProvider provider) async {
    try {
      final directory = await provider();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      await _startProcess('explorer.exe', [directory.path]);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> completePendingReset() async {
    final marker = await _pendingMarker();
    if (!await marker.exists()) return true;
    final completed = await _cleanupOwnedData();
    if (completed && await marker.exists()) await marker.delete();
    return completed && !await marker.exists();
  }

  @override
  Future<void> resetAndExit({
    required Future<void> Function() cancelTransfers,
    required Future<void> Function() deleteDatabase,
  }) async {
    final marker = await _pendingMarker();
    await marker.parent.create(recursive: true);
    await marker.writeAsString('pending', flush: true);

    await _ignoreFailure(
      () => cancelTransfers().timeout(_transferCancelTimeout, onTimeout: () {}),
    );
    await _ignoreFailure(deleteDatabase);
    await _ignoreFailure(_clearPreferences);
    await _ignoreFailure(_clearSecureStorage);
    final completed = await _cleanupOwnedData();
    if (completed && await marker.exists()) await marker.delete();
    _exitApplication(0);
  }

  Future<bool> _cleanupOwnedData() async {
    var completed = true;
    try {
      completed &= await _removeDirectory(await _applicationSupportDirectory());
    } catch (_) {
      completed = false;
    }
    try {
      final logs = await _logsDirectory();
      await AppLog.clearOwnedFiles(logs);
      completed &= await _deleteDirectoryIfEmpty(logs);
    } catch (_) {
      completed = false;
    }
    try {
      await _clearCache();
    } catch (_) {
      // 缓存是短生命周期数据，失败不保留重置标记，避免下次误删新数据。
    }
    try {
      _removeRegistryEntry();
    } catch (_) {
      // 注册表项会在下次启动按需重建，失败不阻塞本次清理完成。
    }
    return completed;
  }

  static Future<bool> _defaultRemoveDirectory(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      return !await directory.exists();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _deleteDirectoryIfEmpty(Directory directory) async {
    try {
      if (!await directory.exists()) return true;
      await for (final _ in directory.list(followLinks: false)) {
        // 目录里还有其它程序的文件时不接管目录，但本应用文件已清理完成。
        return true;
      }
      await directory.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ignoreFailure(AppDataResetAsyncCallback action) async {
    try {
      await action();
    } catch (_) {
      // 单项失败不阻塞退出；重置标记会让下次启动继续补清理。
    }
  }

  static Future<void> _defaultClearPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.clear();
  }

  static Future<void> _startPlatformProcess(
    String executable,
    List<String> arguments,
  ) async {
    await Process.start(executable, arguments);
  }
}
