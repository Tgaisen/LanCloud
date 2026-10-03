import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_controller.dart';
import 'core/app_log.dart';
import 'core/backup/backup_service.dart';
import 'core/incoming_links.dart';
import 'core/notifications.dart';
import 'core/share_inbox.dart';
import 'core/transfer/transfer_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 导航栏沉浸：Android 15+（API 35）系统强制 edge-to-edge，14 及以下
  // 需要显式开启，否则系统导航栏/状态栏会不透明地占掉一条（内容被顶开）。
  // 非 edgeToEdge 模式在 API 36 上会被系统忽略，这里保持与系统一致。
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // 运行日志：把异常与 debugPrint 写进本机文件，用户可在设置-隐私里导出
  await AppLog.instance.init();
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    AppLog.instance.error('flutter', details.exception, details.stack);
    defaultOnError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.instance.error('uncaught', error, stack);
    return true;
  };
  final defaultDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null && message.isNotEmpty) {
      AppLog.instance.log('print', message);
    }
    defaultDebugPrint(message, wrapWidth: wrapWidth);
  };
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
