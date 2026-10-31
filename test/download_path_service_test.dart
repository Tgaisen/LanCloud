import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/download_path_service.dart';
import 'package:lancloud/core/shared_downloads_gateway.dart';
import 'package:lancloud/core/shared_downloads_storage.dart';

class _FakePathService implements DownloadPathService {
  const _FakePathService(this.path);

  final String path;

  @override
  Future<String> defaultDownloadDirPath() async => path;
}

class _FakeSharedDownloads implements SharedDownloadsGateway {
  @override
  Future<String?> defaultDirectoryPath() async => null;

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<SharedDownloadedFile> save({
    required String sourcePath,
    required String fileName,
    required String mime,
    String jobId = '',
    void Function(int copied, int total)? onProgress,
  }) async => const SharedDownloadedFile(uri: '', name: '');
}

void main() {
  test('默认目录服务返回注入路径', () async {
    const path = '/virtual/LanCloud';
    const service = _FakePathService(path);

    expect(await service.defaultDownloadDirPath(), path);
  });

  test('downloadPathServiceProvider 可以被测试实现覆盖', () {
    const service = _FakePathService('/test/LanCloud');
    final container = ProviderContainer(
      overrides: [
        sharedDownloadsGatewayProvider.overrideWithValue(
          _FakeSharedDownloads(),
        ),
        downloadPathServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    expect(
      identical(container.read(downloadPathServiceProvider), service),
      isTrue,
    );
  });
}
