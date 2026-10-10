import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import 'platform_support.dart';

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

  /// Windows 通知在 HKCU\Software\Classes\AppUserModelId 下注册的标识，
  /// 决定通知里显示的应用名。
  static const _windowsAppUserModelId = 'com.lancloud.lancloud';

  /// 通知点击回调的 CLSID（Windows 要求固定 GUID，随便生成一个后不再改）。
  static const _windowsCallbackGuid = '6f2d1c8a-0b7e-4a53-9e21-7c4f0d9b2a11';

  /// 传输完成 / 失败通知渠道。v2：默认不响铃、不振动（渠道建好后
  /// 系统不允许改声音，所以换新 id 让老安装也生效；用户仍可在
  /// 系统设置里自行改回响铃）。
  static const doneChannelId = 'transfers_done_v2';

  /// 随包发布的 Windows 图标（和 exe 用的是同一份 app_icon.ico）。
  static const _windowsIconAsset = 'windows/runner/resources/app_icon.ico';

  /// Windows 通知图标的磁盘路径。
  ///
  /// 系统只认注册表里 AUMID → IconUri 指向的那个文件，所以先把随包的
  /// app_icon.ico 落到应用数据目录（便携版所在目录会被搬走 / 删掉，数据
  /// 目录更稳），每次初始化覆盖一份，图标换了也能跟着更新。
  Future<String?> _windowsIconPath() async {
    if (!PlatformSupport.isWindows) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'app_icon.ico'));
      final data = await rootBundle.load(_windowsIconAsset);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> init(Locale? locale) async {
    try {
      final resolved =
          locale ?? WidgetsBinding.instance.platformDispatcher.locale;
      try {
        i18n = await AppLocalizations.delegate.load(resolved);
      } catch (_) {}
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      // Windows 端必须显式给初始化参数，否则 initialize 直接抛 ArgumentError
      final windows = WindowsInitializationSettings(
        // 通知里显示的应用名跟随界面语言（与 Android 的 app_name 一致）
        appName: i18n?.appName ?? 'LanCloud',
        appUserModelId: _windowsAppUserModelId,
        guid: _windowsCallbackGuid,
        // 没有这个路径，Windows 的 toast 就不显示应用图标
        iconPath: await _windowsIconPath(),
      );
      await _plugin.initialize(
        settings: InitializationSettings(android: android, windows: windows),
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
    // Windows 的 toast 没有「常驻进度」概念，每次刷新都会变成一条新通知，
    // 桌面端只保留「完成 / 失败」提醒，不做进度通知。
    if (PlatformSupport.isDesktop) return;
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
