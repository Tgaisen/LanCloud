import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/settings_store.dart';
import '../download_path_service.dart';
import '../download_target.dart';
import '../platform_support.dart';
import '../shared_downloads_gateway.dart';

/// `TransferManager` 需要的下载目标与路径解析能力。
abstract interface class TransferDownloadPort {
  Future<DownloadTargetMode> targetMode();
  String? get safTreeUri;
  Future<String> safTempFilePath(String taskId, String name);
  Future<String> uniqueSavePath(String name);
}

/// 生产下载端口：从实时设置和注入的平台能力解析目标与路径。
class DefaultTransferDownloadPort implements TransferDownloadPort {
  const DefaultTransferDownloadPort({
    required this.downloadPaths,
    required this.sharedDownloads,
    required this.settings,
  });

  final DownloadPathService downloadPaths;
  final SharedDownloadsGateway sharedDownloads;
  final SettingsStore settings;

  static bool _safTmpSwept = false;

  @override
  Future<DownloadTargetMode> targetMode() async {
    final directory = settings.downloadDir;
    final treeUri = settings.downloadDirTree;
    var supportsSharedDownloads = false;
    if (PlatformSupport.isAndroid &&
        (directory == null || directory.isEmpty) &&
        (treeUri == null || treeUri.isEmpty)) {
      supportsSharedDownloads = await sharedDownloads.isSupported();
    }
    return resolveDownloadTargetMode(
      isAndroid: PlatformSupport.isAndroid,
      supportsSharedDownloads: supportsSharedDownloads,
      directory: directory,
      treeUri: treeUri,
    );
  }

  Future<Directory> downloadDirectory() async {
    Directory dir;
    final custom = settings.downloadDir;
    if (custom != null && custom.isNotEmpty) {
      dir = Directory(custom);
    } else {
      dir = Directory(await downloadPaths.defaultDownloadDirPath());
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  String? get safTreeUri {
    if (!PlatformSupport.isAndroid) return null;
    final uri = settings.downloadDirTree;
    return (uri == null || uri.isEmpty) ? null : uri;
  }

  @override
  Future<String> safTempFilePath(String taskId, String name) async {
    final dir = await _safTempDirectory();
    final file = File(p.join(dir.path, '$taskId${p.extension(name)}'));
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    return file.path;
  }

  Future<Directory> _safTempDirectory() async {
    final base =
        await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'LanCloud', '.tmp'));
    if (!await dir.exists()) await dir.create(recursive: true);
    if (!_safTmpSwept) {
      _safTmpSwept = true;
      unawaited(_sweepStaleSafTmp(dir));
    }
    return dir;
  }

  static Future<void> _sweepStaleSafTmp(Directory dir) async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  @override
  Future<String> uniqueSavePath(String name) async {
    final dir = await downloadDirectory();
    var path = p.join(dir.path, name);
    var i = 1;
    final ext = p.extension(name);
    final baseName = p.basenameWithoutExtension(name);
    while (await File(path).exists()) {
      path = p.join(dir.path, '$baseName($i)$ext');
      i += 1;
    }
    return path;
  }
}

/// 用回调包装迁移期现有下载路径实现。
class CallbackTransferDownloadPort implements TransferDownloadPort {
  factory CallbackTransferDownloadPort({
    required Future<DownloadTargetMode> Function() targetMode,
    required String? Function() safTreeUri,
    required Future<String> Function(String taskId, String name)
    safTempFilePath,
    required Future<String> Function(String name) uniqueSavePath,
  }) => CallbackTransferDownloadPort._(
    targetMode,
    safTreeUri,
    safTempFilePath,
    uniqueSavePath,
  );

  CallbackTransferDownloadPort._(
    this._targetMode,
    this._safTreeUri,
    this._safTempFilePath,
    this._uniqueSavePath,
  );

  final Future<DownloadTargetMode> Function() _targetMode;
  final String? Function() _safTreeUri;
  final Future<String> Function(String taskId, String name) _safTempFilePath;
  final Future<String> Function(String name) _uniqueSavePath;

  @override
  Future<DownloadTargetMode> targetMode() => _targetMode();

  @override
  String? get safTreeUri => _safTreeUri();

  @override
  Future<String> safTempFilePath(String taskId, String name) =>
      _safTempFilePath(taskId, name);

  @override
  Future<String> uniqueSavePath(String name) => _uniqueSavePath(name);
}
