import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/download_target.dart';

void main() {
  group('resolveDownloadTargetMode', () {
    test('显式 SAF 目录优先', () {
      expect(
        resolveDownloadTargetMode(
          isAndroid: true,
          supportsSharedDownloads: true,
          directory: '/storage/emulated/0/Documents',
          treeUri: 'content://tree/primary%3ABaiduNetdisk',
        ),
        DownloadTargetMode.safDirectory,
      );
    });

    test('固定路径设置优先于默认公共 Downloads', () {
      expect(
        resolveDownloadTargetMode(
          isAndroid: true,
          supportsSharedDownloads: true,
          directory: '/storage/emulated/0/Documents',
        ),
        DownloadTargetMode.fixedDirectory,
      );
    });

    test('Android 10+ 未设置目录时使用公共 Downloads', () {
      expect(
        resolveDownloadTargetMode(
          isAndroid: true,
          supportsSharedDownloads: true,
        ),
        DownloadTargetMode.sharedDownloads,
      );
    });

    test('Android 9 及以下未设置目录时退回应用专属目录', () {
      expect(
        resolveDownloadTargetMode(
          isAndroid: true,
          supportsSharedDownloads: false,
        ),
        DownloadTargetMode.appDirectory,
      );
    });

    test('非 Android 平台继续使用普通路径', () {
      expect(
        resolveDownloadTargetMode(
          isAndroid: false,
          supportsSharedDownloads: false,
        ),
        DownloadTargetMode.fixedDirectory,
      );
    });
  });
}
