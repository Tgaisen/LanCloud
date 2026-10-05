import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/l10n.dart';

/// 通知服务：传输进度与完成提醒。
///
/// 通知文案通过 [i18n] 跟随界面语言，由 RootShell 在每次构建时刷新；
/// 初始化时也会按当前设置的语言加载一次。
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// 当前界面语言（用于通知文案）。
  static AppLocalizations? i18n;

  /// 点击传输相关通知时回调（跳转传输视图），由 RootShell 注入。
  static void Function()? onOpenTransfers;

  /// 冷启动由通知拉起且目标是传输视图。
  static bool pendingTransfers = false;

  static const _progressId = 1000;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _doneId = 1001;
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);

  static const progressChannelId = 'transfers_progress';

  /// 传输完成 / 失败通知渠道。v2：默认不响铃、不振动（渠道建好后
  /// 系统不允许改声音，所以换新 id 让老安装也生效；用户仍可在
  /// 系统设置里自行改回响铃）。
  static const doneChannelId = 'transfers_done_v2';

  Future<void> init(Locale? locale) async {
    try {
      final resolved =
          locale ?? WidgetsBinding.instance.platformDispatcher.locale;
      try {
        i18n = await AppLocalizations.delegate.load(resolved);
      } catch (_) {}
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        settings: const InitializationSettings(android: android),
        onDidReceiveNotificationResponse: (response) {
          if (response.payload == 'transfers') onOpenTransfers?.call();
        },
      );
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidImpl?.createNotificationChannel(
        AndroidNotificationChannel(
          progressChannelId,
          i18n?.notifChannelProgress ?? '传输进度',
          description: i18n?.notifChannelProgressDesc ?? '下载与上传进行中的进度',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );
      await androidImpl?.createNotificationChannel(
        AndroidNotificationChannel(
          doneChannelId,
          i18n?.notifChannelDone ?? '传输完成',
          description: i18n?.notifChannelDoneDesc ?? '下载与上传完成或失败的提醒',
          importance: Importance.defaultImportance,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// 冷启动时读取通知启动信息：若由传输通知拉起则标记跳转传输视图。
  Future<void> consumeLaunchDetails() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      pendingTransfers =
          (details?.didNotificationLaunchApp ?? false) &&
          details?.notificationResponse?.payload == 'transfers';
    } catch (_) {
      pendingTransfers = false;
    }
  }

  Future<bool> hasPermission() async {
    try {
      final enabled = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
      return enabled ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> requestPermission() async {
    try {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      return granted ?? true;
    } catch (_) {
      return false;
    }
  }

  /// 传输中的汇总进度通知（约每秒节流一次）。
  void showProgress({
    required int count,
    int done = 0,
    required int percent,
    bool indeterminate = false,
  }) {
    if (!_ready || count <= 0) return;
    if (!indeterminate) {
      final now = DateTime.now();
      if (now.difference(_lastProgress) < const Duration(seconds: 1)) return;
      _lastProgress = now;
    }
    final strings = i18n;
    final body = [
      strings?.notifProgressBody(count) ?? '$count tasks in progress',
      if (done > 0) strings?.notifDoneCount(done) ?? '$done completed',
      if (!indeterminate) '$percent%',
    ].join(' · ');
    final clamped = percent < 0 ? 0 : (percent > 100 ? 100 : percent);
    _plugin.show(
      id: _progressId,
      title: strings?.notifProgressTitle ?? '传输中',
      body: body,
      payload: 'transfers',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          progressChannelId,
          strings?.notifChannelProgress ?? '传输进度',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
          onlyAlertOnce: true,
          ongoing: true,
          showProgress: true,
          maxProgress: 100,
          progress: indeterminate ? 0 : clamped,
          indeterminate: indeterminate,
        ),
      ),
    );
  }

  void cancelProgress() {
    if (!_ready) return;
    _plugin.cancel(id: _progressId);
  }

  void showDone({required bool upload, required String name}) {
    if (!_ready) return;
    final strings = i18n;
    _plugin.show(
      id: _doneId++,
      title: upload
          ? (strings?.notifUploadDone ?? '上传完成')
          : (strings?.notifDownloadDone ?? '下载完成'),
      body: name,
      payload: 'transfers',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          doneChannelId,
          strings?.notifChannelDone ?? '传输完成',
          importance: Importance.defaultImportance,
          priority: Priority.high,
          playSound: false,
          enableVibration: false,
          autoCancel: true,
        ),
      ),
    );
  }

  void showFailed({required String name, String error = ''}) {
    if (!_ready) return;
    final strings = i18n;
    _plugin.show(
      id: _doneId++,
      title: strings?.notifFailed ?? '传输失败',
      body: error.isEmpty ? name : '$name · $error',
      payload: 'transfers',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          doneChannelId,
          strings?.notifChannelDone ?? '传输完成',
          importance: Importance.defaultImportance,
          priority: Priority.high,
          playSound: false,
          enableVibration: false,
          autoCancel: true,
        ),
      ),
    );
  }
}
