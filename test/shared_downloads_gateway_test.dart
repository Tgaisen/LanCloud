import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/shared_downloads_gateway.dart';
import 'package:lancloud/core/shared_downloads_storage.dart';

class _FakeSharedDownloads implements SharedDownloadsGateway {
  _FakeSharedDownloads({required this.supported, this.directoryPath});

  final bool supported;
  final String? directoryPath;
  var supportChecks = 0;

  @override
  Future<bool> isSupported() async {
    supportChecks += 1;
    return supported;
  }

  @override
  Future<String?> defaultDirectoryPath() async => directoryPath;

  @override
  Future<SharedDownloadedFile> save({
    required String sourcePath,
    required String fileName,
    required String mime,
    String jobId = '',
    void Function(int copied, int total)? onProgress,
  }) async => const SharedDownloadedFile(uri: 'content://saved', name: 'saved');
}

void main() {
  test('AppController 使用注入的公共 Downloads 能力解析默认目录', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const path = '/storage/emulated/0/Download/LanCloud';
    final app = AppController(
      sharedDownloads: _FakeSharedDownloads(
        supported: true,
        directoryPath: path,
      ),
    );
    addTearDown(app.dispose);

    expect(await app.defaultDownloadDirPath(), path);
  });

  test('AppController 在 Android 未设置目录时查询注入能力', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final gateway = _FakeSharedDownloads(supported: true);
    final app = AppController(sharedDownloads: gateway);
    addTearDown(app.dispose);

    await app.downloadTargetMode();

    expect(gateway.supportChecks, 1);
  });

  test('sharedDownloadsGatewayProvider 可以被测试实现覆盖', () {
    final gateway = _FakeSharedDownloads(supported: false);
    final container = ProviderContainer(
      overrides: [
        sharedDownloadsGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);

    expect(
      identical(container.read(sharedDownloadsGatewayProvider), gateway),
      isTrue,
    );
  });
}
