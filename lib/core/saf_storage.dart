import 'package:flutter/services.dart';

import 'platform_support.dart';

/// 一个被授权的 SAF 目录（用户通过系统目录选择器授予持久化读写权限）。
class SafDirectory {
  const SafDirectory({required this.uri, required this.label, this.directPath});

  /// 树的持久化 URI（`content://.../tree/...`），跨应用重启可用。
  final String uri;

  /// 展示用的路径 / 名称，例如 `/storage/emulated/0/BaiduNetdisk`。
  final String label;

  /// 目录属于 Download、Documents 等公共目录（Android 11+ 可以直接按
  /// 文件路径写入）时是真实路径；此时不占用授权、下载也不需要中转。
  final String? directPath;
}

/// 写入 SAF 授权目录成功的一个文件。
class SafSavedFile {
  const SafSavedFile({required this.uri, required this.name});

  /// 文档 URI（`content://.../document/...`），用于打开 / 分享 / 删除。
  final String uri;

  /// 目标目录里实际使用的文件名（重名时可能带 (1)）。
  final String name;
}

/// Android SAF（Storage Access Framework）读写通道。
///
/// 分区存储下应用无法用普通文件路径写入 Download / Documents 之外的目录；
/// 这里把用户选择的目录（tree URI）连同持久化授权存下来，下载完成后经原生
/// ContentResolver 把文件写入目标目录，打开 / 分享 / 删除同样走 URI。
/// 全程不需要任何存储权限，也不受分区存储限制。
class SafStorage {
  SafStorage._();

  static const _channel = MethodChannel('lancloud/saf');

  /// 复制进度回调：jobId → (已复制字节, 总字节)。
  static final Map<String, void Function(int copied, int total)> _progress = {};
  static bool _handlersReady = false;

  /// 平台是否支持 SAF（仅 Android）。
  static bool get supported => PlatformSupport.isAndroid;

  /// 路径是不是 SAF 文档 URI。
  static bool isContentUri(String path) => path.startsWith('content://');

  /// 注册原生 → Dart 的进度推送（整个进程只注册一次）。
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

  /// 打开系统目录选择器并取得持久化读写授权；用户取消返回 null，
  /// 目录无法授权（例如只读提供方）抛 PlatformException。
  static Future<SafDirectory?> pickDirectory({String? initialUri}) async {
    final args = <String, Object?>{};
    if (initialUri != null && initialUri.isNotEmpty) {
      args['initialUri'] = initialUri;
    }
    final res = await _channel.invokeMethod<Map<Object?, Object?>>(
      'pickDirectory',
      args,
    );
    if (res == null) return null;
    final path = res['path'];
    return SafDirectory(
      uri: '${res['uri'] ?? ''}',
      label: '${res['label'] ?? ''}',
      directPath: (path is String && path.isNotEmpty) ? path : null,
    );
  }

  /// 释放不再使用的目录授权（换目录 / 恢复默认时调用）。失败静默。
  static Future<void> release(String uri) async {
    if (uri.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('releaseDirectory', {'uri': uri});
    } catch (_) {}
  }

  /// 把 [sourcePath]（应用专属目录里的文件）写入授权目录，
  /// [fileName] 是期望的文件名（重名时原生侧会按 `name(1).ext` 去重）。
  ///
  /// [jobId] + [onProgress] 用于接收复制进度。授权失效抛
  /// PlatformException(code: perm_denied)，其它失败 code 为
  /// export_failed / not_found。
  static Future<SafSavedFile> export({
    required String treeUri,
    required String sourcePath,
    required String fileName,
    required String mime,
    String jobId = '',
    void Function(int copied, int total)? onProgress,
  }) async {
    _ensureHandlers();
    if (jobId.isNotEmpty && onProgress != null) {
      _progress[jobId] = onProgress;
    }
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'exportFile',
        {
          'treeUri': treeUri,
          'sourcePath': sourcePath,
          'fileName': fileName,
          'mime': mime,
          'jobId': jobId,
        },
      );
      if (res == null) {
        throw PlatformException(code: 'export_failed', message: 'empty result');
      }
      return SafSavedFile(
        uri: '${res['uri'] ?? ''}',
        name: '${res['name'] ?? fileName}',
      );
    } finally {
      if (jobId.isNotEmpty) _progress.remove(jobId);
    }
  }

  /// 删除 content URI 文件（SAF 文档或 MediaStore 项目）；
  /// 文件已被用户删掉等情况返回 false。
  static Future<bool> deleteFile(String uri) async {
    final ok = await _channel.invokeMethod<bool>('deleteFile', {'uri': uri});
    return ok ?? false;
  }

  /// 用系统默认程序打开 content URI（读权限会转授给目标应用）。
  /// 打不开（没有可处理的应用等）返回 false，与 open_filex 的口径一致。
  static Future<bool> openFile(String uri) async {
    try {
      final ok = await _channel.invokeMethod<bool>('openFile', {'uri': uri});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
