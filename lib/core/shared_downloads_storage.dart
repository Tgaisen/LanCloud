import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_support.dart';

/// 一次写入公共 Downloads 的文件。
class SharedDownloadedFile {
  const SharedDownloadedFile({required this.uri, required this.name});

  /// MediaStore 内容的 URI，可用于打开、分享和删除。
  final String uri;

  /// 系统实际使用的文件名（重名时可能带序号）。
  final String name;
}

/// Android 公共 Downloads 目录。
///
/// Android 10+ 通过 MediaStore 写入 `Download/LanCloud`，不需要存储权限，
/// 也不需要 SAF 目录授权；文件仍由本应用创建，因此可以用返回的 content URI
/// 打开、分享和删除。
class SharedDownloadsStorage {
  SharedDownloadsStorage._();

  static const _channel = MethodChannel('lancloud/shared_downloads');

  static bool? _supported;
  static String? _defaultDirectoryPath;
  static bool _handlersReady = false;
  static final Map<String, void Function(int copied, int total)> _progress = {};

  static void _ensureHandlers() {
    if (_handlersReady) return;
    _handlersReady = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'progress') return null;
      final args = call.arguments;
      if (args is! Map) return null;
      final handler = _progress['${args['id'] ?? ''}'];
      handler?.call(
        (args['copied'] as num?)?.toInt() ?? 0,
        (args['total'] as num?)?.toInt() ?? 0,
      );
      return null;
    });
  }

  /// 当前系统是否支持无授权写入公共 Downloads（Android 10+）。
  static Future<bool> isSupported() async {
    final cached = _supported;
    if (cached != null) return cached;
    if (!PlatformSupport.isAndroid) {
      _supported = false;
      return false;
    }
    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      _supported = false;
    }
    return _supported!;
  }

  /// 默认公共下载目录的展示路径，例如 `/storage/emulated/0/Download/LanCloud`。
  static Future<String?> defaultDirectoryPath() async {
    final cached = _defaultDirectoryPath;
    if (cached != null) return cached;
    if (!await isSupported()) return null;
    try {
      _defaultDirectoryPath = await _channel.invokeMethod<String>(
        'defaultDirectory',
      );
    } catch (_) {
      _defaultDirectoryPath = null;
    }
    return _defaultDirectoryPath;
  }

  /// 把应用专属目录里的 [sourcePath] 复制到 `Download/LanCloud`。
  ///
  /// [jobId] + [onProgress] 用于接收复制进度。系统不支持时抛
  /// `PlatformException(code: unsupported)`，其它写入失败抛
  /// `PlatformException(code: export_failed)`。
  static Future<SharedDownloadedFile> save({
    required String sourcePath,
    required String fileName,
    required String mime,
    String jobId = '',
    void Function(int copied, int total)? onProgress,
  }) async {
    _ensureHandlers();
    if (!await isSupported()) {
      throw PlatformException(
        code: 'unsupported',
        message: 'MediaStore Downloads requires Android 10 or newer',
      );
    }
    if (jobId.isNotEmpty && onProgress != null) {
      _progress[jobId] = onProgress;
    }
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'saveFile',
        {
          'sourcePath': sourcePath,
          'fileName': fileName,
          'mime': mime,
          'jobId': jobId,
        },
      );
      if (res == null) {
        throw PlatformException(code: 'export_failed', message: 'empty result');
      }
      return SharedDownloadedFile(
        uri: '${res['uri'] ?? ''}',
        name: '${res['name'] ?? fileName}',
      );
    } finally {
      if (jobId.isNotEmpty) _progress.remove(jobId);
    }
  }

  /// 仅供测试：清除平台能力与路径缓存。
  @visibleForTesting
  static void resetCacheForTesting() {
    _supported = null;
    _defaultDirectoryPath = null;
  }
}
