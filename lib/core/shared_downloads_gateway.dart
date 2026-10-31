import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shared_downloads_storage.dart';

/// 公共 Downloads 能力接口，隔离平台通道并允许测试注入。
abstract interface class SharedDownloadsGateway {
  Future<bool> isSupported();

  Future<String?> defaultDirectoryPath();

  Future<SharedDownloadedFile> save({
    required String sourcePath,
    required String fileName,
    required String mime,
    String jobId,
    void Function(int copied, int total)? onProgress,
  });
}

/// 生产实现：保持委托到现有 Android MethodChannel 封装。
class PlatformSharedDownloadsGateway implements SharedDownloadsGateway {
  const PlatformSharedDownloadsGateway();

  @override
  Future<bool> isSupported() => SharedDownloadsStorage.isSupported();

  @override
  Future<String?> defaultDirectoryPath() =>
      SharedDownloadsStorage.defaultDirectoryPath();

  @override
  Future<SharedDownloadedFile> save({
    required String sourcePath,
    required String fileName,
    required String mime,
    String jobId = '',
    void Function(int copied, int total)? onProgress,
  }) => SharedDownloadsStorage.save(
    sourcePath: sourcePath,
    fileName: fileName,
    mime: mime,
    jobId: jobId,
    onProgress: onProgress,
  );
}

/// 应用级公共 Downloads 路径能力；无状态且常驻。
final sharedDownloadsGatewayProvider = Provider<SharedDownloadsGateway>(
  (ref) => const PlatformSharedDownloadsGateway(),
);
