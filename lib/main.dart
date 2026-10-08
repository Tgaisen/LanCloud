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
import 'core/platform_support.dart';
import 'core/share_inbox.dart';
import 'core/system_motion.dart';
import 'core/transfer/transfer_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 导航栏沉浸：Android 15+（API 35）系统强制 edge-to-edge，14 及以下
  // 需要显式开启，否则系统导航栏/状态栏会不透明地占掉一条（内容被顶开）。
  // 非 edgeToEdge 模式在 API 36 上会被系统忽略，这里保持与系统一致。
  // 桌面端没有系统栏，跳过。
  if (PlatformSupport.isMobile) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  // 运行日志：把异常与 debugPrint 写进本机文件，用户可在设置-隐私里导出
  await AppLog.instance.init();
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    // 记 details 而不是 exception：布局溢出这类报错没有堆栈，
    // 只有 details 里才带「出问题的组件」和上下文，否则日志定位不到界面。
    AppLog.instance.error('flutter', details.toString(), details.stack);
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
  // 前台服务只有 Android / iOS 需要（也是只有它们才有的插件）。
  // 桌面端窗口关掉 = 进程结束，不存在后台保活问题。
  if (PlatformSupport.isMobile) {
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
  }
  final app = AppController();
  await app.init();
  // 系统「移除动画」：读一次并监听原生推送（华为等 ROM 的开关引擎看不到）
  SystemMotion.init();
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
