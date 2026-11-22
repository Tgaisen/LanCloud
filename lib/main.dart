import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/app_composition_root.dart';
import 'core/app_data_reset.dart';
import 'core/app_environment.dart';
import 'core/app_log.dart';
import 'core/app_startup.dart';
import 'core/download_path_service.dart';
import 'core/favorites/favorite_monitor.dart';
import 'core/incoming_links.dart';
import 'core/notifications.dart';
import 'core/platform_capabilities.dart';
import 'core/platform_support.dart';
import 'core/share_inbox.dart';
import 'core/shared_downloads_gateway.dart';
import 'core/system_motion.dart';
import 'core/third_party_licenses.dart';
import 'core/transfer/transfer_manager_provider.dart';
import 'core/update/update_service.dart';

@visibleForTesting
Future<void> initializePlatformSystemUi({
  PlatformCapabilities? capabilities,
  Future<void> Function(SystemUiMode mode)? setSystemUiMode,
}) async {
  final currentCapabilities = capabilities ?? PlatformCapabilities.current;
  if (!currentCapabilities.supportsEdgeToEdgeSystemUi) return;
  await (setSystemUiMode ?? SystemChrome.setEnabledSystemUIMode)(
    SystemUiMode.edgeToEdge,
  );
}

@visibleForTesting
void initializePlatformForegroundService({
  PlatformCapabilities? capabilities,
  void Function()? initialize,
}) {
  final currentCapabilities = capabilities ?? PlatformCapabilities.current;
  if (!currentCapabilities.supportsForegroundTask) return;
  (initialize ?? _initializeForegroundService)();
}

void _initializeForegroundService() {
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'foreground_service',
      channelName: '蓝云',
      channelDescription: '传输、收藏检测或 WebDAV 备份进行中时保持后台运行',
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 上次“删除所有数据”若遇文件占用，会在日志和数据库初始化前补删。
  try {
    await PlatformAppDataResetService().completePendingReset();
  } catch (_) {
    // 清理失败不能阻止应用启动；保留重置标记，下次继续尝试。
  }
  // 开源许可页要展示的素材许可证（第三方图标集等）：先登记再运行
  registerThirdPartyLicenses();
  // 导航栏沉浸：Android 15+（API 35）系统强制 edge-to-edge，14 及以下
  // 需要显式开启，否则系统导航栏/状态栏会不透明地占掉一条（内容被顶开）。
  // 非 edgeToEdge 模式在 API 36 上会被系统忽略，这里保持与系统一致。
  // 桌面端没有系统栏，iOS 当前也不走 Android 的 edge-to-edge 初始化。
  unawaited(initializePlatformSystemUi());
  // 平台能力预热：Android SDK 级别（WebView 的合成方式按它判定，
  // 见 web_page.dart / web_login_page.dart）。留一行日志，
  // 排查「为什么这台设备的 WebView 表现不同」时能对上号。
  unawaited(
    PlatformSupport.loadAndroidSdkInt().then((value) {
      if (value != null) debugPrint('[LanCloud] androidSdkInt=$value');
    }),
  );
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
  // 只有能力矩阵确认前台任务后端完整时才初始化插件；桌面端关闭窗口即结束。
  initializePlatformForegroundService();
  const sharedDownloads = PlatformSharedDownloadsGateway();
  final downloadPaths = PlatformDownloadPathService(
    sharedDownloads: sharedDownloads,
  );
  final environment = AppEnvironment();
  final startup = AppStartup(environment: environment, onChanged: () {});
  await startup.initialize();
  final composition = AppCompositionRoot(
    environment: environment,
    reloadFromStorage: startup.reloadFromStorage,
    sharedDownloads: sharedDownloads,
    downloadPaths: downloadPaths,
  );
  // 系统「移除动画」：读一次并监听原生推送（华为等 ROM 的开关引擎看不到）
  SystemMotion.init();
  final language = environment.settingsState.store.language;
  final locale = language == 'zh'
      ? const Locale('zh')
      : language == 'en'
      ? const Locale('en')
      : null;
  await NotificationService.instance.init(locale);
  await NotificationService.instance.consumeLaunchDetails();
  await SharedInbox.instance.init();
  await IncomingLinks.instance.init();
  // 自动备份：按每天/每周频率在启动和回到前台时补一次，失败只记录不打扰。
  unawaited(composition.backupService.maybeAutoBackup());
  // Riverpod 更新试点：沿用已加载的设置对象，先恢复缓存再非阻塞检查更新。
  final updateContainer = composition.createContainer();
  // 生产消费端已迁到 Riverpod，但仍要在 runApp 前主动创建管理器，
  // 保持任务恢复与后台服务的启动顺序不变。
  updateContainer.read(transferManagerProvider);
  final updates = updateContainer.read(updateServiceProvider.notifier);
  await updates.initialize();
  unawaited(updates.maybeAutoCheck());
  final favoriteMonitor = updateContainer.read(
    favoriteMonitorProvider.notifier,
  );
  await favoriteMonitor.initialize();
  unawaited(favoriteMonitor.maybeAutoCheck());
  runApp(
    UncontrolledProviderScope(
      container: updateContainer,
      child: const LanCloudApp(),
    ),
  );
}
