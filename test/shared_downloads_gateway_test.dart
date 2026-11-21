import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/download_path_service.dart';
import 'package:lancloud/core/download_target.dart';
import 'package:lancloud/core/platform_capabilities.dart';
import 'package:lancloud/core/shared_downloads_gateway.dart';
import 'package:lancloud/core/shared_downloads_storage.dart';
import 'package:lancloud/core/transfer/transfer_download_port.dart';
import 'package:path/path.dart' as p;

class _FakeSharedDownloads implements SharedDownloadsGateway {
  _FakeSharedDownloads({required this.supported, this.directoryPath});

  final bool supported;
  final String? directoryPath;
  var supportChecks = 0;
  var directoryChecks = 0;

  @override
  Future<bool> isSupported() async {
    supportChecks += 1;
    return supported;
  }

  @override
  Future<String?> defaultDirectoryPath() async {
    directoryChecks += 1;
    return directoryPath;
  }

  @override
  Future<SharedDownloadedFile> save({
    required String sourcePath,
    required String fileName,
    required String mime,
    String jobId = '',
    void Function(int copied, int total)? onProgress,
  }) async => const SharedDownloadedFile(uri: 'content://saved', name: 'saved');
}

class _FakeDownloadDirectoryProvider implements DownloadDirectoryProvider {
  _FakeDownloadDirectoryProvider({
    required this.downloads,
    required this.documents,
    required this.external,
  });

  final Directory? downloads;
  final Directory documents;
  final Directory? external;
  var downloadsChecks = 0;
  var documentsChecks = 0;
  var externalChecks = 0;

  @override
  Future<Directory> applicationDocumentsDirectory() async {
    documentsChecks += 1;
    return documents;
  }

  @override
  Future<Directory?> downloadsDirectory() async {
    downloadsChecks += 1;
    return downloads;
  }

  @override
  Future<Directory?> externalStorageDirectory() async {
    externalChecks += 1;
    return external;
  }
}

void main() {
  test('目录服务使用注入的公共 Downloads 能力解析默认目录', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const path = '/storage/emulated/0/Download/LanCloud';
    final service = PlatformDownloadPathService(
      sharedDownloads: _FakeSharedDownloads(
        supported: true,
        directoryPath: path,
      ),
    );

    expect(await service.defaultDownloadDirPath(), path);
  });

  test('iOS 默认目录使用系统 Downloads，不访问公共 Downloads 或外部存储', () async {
    final gateway = _FakeSharedDownloads(supported: true);
    final downloads = Directory('/virtual/iOS/Downloads');
    final provider = _FakeDownloadDirectoryProvider(
      downloads: downloads,
      documents: Directory('/virtual/iOS/Documents'),
      external: Directory('/virtual/iOS/External'),
    );
    final service = PlatformDownloadPathService(
      sharedDownloads: gateway,
      capabilities: PlatformCapabilities.ios,
      directoryProvider: provider,
    );

    expect(
      await service.defaultDownloadDirPath(),
      p.join(downloads.path, 'LanCloud'),
    );
    expect(gateway.directoryChecks, 0);
    expect(provider.downloadsChecks, 1);
    expect(provider.externalChecks, 0);
  });

  test('Android 公共下载不可用时仍回退应用外部存储', () async {
    final gateway = _FakeSharedDownloads(supported: false);
    final external = Directory('/virtual/Android/External');
    final provider = _FakeDownloadDirectoryProvider(
      downloads: Directory('/virtual/Android/Downloads'),
      documents: Directory('/virtual/Android/Documents'),
      external: external,
    );
    final service = PlatformDownloadPathService(
      sharedDownloads: gateway,
      capabilities: PlatformCapabilities.android,
      directoryProvider: provider,
    );

    expect(
      await service.defaultDownloadDirPath(),
      p.join(external.path, 'LanCloud'),
    );
    expect(provider.downloadsChecks, 0);
    expect(provider.externalChecks, 1);
  });

  test('默认下载端口在 Android 未设置目录时查询注入能力', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final gateway = _FakeSharedDownloads(supported: true);
    final port = DefaultTransferDownloadPort(
      downloadPaths: PlatformDownloadPathService(sharedDownloads: gateway),
      sharedDownloads: gateway,
      settings: SettingsStore(),
      capabilities: PlatformCapabilities.android,
    );

    await port.targetMode();

    expect(gateway.supportChecks, 1);
  });

  test('非 Android 下载端口不查询公共 Downloads', () async {
    for (final (:name, :capabilities) in [
      (name: 'Windows', capabilities: PlatformCapabilities.windows),
      (name: 'iOS', capabilities: PlatformCapabilities.ios),
    ]) {
      final gateway = _FakeSharedDownloads(supported: true);
      final port = DefaultTransferDownloadPort(
        downloadPaths: PlatformDownloadPathService(
          sharedDownloads: gateway,
          capabilities: capabilities,
        ),
        sharedDownloads: gateway,
        settings: SettingsStore(),
        capabilities: capabilities,
      );

      expect(
        await port.targetMode(),
        DownloadTargetMode.fixedDirectory,
        reason: name,
      );
      expect(gateway.supportChecks, 0, reason: name);
    }
  });

  test('sharedDownloadsGatewayProvider 可以被测试实现覆盖', () {
    final gateway = _FakeSharedDownloads(supported: false);
    final container = ProviderContainer(
      overrides: [sharedDownloadsGatewayProvider.overrideWithValue(gateway)],
    );
    addTearDown(container.dispose);

    expect(
      identical(container.read(sharedDownloadsGatewayProvider), gateway),
      isTrue,
    );
  });
}
