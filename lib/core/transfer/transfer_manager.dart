import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../l10n/l10n.dart';
import '../api/lanzou_client.dart';
import '../api/models.dart';
import '../download_target.dart';
import '../notifications.dart';
import '../platform_support.dart';
import '../saf_storage.dart';
import '../saved_file.dart';
import '../shared_downloads_gateway.dart';
import 'resumable_downloader.dart';
import 'transfer_dependencies.dart';

enum TransferKind { upload, download }

enum TransferStatus {
  queued,
  resolving,
  running,
  resuming,
  paused,
  saving,
  done,
  failed,
  canceled,
}

class TransferTask {
  TransferTask({
    required this.id,
    required this.kind,
    required this.name,
    required this.accountUid,
    this.total = 0,
    this.folderId = '',
    this.localFilePath = '',
    this.url = '',
    this.referer = '',
    this.pwd = '',
    this.streamFactory,
    this.sourceSize = 0,
    this.via,
    this.refId,
  });

  final String id;
  final TransferKind kind;
  final String name;
  final String accountUid;
  final String folderId;
  final String localFilePath;

  /// 解析后的直链。应用重启后为空，重试时会按 [referer] 重新解析。
  String url;

  /// 分享链接（下载来源）：重试时用它重新解析直链，也用作下载请求的 Referer。
  final String referer;

  /// 分享密码（无密码为空串）：应用重启后重试解析用。
  final String pwd;

  final Stream<List<int>> Function()? streamFactory;
  final int sourceSize;

  /// 下载走的客户端（带解析时拿到的 Cookie 等）；重启后重试时会换回
  /// 新解析用的客户端，所以不是 final。
  LanzouClient? via;
  final String? refId;
  CancelToken cancelToken = CancelToken();

  int total;
  int received = 0;
  DateTime _lastProgressNotification = DateTime.fromMillisecondsSinceEpoch(0);
  TransferStatus status = TransferStatus.queued;
  String? error;
  String? savedPath;
  String? partialPath;
  bool exporting = false;
  bool autoRefreshTried = false;

  /// 已被用户删除：进行中的任务结束后不再写回记录。
  bool removed = false;

  double get progress =>
      total > 0 ? (received / total).clamp(0, 1).toDouble() : 0;

  bool shouldNotifyProgress(DateTime now, Duration interval) {
    if (now.difference(_lastProgressNotification) < interval) return false;
    _lastProgressNotification = now;
    return true;
  }
}

class TransferManager extends ChangeNotifier {
  TransferManager.withDependencies(
    TransferDependencies dependencies, {
    TransferNotificationSink? notifications,
    SharedDownloadsGateway? sharedDownloads,
    TransferDownloader? downloader,
    this._progressUpdateInterval = const Duration(seconds: 1),
  }) : _dependencies = dependencies,
       _notifications = notifications ?? NotificationService.instance,
       _sharedDownloads =
           sharedDownloads ?? const PlatformSharedDownloadsGateway(),
       _downloader =
           downloader ??
           DioTransferDownloader(
             segmentConnectionsProvider: () =>
                 dependencies.settings.downloadConnections,
           ) {
    _restore();
  }

  static const int maxUploads = 1;
  static const int maxDownloads = 3;

  final TransferDependencies _dependencies;
  final Duration _progressUpdateInterval;
  final TransferNotificationSink _notifications;
  final SharedDownloadsGateway _sharedDownloads;
  final TransferDownloader _downloader;
  final List<TransferTask> tasks = [];
  final List<void Function(TransferTask)> _taskListeners = [];
  int _seq = 0;
  bool _serviceRunning = false;
  int _serviceTaskCount = 0;

  /// 测试注入：重启后重试时用来重新解析直链；默认走账号端口的公开客户端。
  @visibleForTesting
  Future<DirectFile> Function(String shareUrl, String pwd)? debugResolveShare;

  /// 「已加入下载」标记的低频版本号：任务增删 / 状态变化时自增，下载中的进度
  /// 更新**不**触发。列表里的下载标记监听它，避免长列表跟着进度高频重建。
  final ValueNotifier<int> marksRevision = ValueNotifier(0);

  void _bumpMarks() => marksRevision.value += 1;

  void _reportProgress(TransferTask task, int received, int total) {
    task.received = received;
    if (total > 0) task.total = total;
    if (!task.shouldNotifyProgress(DateTime.now(), _progressUpdateInterval)) {
      return;
    }
    notifyListeners();
    _syncTaskNotification(task);
  }

  /// 某个文件的下载状态（用于「已添加下载」标记）：找最近一条匹配的下载任务，
  /// 已取消的不算。
  ///
  /// [key] 对网盘文件是 `"账号uid:文件id"`（匹配任务的 [TransferTask.refId]），
  /// 对分享文件是分享链接（匹配任务的 [TransferTask.referer]）。
  TransferTask? downloadMarkOf(String key) {
    if (key.isEmpty) return null;
    for (var i = tasks.length - 1; i >= 0; i--) {
      final task = tasks[i];
      if (task.kind != TransferKind.download) continue;
      if (task.status == TransferStatus.canceled) continue;
      if (task.refId == key || task.referer == key) return task;
    }
    return null;
  }

  void addTaskListener(void Function(TransferTask) listener) {
    _taskListeners.add(listener);
  }

  void removeTaskListener(void Function(TransferTask) listener) {
    _taskListeners.remove(listener);
  }

  Future<void> _restore() async {
    try {
      final rows = await _dependencies.store.loadTransfers();
      for (final row in rows) {
        final kind = '${row['kind']}' == 'upload'
            ? TransferKind.upload
            : TransferKind.download;
        final originalStatus = '${row['status']}';
        var status = TransferStatus.values.firstWhere(
          (s) => s.name == originalStatus,
          orElse: () => TransferStatus.failed,
        );
        if (status == TransferStatus.canceled) {
          _notifications.cancelTransferTask('${row['id']}');
          await _dependencies.store.deleteTransfer('${row['id']}');
          continue;
        }
        var error = '${row['error'] ?? ''}';
        if (status == TransferStatus.running ||
            status == TransferStatus.queued ||
            status == TransferStatus.resolving ||
            status == TransferStatus.resuming ||
            status == TransferStatus.saving) {
          status = TransferStatus.failed;
          error = NotificationService.i18n?.taskInterrupted ?? '应用已退出，任务中断';
        }
        final task = TransferTask(
          id: '${row['id']}',
          kind: kind,
          name: '${row['name']}',
          // 上传要带账号 Cookie；老记录没存账号时退回到当前激活账号
          accountUid: '${row['account'] ?? ''}'.isEmpty
              ? (_dependencies.accounts.activeUid ?? '')
              : '${row['account']}',
          folderId: '${row['folder_id'] ?? ''}',
          localFilePath: '${row['local_path'] ?? ''}',
          referer: '${row['referer'] ?? ''}',
          pwd: '${row['pwd'] ?? ''}',
          refId: '${row['ref'] ?? ''}'.isEmpty ? null : '${row['ref']}',
        );
        task.total = (row['total'] as int?) ?? 0;
        task.received = (row['received'] as int?) ?? 0;
        task.status = status;
        task.error = error.isEmpty ? null : error;
        final savedPath = '${row['saved_path'] ?? ''}';
        task.savedPath = savedPath.isEmpty ? null : savedPath;
        tasks.add(task);
        if (task.status.name != originalStatus) {
          await _persist(task);
          _notifications.cancelTransferTask(task.id);
        }
      }
      _bumpMarks();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persist(TransferTask task) async {
    if (task.removed) return;
    try {
      await _dependencies.store.saveTransfer(
        id: task.id,
        kind: task.kind == TransferKind.upload ? 'upload' : 'download',
        name: task.name,
        status: task.status.name,
        total: task.total,
        received: task.received,
        error: task.error ?? '',
        savedPath: task.savedPath ?? '',
        ref: task.refId ?? '',
        folderId: task.folderId,
        referer: task.referer,
        pwd: task.pwd,
        localPath: task.localFilePath,
        account: task.accountUid,
      );
    } catch (_) {}
  }

  List<TransferTask> byKind(TransferKind kind) =>
      tasks.where((t) => t.kind == kind).toList();

  void addUpload({
    required String name,
    required String folderId,
    String path = '',
    Stream<List<int>> Function()? streamFactory,
    int size = 0,
  }) {
    final uid = _dependencies.accounts.activeUid ?? '';
    final task = TransferTask(
      id: 'u${DateTime.now().millisecondsSinceEpoch}_${_seq++}',
      kind: TransferKind.upload,
      name: name,
      accountUid: uid,
      folderId: folderId,
      localFilePath: path,
      streamFactory: streamFactory,
      sourceSize: size,
    )..total = size;
    tasks.add(task);
    _persist(task);
    notifyListeners();
    _pump();
  }

  void addDownload({
    required String url,
    required String name,
    String accountUid = '',
    String referer = '',
    String pwd = '',
    int size = 0,
    LanzouClient? via,
    String? refId,
  }) {
    final task = TransferTask(
      id: 'd${DateTime.now().millisecondsSinceEpoch}_${_seq++}',
      kind: TransferKind.download,
      name: name,
      accountUid: accountUid.isEmpty
          ? (_dependencies.accounts.activeUid ?? '')
          : accountUid,
      url: url,
      referer: referer,
      pwd: pwd,
      via: via,
      refId: refId,
    )..total = size;
    tasks.add(task);
    _bumpMarks();
    _persist(task);
    notifyListeners();
    _pump();
  }

  /// 取消下载或上传等同于删除任务记录；取消后不再保留“已下载”状态。
  void cancel(String id) => removeTask(id);

  /// 暂停下载。只中止网络读取，已写入的 `.part` 文件保留供继续。
  void pause(String id) {
    final task = _find(id);
    if (task == null ||
        task.kind != TransferKind.download ||
        (task.status != TransferStatus.running &&
            task.status != TransferStatus.queued) ||
        task.exporting) {
      return;
    }
    task.status = TransferStatus.paused;
    if (task.cancelToken.isCancelled) {
      task.cancelToken = CancelToken();
    } else {
      task.cancelToken.cancel('user paused');
    }
    _bumpMarks();
    _persist(task);
    notifyListeners();
    _pump();
    _syncTaskNotification(task);
  }

  /// 批量暂停下载：每批只持久化和通知一次，避免整页随任务数反复重建。
  void pauseDownloads(Iterable<String> ids) {
    var changed = false;
    final changedTasks = <TransferTask>[];
    for (final id in ids.toSet()) {
      final task = _find(id);
      if (task == null ||
          task.kind != TransferKind.download ||
          (task.status != TransferStatus.running &&
              task.status != TransferStatus.queued) ||
          task.exporting) {
        continue;
      }
      task.status = TransferStatus.paused;
      if (task.cancelToken.isCancelled) {
        task.cancelToken = CancelToken();
      } else {
        task.cancelToken.cancel('user paused');
      }
      _persist(task);
      changed = true;
      changedTasks.add(task);
    }
    if (!changed) return;
    _bumpMarks();
    notifyListeners();
    _pump();
    for (final task in changedTasks) {
      _syncTaskNotification(task);
    }
  }

  /// 继续暂停的下载；断点位置由下载器读取 `.part` 文件长度确定。
  Future<String?> resume(String id) async {
    final task = _find(id);
    if (task == null ||
        task.kind != TransferKind.download ||
        task.status != TransferStatus.paused) {
      return null;
    }
    task.status = TransferStatus.resuming;
    task.error = null;
    _bumpMarks();
    _persist(task);
    notifyListeners();
    _syncTaskNotification(task);
    final message = await _ensureDownloadUrl(task);
    if (task.removed) return null;
    if (message != null) {
      task.status = TransferStatus.paused;
      task.error = message;
      _bumpMarks();
      _persist(task);
      notifyListeners();
      _syncTaskNotification(task);
      return message;
    }
    if (task.status != TransferStatus.resuming) return null;
    task.autoRefreshTried = false;
    task.status = TransferStatus.queued;
    task.error = null;
    _bumpMarks();
    _persist(task);
    notifyListeners();
    _syncTaskNotification(task);
    _pump();
    return null;
  }

  /// 批量恢复暂停的下载，返回无法恢复的任务数。
  ///
  /// 恢复可能需要重新解析直链，因此仍然逐项执行；单项 [resume] 会负责每次
  /// 状态变化的持久化与通知。
  Future<int> resumeDownloads(Iterable<String> ids) async {
    var failed = 0;
    for (final id in ids.toSet()) {
      final message = await resume(id);
      if (message != null) failed += 1;
    }
    return failed;
  }

  /// 重试失败任务。
  ///
  /// 下载任务在应用重启后只剩分享链接（[TransferTask.referer]）与密码，
  /// 这里先重新解析出直链再入队；解析要走网络，所以是异步的。
  /// 返回需要提示给用户的错误信息；成功入队（或无需处理）返回 null。
  Future<String?> retry(String id) async {
    final task = _find(id);
    if (task == null || task.status != TransferStatus.failed) return null;
    final expectedStatus = task.status;
    final i18n = NotificationService.i18n;
    if (task.kind == TransferKind.upload) {
      if (task.localFilePath.isNotEmpty) {
        // 源文件路径已持久化，重启后一般还在缓存目录里；被清理掉时提示重选
        if (!File(task.localFilePath).existsSync()) {
          final message = i18n?.retryUploadFileGone ?? '源文件已不存在，请重新选择文件上传';
          task.error = message;
          _persist(task);
          notifyListeners();
          return message;
        }
      } else if (task.streamFactory == null) {
        // 旧记录没留源文件路径，来源也只是一次性的流：没法继续
        final message = i18n?.retryUploadUnavailable ?? '应用重启后无法继续该上传，请重新上传';
        task.error = message;
        _persist(task);
        notifyListeners();
        return message;
      }
      // 上传必须带账号 Cookie：账号被移除、或记录里没有可用账号时先拦下，
      // 别发出请求让服务端回 "login not"
      if (_uploadAccountUid(task).isEmpty) {
        final message = i18n?.uploadNeedLogin ?? '请先登录后再上传';
        task.error = message;
        _persist(task);
        notifyListeners();
        return message;
      }
    }
    if (task.kind == TransferKind.download) {
      final message = await _ensureDownloadUrl(task);
      if (message != null) return message;
      if (task.removed || task.status != expectedStatus) return null;
    }
    task.status = TransferStatus.queued;
    task.error = null;
    task.autoRefreshTried = false;
    if (task.kind == TransferKind.upload) task.received = 0;
    _bumpMarks();
    _persist(task);
    notifyListeners();
    _syncTaskNotification(task);
    _pump();
    return null;
  }

  Future<String?> _ensureDownloadUrl(TransferTask task) async {
    if (task.kind != TransferKind.download || task.url.isNotEmpty) return null;
    final i18n = NotificationService.i18n;
    if (task.referer.isEmpty) {
      final message = i18n?.retryUnavailable ?? '应用重启后请重新发起下载';
      task.error = message;
      _persist(task);
      notifyListeners();
      return message;
    }
    task.error = i18n?.retryResolving ?? '正在重新解析下载链接…';
    notifyListeners();
    try {
      final DirectFile direct;
      final resolver = debugResolveShare;
      if (resolver != null) {
        direct = await resolver(task.referer, task.pwd);
        task.via = null;
      } else {
        final client = _dependencies.accounts.publicClient;
        direct = await client.resolveFileShare(task.referer, pwd: task.pwd);
        task.via = client;
      }
      if (task.removed) return null;
      task.url = direct.url;
      return null;
    } catch (e) {
      if (task.removed) return null;
      final message = i18n?.retryResolveFailed('$e') ?? '重新解析下载链接失败：$e';
      task.error = message;
      _persist(task);
      notifyListeners();
      return message;
    }
  }

  /// 清空指定类型的已结束任务，返回被移除的任务快照供调用方处理本地文件。
  List<TransferTask> clearFinished(TransferKind kind) {
    final removed = tasks
        .where(
          (t) =>
              t.kind == kind &&
              (t.status == TransferStatus.done ||
                  t.status == TransferStatus.failed ||
                  t.status == TransferStatus.canceled),
        )
        .toList(growable: false);
    if (removed.isEmpty) return const <TransferTask>[];
    removeTasks([for (final task in removed) task.id]);
    return removed;
  }

  /// 删除一条传输记录：进行中的先取消，避免残留记录被写回。
  void removeTask(String id) {
    final task = _find(id);
    if (task == null) return;
    task.removed = true;
    if (task.status == TransferStatus.running ||
        task.status == TransferStatus.saving) {
      task.status = TransferStatus.canceled;
      if (!task.cancelToken.isCancelled) {
        task.cancelToken.cancel('removed');
      }
    } else {
      unawaited(_deletePartial(task));
    }
    tasks.remove(task);
    _notifications.cancelTransferTask(task.id);
    _dependencies.store.deleteTransfer(id).catchError((_) {});
    _bumpMarks();
    notifyListeners();
    _pump();
  }

  /// 批量删除传输记录：一次通知、一次落库，列表整体刷新一遍
  /// （逐条删时每条都会重播一次列表动画，条目多时又卡又乱）。
  void removeTasks(List<String> ids) {
    final removed = <String>[];
    for (final id in ids) {
      final task = _find(id);
      if (task == null) continue;
      task.removed = true;
      if (task.status == TransferStatus.running ||
          task.status == TransferStatus.saving) {
        task.status = TransferStatus.canceled;
        if (!task.cancelToken.isCancelled) {
          task.cancelToken.cancel('removed');
        }
      } else {
        unawaited(_deletePartial(task));
      }
      tasks.remove(task);
      _notifications.cancelTransferTask(task.id);
      removed.add(id);
    }
    if (removed.isEmpty) return;
    _dependencies.store.deleteTransfers(removed).catchError((_) {});
    _bumpMarks();
    notifyListeners();
    _pump();
  }

  TransferTask? _find(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _pump() {
    var runningUploads = tasks
        .where(
          (t) =>
              t.kind == TransferKind.upload &&
              t.status == TransferStatus.running,
        )
        .length;
    var runningDownloads = tasks
        .where(
          (t) =>
              t.kind == TransferKind.download &&
              (t.status == TransferStatus.running ||
                  t.status == TransferStatus.resolving ||
                  t.status == TransferStatus.resuming),
        )
        .length;
    for (final task in tasks) {
      if (task.status != TransferStatus.queued) continue;
      if (task.kind == TransferKind.upload &&
          runningUploads < _dependencies.settings.maxUploads) {
        runningUploads += 1;
        _start(task);
      } else if (task.kind == TransferKind.download &&
          runningDownloads < _dependencies.settings.maxDownloads) {
        runningDownloads += 1;
        _start(task);
      }
    }
    _syncForegroundService();
  }

  /// 有进行中任务时启动前台服务保持后台传输；全部结束则停止服务。
  void _syncForegroundService() {
    // 前台服务是 Android / iOS 的能力，桌面端不需要（也没有这个插件）。
    if (!PlatformSupport.isMobile) return;
    final activeCount = tasks
        .where((task) => _isActiveTransferStatus(task.status))
        .length;
    final i18n = NotificationService.i18n;
    final title = i18n?.notifProgressTitle ?? '传输中';
    final text =
        i18n?.notifProgressBody(activeCount) ??
        '$activeCount tasks in progress';
    if (activeCount > 0 && !_serviceRunning) {
      _serviceRunning = true;
      _serviceTaskCount = activeCount;
      FlutterForegroundTask.startService(
        serviceId: 1000,
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: title,
        notificationText: text,
      );
    } else if (activeCount > 0 &&
        _serviceRunning &&
        _serviceTaskCount != activeCount) {
      _serviceTaskCount = activeCount;
      FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    } else if (activeCount == 0 && _serviceRunning) {
      _serviceRunning = false;
      _serviceTaskCount = 0;
      FlutterForegroundTask.stopService();
    }
  }

  static bool _isActiveTransferStatus(TransferStatus status) =>
      status == TransferStatus.queued ||
      status == TransferStatus.resolving ||
      status == TransferStatus.running ||
      status == TransferStatus.resuming ||
      status == TransferStatus.saving;

  Future<void> _start(TransferTask task) async {
    if (task.cancelToken.isCancelled) task.cancelToken = CancelToken();
    final needsResolution =
        task.kind == TransferKind.download && task.url.isEmpty;
    task.status = needsResolution
        ? TransferStatus.resolving
        : TransferStatus.running;
    task.error = null;
    _bumpMarks();
    _persist(task);
    notifyListeners();
    _syncTaskNotification(task);
    try {
      if (task.kind == TransferKind.upload) {
        await _runUpload(task);
      } else {
        if (needsResolution) {
          final message = await _ensureDownloadUrl(task);
          if (task.removed || task.status != TransferStatus.resolving) return;
          if (message != null) {
            task.status = TransferStatus.failed;
            task.error = message;
            return;
          }
          task.status = TransferStatus.running;
          task.error = null;
          _bumpMarks();
          _persist(task);
          notifyListeners();
          _syncTaskNotification(task);
        }
        await _runDownload(task);
      }
      if (task.status != TransferStatus.canceled &&
          task.status != TransferStatus.paused) {
        task.status = TransferStatus.done;
      }
    } on DioException catch (e) {
      if (task.status == TransferStatus.paused) {
        // 暂停保留当前状态，等用户继续。
      } else if (task.status == TransferStatus.canceled ||
          CancelToken.isCancel(e)) {
        task.status = TransferStatus.canceled;
      } else if (task.kind == TransferKind.download &&
          task.referer.isNotEmpty &&
          !task.autoRefreshTried &&
          _shouldRefreshDirectUrl(e.response?.statusCode)) {
        task.autoRefreshTried = true;
        task.url = '';
        task.via = null;
        final message = await _ensureDownloadUrl(task);
        if (task.status == TransferStatus.canceled ||
            task.status == TransferStatus.paused) {
          // 重新解析期间用户已经取消或暂停。
        } else if (message == null && !task.removed) {
          task.status = TransferStatus.queued;
          task.error = null;
        } else {
          task.status = TransferStatus.failed;
          task.error ??= message ?? e.message;
        }
      } else {
        task.status = TransferStatus.failed;
        task.error = _dioMessage(e);
      }
    } on LanzouException catch (e) {
      task.status = TransferStatus.failed;
      task.error = NotificationService.i18n?.lanzouError(e) ?? e.message;
    } catch (e) {
      task.status = TransferStatus.failed;
      task.error = '$e';
    } finally {
      _bumpMarks();
      _persist(task);
      notifyListeners();
      _pump();
      _syncTaskNotification(task);
      if (task.status == TransferStatus.done) {
        for (final listener in _taskListeners) {
          listener(task);
        }
      }
    }
  }

  /// 按任务和设置同步单条通知。进行中任务受“传输进度通知”控制，
  /// 完成 / 失败受“传输完成通知”控制。
  void _syncTaskNotification(TransferTask task) {
    // 上传完成后留通知意义不大；失败通知仍然保留，方便用户判断原因。
    if (task.kind == TransferKind.upload &&
        task.status == TransferStatus.done) {
      _notifications.cancelTransferTask(task.id);
      return;
    }
    final state = switch (task.status) {
      TransferStatus.resolving => TransferNotificationState.resolving,
      TransferStatus.resuming => TransferNotificationState.resuming,
      TransferStatus.running =>
        task.kind == TransferKind.upload
            ? TransferNotificationState.uploading
            : TransferNotificationState.downloading,
      TransferStatus.paused => TransferNotificationState.paused,
      TransferStatus.saving => TransferNotificationState.saving,
      TransferStatus.done => TransferNotificationState.done,
      TransferStatus.failed => TransferNotificationState.failed,
      TransferStatus.queued || TransferStatus.canceled => null,
    };
    if (task.removed || state == null) {
      _notifications.cancelTransferTask(task.id);
      return;
    }
    final terminal =
        state == TransferNotificationState.done ||
        state == TransferNotificationState.failed;
    final enabled = terminal
        ? _dependencies.settings.notifyDone
        : _dependencies.settings.notifyProgress;
    if (!enabled) {
      _notifications.cancelTransferTask(task.id);
      return;
    }
    _notifications.showTransferTask(
      TransferNotificationSnapshot(
        taskId: task.id,
        name: task.name,
        kind: task.kind == TransferKind.upload
            ? TransferNotificationKind.upload
            : TransferNotificationKind.download,
        state: state,
        received: task.received,
        total: task.total,
        savedPath: task.savedPath,
        error: task.error,
      ),
    );
  }

  /// 上传要用的账号 uid：任务自带账号优先，老记录退回到当前激活账号；
  /// 账号不在账号列表里（被移除 / 已登出）时返回空串。
  String _uploadAccountUid(TransferTask task) {
    final uid = task.accountUid.isEmpty
        ? (_dependencies.accounts.activeUid ?? '')
        : task.accountUid;
    if (uid.isEmpty || !_dependencies.accounts.hasAccount(uid)) return '';
    return uid;
  }

  Future<void> _runUpload(TransferTask task) async {
    final uid = _uploadAccountUid(task);
    if (uid.isEmpty) {
      throw LanzouException(
        NotificationService.i18n?.uploadNeedLogin ?? '请先登录后再上传',
      );
    }
    final client = _dependencies.accounts.clientFor(uid);
    await client.uploadFile(
      name: task.name,
      folderId: task.folderId,
      path: task.localFilePath.isEmpty ? null : task.localFilePath,
      streamFactory: task.streamFactory,
      size: task.sourceSize > 0 ? task.sourceSize : null,
      cancelToken: task.cancelToken,
      onProgress: (sent, total) => _reportProgress(task, sent, total),
    );
  }

  Future<void> _runDownload(TransferTask task) async {
    task.exporting = false;
    // SAF 目录和公共 Downloads 都先下到应用专属中转目录，完成后由原生
    // 流式写入目标；固定路径 / 应用专属目录仍可直接写。
    final target = await _dependencies.download.targetMode();
    final treeUri = target == DownloadTargetMode.safDirectory
        ? _dependencies.download.safTreeUri
        : null;
    final staged =
        treeUri != null || target == DownloadTargetMode.sharedDownloads;
    final path = staged
        ? await _dependencies.download.partialFilePath(
            task.id,
            task.name,
            staged: true,
          )
        : await _dependencies.download.partialFilePath(
            task.id,
            task.name,
            staged: false,
          );
    task.partialPath = path;
    var completed = false;
    try {
      final dio = task.via?.dio ?? Dio();
      final result = await _downloader.download(
        dio: dio,
        url: task.url,
        partialPath: path,
        expectedTotal: task.total,
        cancelToken: task.cancelToken,
        headers: <String, String>{
          'User-Agent': kUserAgent,
          if (task.referer.isNotEmpty) 'Referer': task.referer,
        },
        receiveTimeout: const Duration(hours: 2),
        onProgress: (received, total) => _reportProgress(task, received, total),
      );
      if (result.total > 0) task.total = result.total;
      // 被风控拦截时会保存成校验页，这里识别并清理
      final file = File(path);
      if (await file.exists()) {
        task.received = await file.length();
        if (task.total <= 0) task.total = task.received;
        final head = await file
            .openRead(0, 512)
            .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
        final text = String.fromCharCodes(head);
        if (text.contains('acw_sc__v2') || text.startsWith('<!DOCTYPE')) {
          await file.delete();
          task.savedPath = null;
          throw LanzouException(
            NotificationService.i18n?.downloadBlocked ?? '下载被风控拦截，请稍后重试',
          );
        }
      }
      if (!staged) {
        final finalPath = await _dependencies.download.uniqueSavePath(
          task.name,
        );
        await file.rename(finalPath);
        task.savedPath = finalPath;
        task.partialPath = null;
        completed = true;
        return;
      }
      // 用户已取消：不把中转文件写进最终目录
      if (task.status == TransferStatus.canceled ||
          task.status == TransferStatus.paused ||
          task.cancelToken.isCancelled) {
        return;
      }
      task.status = TransferStatus.saving;
      task.exporting = true;
      task.received = 0;
      _bumpMarks();
      notifyListeners();
      _syncTaskNotification(task);
      await _persist(task);
      if (treeUri != null) {
        await _exportToSafDir(task, treeUri, path);
      } else {
        await _exportToSharedDownloads(task, path);
      }
      completed = true;
      // 复制阶段被打断不了：取消得晚的话把已经写入的文件清掉，保持
      // 「取消 = 没有文件」的直觉
      if (task.status == TransferStatus.canceled) {
        final saved = task.savedPath;
        task.savedPath = null;
        if (saved != null && saved.isNotEmpty) {
          await deleteSavedFile(saved);
        }
      }
    } finally {
      final preserveForResume =
          !completed &&
          !task.removed &&
          task.status != TransferStatus.canceled &&
          (task.status == TransferStatus.paused ||
              !task.cancelToken.isCancelled);
      if (!preserveForResume) await _deletePartialPath(task, path);
    }
  }

  Future<void> _deletePartial(TransferTask task) async {
    if (task.kind != TransferKind.download) return;
    try {
      final target = await _dependencies.download.targetMode();
      final path =
          task.partialPath ??
          await _partialPathFor(
            task,
            staged:
                target == DownloadTargetMode.sharedDownloads ||
                _dependencies.download.safTreeUri != null,
          );
      await _deletePartialPath(task, path);
    } catch (_) {}
  }

  Future<String> _partialPathFor(TransferTask task, {required bool staged}) =>
      _dependencies.download.partialFilePath(
        task.id,
        task.name,
        staged: staged,
      );

  Future<void> _deletePartialPath(TransferTask task, String path) async {
    try {
      await DioTransferDownloader.deleteState(path);
      if (task.partialPath == path) task.partialPath = null;
    } catch (_) {}
  }

  /// 把中转文件写入 Android 10+ 的公共 `Download/LanCloud`。
  Future<void> _exportToSharedDownloads(TransferTask task, String path) async {
    final i18n = NotificationService.i18n;
    // 下载阶段已到 100%，复制阶段重新从 0 开始显示
    task.received = 0;
    try {
      final saved = await _sharedDownloads.save(
        sourcePath: path,
        fileName: task.name,
        mime: mimeForFileName(task.name),
        jobId: task.id,
        onProgress: (copied, total) => _reportProgress(task, copied, total),
      );
      task.savedPath = saved.uri;
    } on PlatformException catch (e) {
      throw LanzouException(
        i18n?.safExportFailed(e.message ?? e.code) ??
            '写入下载目录失败：${e.message ?? e.code}',
      );
    }
  }

  /// 把中转文件写入用户授权的目录，复制进度直接更新任务进度。
  Future<void> _exportToSafDir(
    TransferTask task,
    String treeUri,
    String path,
  ) async {
    final i18n = NotificationService.i18n;
    // 下载阶段已到 100%，复制阶段重新从 0 开始显示
    task.received = 0;
    try {
      final saved = await SafStorage.export(
        treeUri: treeUri,
        sourcePath: path,
        fileName: task.name,
        mime: mimeForFileName(task.name),
        jobId: task.id,
        onProgress: (copied, total) => _reportProgress(task, copied, total),
      );
      task.savedPath = saved.uri;
    } on PlatformException catch (e) {
      if (e.code == 'perm_denied') {
        throw LanzouException(
          i18n?.safDirPermissionLost ?? '下载目录授权已失效，请在设置里重新选择下载目录',
        );
      }
      throw LanzouException(
        i18n?.safExportFailed(e.message ?? e.code) ??
            '写入下载目录失败：${e.message ?? e.code}',
      );
    }
  }

  String _dioMessage(DioException e) {
    final i18n = NotificationService.i18n;
    final status = e.response?.statusCode;
    if (status != null) {
      return i18n?.networkErrorHttp(status) ?? '网络错误（HTTP $status）';
    }
    return e.message ?? i18n?.networkError ?? '网络错误';
  }

  bool _shouldRefreshDirectUrl(int? statusCode) =>
      statusCode == 401 ||
      statusCode == 403 ||
      statusCode == 404 ||
      statusCode == 410;
}
