import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_controller.dart';
import 'core/backup/backup_service.dart';
import 'core/incoming_links.dart';
import 'core/notifications.dart';
import 'core/share_inbox.dart';
import 'core/transfer/transfer_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'foreground_service',
      channelName: '蓝云',
      channelDescription: '传输进行中时保持后台运行',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
      playSound: false,
      showBadge: false,
      showWhen: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
  final app = AppController();
  await app.init();
  final language = app.settings.language;
  final locale = language == 'zh'
      ? const Locale('zh')
      : language == 'en'
          ? const Locale('en')
          : null;
  await NotificationService.instance.init(locale);
  await NotificationService.instance.consumeLaunchDetails();
  await SharedInbox.instance.init();
  await IncomingLinks.instance.init();
  // 自动备份：按每天/每周频率在启动时补一次，失败只记录不打扰。
  unawaited(BackupService.of(app).maybeAutoBackup());
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: TransferManager(app)),
      ],
      child: const LanCloudApp(),
    ),
  );
}
