import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'platform_capabilities.dart';
import 'shared_downloads_gateway.dart';

/// 默认下载目录的解析能力。
abstract interface class DownloadPathService {
  Future<String> defaultDownloadDirPath();
}

/// 默认目录解析所需的 path_provider 端口。
abstract interface class DownloadDirectoryProvider {
  Future<Directory?> downloadsDirectory();

  Future<Directory> applicationDocumentsDirectory();

  Future<Directory?> externalStorageDirectory();
}

final class _SystemDownloadDirectoryProvider
    implements DownloadDirectoryProvider {
  const _SystemDownloadDirectoryProvider();

  @override
  Future<Directory?> downloadsDirectory() => getDownloadsDirectory();

  @override
  Future<Directory> applicationDocumentsDirectory() =>
      getApplicationDocumentsDirectory();

  @override
  Future<Directory?> externalStorageDirectory() =>
      getExternalStorageDirectory();
}

/// 生产实现：Android 优先公共 Downloads，其余平台使用系统下载目录。
class PlatformDownloadPathService implements DownloadPathService {
  PlatformDownloadPathService({
    required this.sharedDownloads,
    PlatformCapabilities? capabilities,
    DownloadDirectoryProvider? directoryProvider,
  }) : capabilities = capabilities ?? PlatformCapabilities.current,
       _directoryProvider =
           directoryProvider ?? const _SystemDownloadDirectoryProvider();

  final SharedDownloadsGateway sharedDownloads;
  final PlatformCapabilities capabilities;
  final DownloadDirectoryProvider _directoryProvider;

  @override
  Future<String> defaultDownloadDirPath() async {
    if (capabilities.supportsSafDirectory) {
      final shared = await sharedDownloads.defaultDirectoryPath();
      if (shared != null && shared.isNotEmpty) return shared;
    }
    final Directory base;
    if (capabilities.supportsSafDirectory) {
      base =
          await _directoryProvider.externalStorageDirectory() ??
          await _directoryProvider.applicationDocumentsDirectory();
    } else {
      base =
          await _directoryProvider.downloadsDirectory() ??
          await _directoryProvider.applicationDocumentsDirectory();
    }
    return p.join(base.path, 'LanCloud');
  }
}

/// 应用级默认目录解析服务；无状态且常驻。
final downloadPathServiceProvider = Provider<DownloadPathService>(
  (ref) => PlatformDownloadPathService(
    sharedDownloads: ref.watch(sharedDownloadsGatewayProvider),
    capabilities: ref.watch(platformCapabilitiesProvider),
  ),
);
