import 'dart:convert';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:win32/win32.dart';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import 'app_info.dart';
import 'platform_capabilities.dart';
import 'platform_support.dart';

enum NotificationActionKind { transfers, openFile, favoriteFolder }

enum TransferNotificationKind { download, upload }

enum TransferNotificationState {
  resolving,
  resuming,
  downloading,
  uploading,
  paused,
  saving,
  done,
  failed,
}

/// 单个传输任务在通知栏中的状态快照。
class TransferNotificationSnapshot {
  const TransferNotificationSnapshot({
    required this.taskId,
    required this.name,
    required this.kind,
    required this.state,
    required this.received,
    required this.total,
    this.savedPath,
    this.error,
  });

  final String taskId;
  final String name;
  final TransferNotificationKind kind;
  final TransferNotificationState state;
  final int received;
  final int total;
  final String? savedPath;
  final String? error;

  bool get isTerminal =>
      state == TransferNotificationState.done ||
      state == TransferNotificationState.failed;
}

/// 传输管理器依赖的通知能力，测试可注入记录实现。
abstract interface class TransferNotificationSink {
  void showTransferTask(TransferNotificationSnapshot snapshot);

  void cancelTransferTask(String taskId);
}

/// WebDAV 备份期间的常驻进度通知端口。
abstract interface class WebdavBackupNotificationSink {
  Future<void> showWebdavBackupProgress();

  Future<void> cancelWebdavBackupProgress();
}

/// 通知点击后的类型化动作。
///
/// 兼容旧版本保存的 `transfers` payload；下载完成通知使用 JSON，避免
/// Windows 路径中的空格、中文和反斜杠破坏解析。
class NotificationAction {
  const NotificationAction._({
    required this.kind,
    this.path = '',
    this.name = '',
    this.ref = '',
  });

  static const transfers = NotificationAction._(
    kind: NotificationActionKind.transfers,
  );

  factory NotificationAction.openFile({
    required String path,
    required String name,
  }) => NotificationAction._(
    kind: NotificationActionKind.openFile,
    path: path,
    name: name,
  );

  factory NotificationAction.favoriteFolder({required String ref}) =>
      NotificationAction._(
        kind: NotificationActionKind.favoriteFolder,
        ref: ref,
      );

  final NotificationActionKind kind;
  final String path;
  final String name;
  final String ref;

  String encode() {
    if (kind == NotificationActionKind.transfers) return 'transfers';
    if (kind == NotificationActionKind.favoriteFolder) {
      return jsonEncode(<String, String>{
        'action': 'favoriteFolder',
        'ref': ref,
      });
    }
    return jsonEncode(<String, String>{
      'action': 'openFile',
      'path': path,
      'name': name,
    });
  }

  static NotificationAction? decode(String? payload) {
    if (payload == 'transfers') return transfers;
    if (payload == null || payload.isEmpty) return null;
    try {
      final value = jsonDecode(payload);
      if (value is! Map<String, Object?>) return null;
      if (value['action'] == 'favoriteFolder') {
        final ref = value['ref'];
        if (ref is! String || ref.isEmpty) return null;
        return NotificationAction.favoriteFolder(ref: ref);
      }
      if (value['action'] != 'openFile') return null;
      final path = value['path'];
      if (path is! String || path.isEmpty) return null;
      final name = value['name'];
      return NotificationAction.openFile(
        path: path,
        name: name is String ? name : '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// 通知服务：传输进度、收藏检测进度、WebDAV 备份进度和完成提醒。
///
/// 通知文案通过 [i18n] 跟随界面语言，由 RootShell 在每次构建时刷新；
/// 初始化时也会按当前设置的语言加载一次。
class NotificationService
    implements TransferNotificationSink, WebdavBackupNotificationSink {
  NotificationService({PlatformCapabilities? capabilities})
    : _capabilities = capabilities ?? PlatformCapabilities.current;

  static final NotificationService instance = NotificationService();

  final PlatformCapabilities _capabilities;

  /// 当前平台是否有完整接线的本地通知实现。
  bool get supported => _capabilities.supportsLocalNotifications;

  /// 通知插件是否已完成初始化；测试可在不触碰插件时读取。
  @visibleForTesting
  bool get ready => _ready;

  /// 当前界面语言（用于通知文案）。
  static AppLocalizations? i18n;

  /// 点击通知时回调，由 RootShell 注入。
  static void Function(NotificationAction action)? onAction;

  /// 应用尚未装配好回调时暂存通知动作。
  static NotificationAction? _pendingAction;

  static NotificationAction? takePendingAction() {
    final action = _pendingAction;
    _pendingAction = null;
    return action;
  }

  static void _handlePayload(String? payload) {
    final action = NotificationAction.decode(payload);
    if (action == null) return;
    final callback = onAction;
    if (callback == null) {
      _pendingAction = action;
    } else {
      callback(action);
    }
  }

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const progressChannelId = 'transfers_progress';
  static const favoriteCheckProgressChannelId = 'favorites_check_progress';
  static const favoriteUpdateChannelId = 'favorites_updates';
  static const webdavBackupProgressChannelId = 'webdav_backup_progress';

  /// Windows 通知在 HKCU\Software\Classes\AppUserModelId 下注册的标识，
  /// 决定通知里显示的应用名。
  static String get _windowsAppUserModelId =>
      currentAppBuildMode == AppBuildMode.release
      ? 'com.lancloud.lancloud'
      : 'com.lancloud.lancloud.${currentAppBuildMode.name}';

  /// 通知点击回调的 CLSID（Windows 要求固定 GUID，随便生成一个后不再改）。
  static const _windowsCallbackGuid = '6f2d1c8a-0b7e-4a53-9e21-7c4f0d9b2a11';

  /// 通知注册信息所在的注册表键（相对 HKCU）。
  static String get _windowsAumidKey =>
      r'Software\Classes\AppUserModelId\' + _windowsAppUserModelId;

  /// 传输完成 / 失败通知渠道。v2：默认不响铃、不振动（渠道建好后
  /// 系统不允许改声音，所以换新 id 让老安装也生效；用户仍可在
  /// 系统设置里自行改回响铃）。
  static const doneChannelId = 'transfers_done_v2';

  /// 随包发布的 Windows 图标：Release 用原图，Profile / Debug 用 Code 角标图。
  static String get _windowsIconAsset =>
      currentAppBuildMode == AppBuildMode.release
      ? 'windows/runner/resources/app_icon.ico'
      : 'windows/runner/resources/app_icon_badge.ico';

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
      final file = File(
        p.join(dir.path, 'app_icon_${currentAppBuildMode.name}.ico'),
      );
      final data = await rootBundle.load(_windowsIconAsset);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 删除 Windows 通知的注册表标识键（设置-清除数据-「注册表项目」）。
  ///
  /// 为在系统通知里显示应用名与图标，应用启动时会在
  /// `HKCU\Software\Classes\AppUserModelId\com.lancloud.lancloud`
  /// 下写入通知注册信息；该键只服务通知显示，删掉不影响账号与本机数据，
  /// 下次启动初始化通知时会按需重建。键本来就不存在时同样算干净。
  static bool removeWindowsRegistryEntry() {
    if (!PlatformSupport.isWindows) return false;
    final subKey = PCWSTR(_windowsAumidKey.toNativeUtf16());
    try {
      final result = RegDeleteTree(HKEY_CURRENT_USER, subKey);
      return result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND;
    } finally {
      calloc.free(subKey);
    }
  }

  Future<void> init(Locale? locale) async {
    if (!supported) {
      _ready = false;
      return;
    }
    try {
      final resolved =
          locale ?? WidgetsBinding.instance.platformDispatcher.locale;
      try {
        i18n = await AppLocalizations.delegate.load(resolved);
      } catch (_) {}
      final android = AndroidInitializationSettings(
        currentAppBuildMode == AppBuildMode.release
            ? '@mipmap/ic_launcher'
            : '@mipmap/ic_launcher_badged',
      );
      // Windows 端必须显式给初始化参数，否则 initialize 直接抛 ArgumentError
      final windows = WindowsInitializationSettings(
        // 通知里显示的应用名跟随界面语言和构建类型。
        appName:
            i18n?.currentAppDisplayName ??
            appDisplayName('LanCloud', currentAppBuildMode),
        appUserModelId: _windowsAppUserModelId,
        guid: _windowsCallbackGuid,
        // 没有这个路径，Windows 的 toast 就不显示应用图标
        iconPath: await _windowsIconPath(),
      );
      await _plugin.initialize(
        settings: InitializationSettings(android: android, windows: windows),
        onDidReceiveNotificationResponse: (response) {
          _handlePayload(response.payload);
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
      await androidImpl?.createNotificationChannel(
        AndroidNotificationChannel(
          favoriteCheckProgressChannelId,
          i18n?.favoriteCheckChannel ?? '收藏文件夹检测',
          description: i18n?.favoriteCheckChannelDesc ?? '检测收藏夹更新时的进度',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );
      await androidImpl?.createNotificationChannel(
        AndroidNotificationChannel(
          favoriteUpdateChannelId,
          i18n?.favoriteUpdateChannel ?? '收藏文件夹更新',
          description: i18n?.favoriteUpdateChannelDesc ?? '收藏文件夹有更新时提醒',
          importance: Importance.defaultImportance,
          playSound: false,
          enableVibration: false,
          showBadge: true,
        ),
      );
      await androidImpl?.createNotificationChannel(
        AndroidNotificationChannel(
          webdavBackupProgressChannelId,
          i18n?.webdavBackupProgressTitle ?? 'WebDAV 备份',
          description: i18n?.webdavBackupProgressBody ?? '正在备份',
          importance: Importance.low,
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

  /// 冷启动时读取通知启动信息并暂存类型化点击动作。
  Future<void> consumeLaunchDetails() async {
    if (!supported) return;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        _handlePayload(details?.notificationResponse?.payload);
      }
    } catch (_) {
      // 读取启动详情失败时保持无待处理动作。
    }
  }

  Future<bool> hasPermission() async {
    if (!supported) return false;
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
    if (!supported) return false;
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

  @override
  void showTransferTask(TransferNotificationSnapshot task) {
    if (!_ready) return;
    // Windows toast 没有常驻进度语义，桌面端仍只显示完成 / 失败提醒。
    if (PlatformSupport.isDesktop && !task.isTerminal) return;

    final strings = i18n;
    final hasTotal = task.total > 0;
    final showProgress = switch (task.state) {
      TransferNotificationState.done ||
      TransferNotificationState.failed => false,
      TransferNotificationState.paused => hasTotal,
      _ => true,
    };
    final indeterminate = switch (task.state) {
      TransferNotificationState.resolving ||
      TransferNotificationState.resuming => true,
      TransferNotificationState.downloading ||
      TransferNotificationState.uploading ||
      TransferNotificationState.saving => !hasTotal,
      _ => false,
    };
    final ongoing = switch (task.state) {
      TransferNotificationState.resolving ||
      TransferNotificationState.resuming ||
      TransferNotificationState.downloading ||
      TransferNotificationState.uploading ||
      TransferNotificationState.saving => true,
      _ => false,
    };
    final percent = hasTotal
        ? ((task.received * 100) ~/ task.total).clamp(0, 100)
        : 0;
    final payload =
        task.state == TransferNotificationState.done &&
            task.kind == TransferNotificationKind.download &&
            task.savedPath != null &&
            task.savedPath!.isNotEmpty
        ? NotificationAction.openFile(
            path: task.savedPath!,
            name: task.name,
          ).encode()
        : NotificationAction.transfers.encode();
    final channelId = task.isTerminal ? doneChannelId : progressChannelId;
    final channelName = task.isTerminal
        ? (strings?.notifChannelDone ?? '传输完成')
        : (strings?.notifChannelProgress ?? '传输进度');

    _plugin.show(
      id: notificationIdFor(task.taskId),
      title: task.name,
      body: _taskBody(task, strings),
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: task.isTerminal
              ? Importance.defaultImportance
              : Importance.low,
          priority: task.isTerminal ? Priority.high : Priority.low,
          playSound: false,
          enableVibration: false,
          onlyAlertOnce: true,
          ongoing: ongoing,
          autoCancel: !ongoing,
          showProgress: showProgress,
          maxProgress: 100,
          progress: showProgress && !indeterminate ? percent : 0,
          indeterminate: showProgress && indeterminate,
        ),
      ),
    );
  }

  @override
  void cancelTransferTask(String taskId) {
    if (!_ready) return;
    _plugin.cancel(id: notificationIdFor(taskId));
  }

  static const int favoriteCheckProgressNotificationId = 1150000000;
  static const String favoriteUpdateGroupKey = 'favorite_folder_updates';

  Future<void> showFavoriteCheckProgress({
    required String title,
    required int completed,
    required int total,
    required String name,
  }) async {
    if (!_ready) return;
    final strings = i18n;
    await _plugin.show(
      id: favoriteCheckProgressNotificationId,
      title: title,
      body:
          strings?.favoriteCheckProgressBody(completed, total, name) ??
          '$completed/$total · $name',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          favoriteCheckProgressChannelId,
          strings?.favoriteCheckChannel ?? '收藏文件夹检测',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
          showProgress: true,
          indeterminate: total <= 0,
          maxProgress: total > 0 ? total : 100,
          progress: total > 0 ? completed.clamp(0, total) : 0,
        ),
      ),
    );
  }

  Future<void> cancelFavoriteCheckProgress() async {
    if (!_ready) return;
    await _plugin.cancel(id: favoriteCheckProgressNotificationId);
  }

  static const int webdavBackupProgressNotificationId = 1160000000;

  @override
  Future<void> showWebdavBackupProgress() async {
    if (!_ready || PlatformSupport.isDesktop) return;
    final strings = i18n;
    await _plugin.show(
      id: webdavBackupProgressNotificationId,
      title: strings?.webdavBackupProgressTitle ?? 'WebDAV 备份',
      body: strings?.webdavBackupProgressBody ?? '正在备份',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          webdavBackupProgressChannelId,
          strings?.webdavBackupProgressTitle ?? 'WebDAV 备份',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
          showProgress: true,
          indeterminate: true,
          maxProgress: 100,
          progress: 0,
        ),
      ),
    );
  }

  @override
  Future<void> cancelWebdavBackupProgress() async {
    if (!_ready || PlatformSupport.isDesktop) return;
    await _plugin.cancel(id: webdavBackupProgressNotificationId);
  }

  Future<void> showFavoriteFolderUpdate({
    required String ref,
    required String name,
    required String time,
  }) async {
    if (!_ready) return;
    final strings = i18n;
    await _plugin.show(
      id: favoriteFolderNotificationIdFor(ref),
      title: name,
      body: time.isEmpty
          ? strings?.favoriteFolderUpdateNotificationBodyNoTime ?? '文件夹有更新'
          : strings?.favoriteFolderUpdateNotificationBody(time) ??
                '文件夹有更新 · $time',
      payload: NotificationAction.favoriteFolder(ref: ref).encode(),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          favoriteUpdateChannelId,
          strings?.favoriteUpdateChannel ?? '收藏文件夹更新',
          importance: Importance.defaultImportance,
          priority: Priority.high,
          playSound: false,
          enableVibration: false,
          groupKey: favoriteUpdateGroupKey,
          autoCancel: true,
        ),
      ),
    );
  }

  Future<void> cancelFavoriteFolderUpdate(String ref) async {
    if (!_ready) return;
    await _plugin.cancel(id: favoriteFolderNotificationIdFor(ref));
  }

  @visibleForTesting
  static int favoriteFolderNotificationIdFor(String ref) {
    var hash = 0x811c9dc5;
    for (final codeUnit in ref.codeUnits) {
      hash = ((hash ^ codeUnit) * 0x01000193) & 0x7fffffff;
    }
    return 1100000000 + hash % 40000000;
  }

  /// 任务字符串 ID 到 Android 32 位通知 ID 的稳定映射。
  @visibleForTesting
  static int notificationIdFor(String taskId) {
    var hash = 0x811c9dc5;
    for (final codeUnit in taskId.codeUnits) {
      hash = ((hash ^ codeUnit) * 0x01000193) & 0x7fffffff;
    }
    return 10000 + hash % 1000000000;
  }

  String _taskBody(
    TransferNotificationSnapshot task,
    AppLocalizations? strings,
  ) => switch (task.state) {
    TransferNotificationState.resolving => strings?.resolving ?? '解析中',
    TransferNotificationState.resuming => strings?.resumingDownload ?? '恢复中',
    TransferNotificationState.downloading => strings?.downloading ?? '下载中',
    TransferNotificationState.uploading => strings?.uploading ?? '上传中',
    TransferNotificationState.paused => strings?.paused ?? '已暂停',
    TransferNotificationState.saving => strings?.saving ?? '正在保存',
    TransferNotificationState.done => strings?.completed ?? '已完成',
    TransferNotificationState.failed => failureBodyFor(
      kind: task.kind,
      error: task.error,
      strings: strings,
    ),
  };

  @visibleForTesting
  static String failureBodyFor({
    required TransferNotificationKind kind,
    required String? error,
    AppLocalizations? strings,
  }) => formatTransferFailure(
    strings,
    upload: kind == TransferNotificationKind.upload,
    error: error,
  );
}
