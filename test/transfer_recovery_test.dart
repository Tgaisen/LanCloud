import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/transfer/transfer_dependencies.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_settings_port.dart';

import 'support/transfer_manager_test_support.dart';

void main() {
  group('TransferManager 暂停与继续', () {
    test('should 识别人机校验页后刷新直链并重新下载', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'lancloud-transfer-challenge',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final payload = List<int>.generate(2048, (index) => index % 193);
      final padding = List<String>.filled(700, 'x').join();
      final challenge =
          '<html><script>$padding'
                  "var arg1='7E8382F8567F0B54329AFED098ECFC4F8EAC90CD';"
                  "document.cookie='acw_sc__v2=token';"
                  '</script></html>'
              .codeUnits;
      final downloader = ChallengeThenSuccessDownloader(
        challenge: challenge,
        payload: payload,
      );
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: FakeTransferStore(),
          accounts: FakeTransferAccountPort(),
          download: FakeTransferDownloadPort(tempDir.path),
          settings: StoreTransferSettingsPort(
            SettingsStore()..maxDownloads = 1,
          ),
        ),
        downloader: downloader,
      );
      addTearDown(manager.dispose);
      var resolved = 0;
      manager.debugResolveShare = (url, pwd) async {
        resolved += 1;
        return DirectFile(
          name: 'archive.apk',
          url: 'https://cdn.example/fresh',
        );
      };

      manager.addDownload(
        url: 'https://cdn.example/stale',
        name: 'archive.apk',
        referer: 'https://example.com/share',
      );
      final task = manager.tasks.single;
      await waitForTransferCondition(
        () =>
            task.status == TransferStatus.done ||
            task.status == TransferStatus.failed,
      );

      expect(task.status, TransferStatus.done);
      expect(resolved, 1);
      expect(downloader.urls, <String>[
        'https://cdn.example/stale',
        'https://cdn.example/fresh',
      ]);
      expect(await File(task.savedPath!).readAsBytes(), payload);
    });

    test('should 将应用中退出时残留的保存状态恢复为失败', () async {
      final manager = TransferManager.withDependencies(
        TransferDependencies(
          store: FakeTransferStore([
            {
              'id': 'd1',
              'kind': 'download',
              'name': 'archive.zip',
              'status': 'saving',
            },
          ]),
          accounts: FakeTransferAccountPort(),
          download: const FakeTransferDownloadPort(''),
          settings: StoreTransferSettingsPort(SettingsStore()),
        ),
      );
      addTearDown(manager.dispose);

      await waitForTransferCondition(() => manager.tasks.isNotEmpty);
      expect(manager.tasks.single.status, TransferStatus.failed);
      expect(manager.tasks.single.error, '应用已退出，任务中断');
    });
  });
}
