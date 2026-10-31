import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'platform_support.dart';
import 'shared_downloads_gateway.dart';

/// 默认下载目录的解析能力。
abstract interface class DownloadPathService {
  Future<String> defaultDownloadDirPath();
}

/// 生产实现：Android 优先公共 Downloads，其余平台使用系统下载目录。
class PlatformDownloadPathService implements DownloadPathService {
  const PlatformDownloadPathService({required this.sharedDownloads});

  final SharedDownloadsGateway sharedDownloads;

  @override
  Future<String> defaultDownloadDirPath() async {
    if (PlatformSupport.isAndroid) {
      final shared = await sharedDownloads.defaultDirectoryPath();
      if (shared != null && shared.isNotEmpty) return shared;
    }
    final Directory base;
    if (PlatformSupport.isMobile) {
      base =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      base =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    return p.join(base.path, 'LanCloud');
  }
}

/// 应用级默认目录解析服务；无状态且常驻。
final downloadPathServiceProvider = Provider<DownloadPathService>(
  (ref) => PlatformDownloadPathService(
    sharedDownloads: ref.watch(sharedDownloadsGatewayProvider),
  ),
);
