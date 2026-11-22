import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lancloud/core/foreground_task_coordinator.dart';
import 'package:lancloud/core/app_permissions.dart';
import 'package:lancloud/core/notifications.dart';
import 'package:lancloud/core/platform_capabilities.dart';
import 'package:lancloud/core/platform_support.dart';
import 'package:lancloud/core/saf_storage.dart';
import 'package:lancloud/core/shared_downloads_storage.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/main.dart';
import 'package:lancloud/ui/web_page.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('WebPage', () {
    testWidgets('should initialize the Android WebView plugin', (tester) async {
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await PlatformSupport.loadAndroidSdkInt();
      expect(PlatformSupport.androidSdkIntCached, greaterThanOrEqualTo(29));

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const WebPage(
            title: 'WebView smoke',
            url:
                'data:text/html;charset=utf-8,'
                '%3Ctitle%3ELanCloud%3C%2Ftitle%3E'
                '%3Cbody%3Esmoke%3C%2Fbody%3E',
          ),
        ),
      );
      await _pumpUntilFound(tester, find.byType(InAppWebView));

      expect(find.byType(InAppWebView), findsOneWidget);
      expect(find.text('WebView smoke'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }, skip: !Platform.isAndroid);
  });

  group('NotificationService', () {
    testWidgets('should initialize Android notification channels', (_) async {
      final service = NotificationService(
        capabilities: PlatformCapabilities.android,
      );

      await service.init(const Locale('zh'));

      expect(service.supported, isTrue);
      expect(service.supportsProgressNotifications, isTrue);
      expect(service.ready, isTrue);
    }, skip: !Platform.isAndroid);
  });

  group('AppPermissions', () {
    testWidgets('should query native Android permission states', (_) async {
      final permissions = AppPermissions(
        capabilities: PlatformCapabilities.android,
      );

      final status = await permissions.status();

      expect(status.install, isNot(PermissionState.unknown));
      expect(status.battery, isNot(PermissionState.unknown));
    }, skip: !Platform.isAndroid);
  });

  group('SharedDownloadsStorage', () {
    testWidgets('should write and delete a file in public Downloads', (
      _,
    ) async {
      SharedDownloadsStorage.resetCacheForTesting();
      final directory = Directory.systemTemp.createTempSync(
        'lancloud_shared_downloads_',
      );
      addTearDown(() {
        try {
          if (directory.existsSync()) {
            directory.deleteSync(recursive: true);
          }
        } catch (_) {}
      });
      final fileName =
          'lancloud_android_smoke_${DateTime.now().microsecondsSinceEpoch}.txt';
      final source = File('${directory.path}/$fileName');
      await source.writeAsString('LanCloud MediaStore smoke', flush: true);

      expect(await SharedDownloadsStorage.isSupported(), isTrue);
      expect(await SharedDownloadsStorage.defaultDirectoryPath(), isNotNull);

      final saved = await SharedDownloadsStorage.save(
        sourcePath: source.path,
        fileName: fileName,
        mime: 'text/plain',
      );
      expect(saved.uri, startsWith('content://'));
      expect(saved.name, contains('lancloud_android_smoke_'));
      expect(await SafStorage.deleteFile(saved.uri), isTrue);
    }, skip: !Platform.isAndroid);
  });

  group('ForegroundTaskCoordinator', () {
    testWidgets(
      'should keep the Android service alive until the last reason releases',
      (_) async {
        initializePlatformForegroundService(
          capabilities: PlatformCapabilities.android,
        );
        final coordinator = ForegroundTaskCoordinator(
          FlutterForegroundTaskBackend(
            capabilities: PlatformCapabilities.android,
          ),
        );
        addTearDown(() async {
          coordinator.release(ForegroundTaskReason.transfers);
          coordinator.release(ForegroundTaskReason.favoriteCheck);
          if (await FlutterForegroundTask.isRunningService) {
            await FlutterForegroundTask.stopService();
          }
        });

        if (await FlutterForegroundTask.isRunningService) {
          await FlutterForegroundTask.stopService();
        }

        coordinator.acquire(
          ForegroundTaskReason.transfers,
          title: '传输中',
          text: '正在下载测试文件',
        );
        await _waitForService(running: true);

        coordinator.acquire(
          ForegroundTaskReason.favoriteCheck,
          title: '检测收藏',
          text: '正在检测收藏文件夹',
        );
        coordinator.release(ForegroundTaskReason.transfers);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(await FlutterForegroundTask.isRunningService, isTrue);

        coordinator.release(ForegroundTaskReason.favoriteCheck);
        await _waitForService(running: false);
      },
      skip: !Platform.isAndroid,
    );
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('等待 Android 原生组件超时：$finder');
}

Future<void> _waitForService({required bool running}) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (await FlutterForegroundTask.isRunningService == running) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('前台服务状态未变为 ${running ? '运行中' : '已停止'}');
}
