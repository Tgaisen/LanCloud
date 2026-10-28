import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../l10n/l10n.dart';
import '../api/lanzou_client.dart';
import '../api/models.dart';
import '../app_controller.dart';
import '../download_target.dart';
import '../notifications.dart';
import '../platform_support.dart';
import '../saf_storage.dart';
import '../saved_file.dart';
import '../shared_downloads_storage.dart';

enum TransferKind { upload, download }

enum TransferStatus { queued, running, done, failed, canceled }

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
  final CancelToken cancelToken = CancelToken();

  int total;
  int received = 0;
  TransferStatus status = TransferStatus.queued;
  String? error;
  String? savedPath;

  /// 已被用户删除：进行中的任务结束后不再写回记录。
  bool removed = false;

  double get progress =>
      total > 0 ? (received / total).clamp(0, 1).toDouble() : 0;
}

class TransferManager extends ChangeNotifier {
  TransferManager(this._app) {
    _restore();
  }

  static const int maxUploads = 1;
  static const int maxDownloads = 3;

  final AppController _app;
  final List<TransferTask> tasks = [];
  final List<void Function(TransferTask)> _taskListeners = [];
  int _seq = 0;
  bool _serviceRunning = false;

  /// 测试注入：重启后重试时用来重新解析直链；默认走 [AppController.publicClient]。
  @visibleForTesting
  Future<DirectFile> Function(String shareUrl, String pwd)? debugResolveShare;

  /// 「已下载」标记的低频版本号：任务增删 / 状态变化时自增，下载中的进度
  /// 更新**不**触发。列表里的下载标记监听它，避免长列表跟着进度高频重建。
  final ValueNotifier<int> marksRevision = ValueNotifier(0);

  void _bumpMarks() => marksRevision.value += 1;

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
      final rows = await _app.db.loadTransfers();
      for (final row in rows) {
        final kind = '${row['kind']}' == 'upload'
            ? TransferKind.upload
            : TransferKind.download;
        final originalStatus = '${row['status']}';
        var status = TransferStatus.values.firstWhere(
          (s) => s.name == originalStatus,
          orElse: () => TransferStatus.failed,
        );
        var error = '${row['error'] ?? ''}';
        if (status == TransferStatus.running ||
            status == TransferStatus.queued) {
          status = TransferStatus.failed;
          error = NotificationService.i18n?.taskInterrupted ?? '应用已退出，任务中断';
        }
        final task = TransferTask(
          id: '${row['id']}',
          kind: kind,
          name: '${row['name']}',
          // 上传要带账号 Cookie；老记录没存账号时退回到当前激活账号
          accountUid: '${row['account'] ?? ''}'.isEmpty
              ? (_app.activeUid ?? '')
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
        }
      }
      _bumpMarks();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persist(TransferTask task) async {
    if (task.removed) return;
    try {
      await _app.db.saveTransfer(
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
    final uid = _app.activeUid ?? '';
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
      accountUid: accountUid.isEmpty ? (_app.activeUid ?? '') : accountUid,
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

  void cancel(String id) {
    final task = _find(id);
    if (task == null) return;
    if (task.status == TransferStatus.queued) {
      task.status = TransferStatus.canceled;
    } else if (task.status == TransferStatus.running) {
      task.cancelToken.cancel('user canceled');
      task.status = TransferStatus.canceled;
    }
    _bumpMarks();
    _persist(task);
    notifyListeners();
    _pump();
  }

  /// 重试失败任务。
  ///
  /// 下载任务在应用重启后只剩分享链接（[TransferTask.referer]）与密码，
  /// 这里先重新解析出直链再入队；解析要走网络，所以是异步的。
  /// 返回需要提示给用户的错误信息；成功入队（或无需处理）返回 null。
  Future<String?> retry(String id) async {
    final task = _find(id);
    if (task == null || task.status != TransferStatus.failed) return null;
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
    if (task.kind == TransferKind.download && task.url.isEmpty) {
      if (task.referer.isEmpty) {
        // 旧记录没留分享链接：解析不回来，只能重新发起
        final message = i18n?.retryUnavailable ?? '应用重启后请重新发起下载';
        task.error = message;
        _persist(task);
        notifyListeners();
        return message;
      }
      // 解析期间列表里先给出反馈；失败时保留错误提示
      task.error = i18n?.retryResolving ?? '正在重新解析下载链接…';
      notifyListeners();
      try {
        final direct =
            await (debugResolveShare?.call(task.referer, task.pwd) ??
                _app.publicClient.resolveFileShare(
                  task.referer,
                  pwd: task.pwd,
                ));
        if (task.removed) return null;
        task.url = direct.url;
        task.via = _app.publicClient;
      } catch (e) {
        if (task.removed) return null;
        final message = i18n?.retryResolveFailed('$e') ?? '重新解析下载链接失败：$e';
        task.error = message;
        _persist(task);
        notifyListeners();
        return message;
      }
    }
    task.status = TransferStatus.queued;
    task.error = null;
    task.received = 0;
    _bumpMarks();
    _persist(task);
    notifyListeners();
    _pump();
    return null;
  }

  void clearFinished() {
    final removed = tasks
        .where(
          (t) =>
              t.status == TransferStatus.done ||
              t.status == TransferStatus.canceled,
        )
        .map((t) => t.id)
        .toList();
    tasks.removeWhere(
      (t) =>
          t.status == TransferStatus.done ||
          t.status == TransferStatus.canceled,
    );
    for (final id in removed) {
      _app.db.deleteTransfer(id).catchError((_) {});
    }
    _bumpMarks();
    notifyListeners();
  }

  /// 删除一条传输记录：进行中的先取消，避免残留记录被写回。
  void removeTask(String id) {
    final task = _find(id);
    if (task == null) return;
    task.removed = true;
    if (task.status == TransferStatus.running) {
      task.cancelToken.cancel('removed');
    }
    tasks.remove(task);
    _app.db.deleteTransfer(id).catchError((_) {});
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
      if (task.status == TransferStatus.running) {
        task.cancelToken.cancel('removed');
      }
      tasks.remove(task);
      removed.add(id);
    }
    if (removed.isEmpty) return;
    _app.db.deleteTransfers(removed).catchError((_) {});
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
              t.status == TransferStatus.running,
        )
        .length;
    for (final task in tasks) {
      if (task.status != TransferStatus.queued) continue;
      if (task.kind == TransferKind.upload &&
          runningUploads < _app.settings.maxUploads) {
        runningUploads += 1;
        _start(task);
      } else if (task.kind == TransferKind.download &&
          runningDownloads < _app.settings.maxDownloads) {
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
    final active = tasks.any(
      (t) =>
          t.status == TransferStatus.running ||
          t.status == TransferStatus.queued,
    );
    if (active && !_serviceRunning) {
      _serviceRunning = true;
      final i18n = NotificationService.i18n;
      FlutterForegroundTask.startService(
        serviceId: 1000,
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: i18n?.appName ?? '蓝云',
        notificationText: i18n?.notifProgressTitle ?? '传输中',
      );
    } else if (!active && _serviceRunning) {
      _serviceRunning = false;
      FlutterForegroundTask.stopService();
    }
  }

  Future<void> _start(TransferTask task) async {
    task.status = TransferStatus.running;
    task.error = null;
    _bumpMarks();
    _persist(task);
    notifyListeners();
    _syncProgressNotification();
    try {
      if (task.kind == TransferKind.upload) {
        await _runUpload(task);
      } else {
        await _runDownload(task);
      }
      if (task.status != TransferStatus.canceled) {
        task.status = TransferStatus.done;
      }
      if (task.kind == TransferKind.download &&
          task.refId != null &&
          task.status == TransferStatus.done) {
        await _app.db.markDownloaded(
          ref: task.refId!,
          name: task.name,
          path: task.savedPath ?? '',
        );
      }
    } on DioException catch (e) {
      if (task.status == TransferStatus.canceled || CancelToken.isCancel(e)) {
        task.status = TransferStatus.canceled;
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
      _notifyFinished(task);
      _syncProgressNotification();
      if (task.status == TransferStatus.done) {
        for (final listener in _taskListeners) {
          listener(task);
        }
      }
    }
  }

  /// 汇总所有运行中任务的进度，节流更新通知栏进度。
  void _syncProgressNotification() {
    final ns = NotificationService.instance;
    if (!_app.settings.notifyProgress) {
      ns.cancelProgress();
      return;
    }
    final running = tasks
        .where((t) => t.status == TransferStatus.running)
        .toList();
    if (running.isEmpty) {
      ns.cancelProgress();
      return;
    }
    var total = 0;
    var received = 0;
    var known = 0;
    for (final t in running) {
      received += t.received;
      if (t.total > 0) {
        total += t.total;
        known += 1;
      }
    }
    ns.showProgress(
      count: running.length,
      percent: total > 0 ? (received * 100) ~/ total : 0,
      indeterminate: known == 0,
    );
  }

  void _notifyFinished(TransferTask task) {
    if (!_app.settings.notifyDone) return;
    final ns = NotificationService.instance;
    if (task.status == TransferStatus.done) {
      ns.showDone(upload: task.kind == TransferKind.upload, name: task.name);
    } else if (task.status == TransferStatus.failed) {
      ns.showFailed(name: task.name, error: task.error ?? '');
    }
  }

  /// 上传要用的账号 uid：任务自带账号优先，老记录退回到当前激活账号；
  /// 账号不在账号列表里（被移除 / 已登出）时返回空串。
  String _uploadAccountUid(TransferTask task) {
    final uid = task.accountUid.isEmpty
        ? (_app.activeUid ?? '')
        : task.accountUid;
    if (uid.isEmpty || _app.accounts.byUid(uid) == null) return '';
    return uid;
  }

  Future<void> _runUpload(TransferTask task) async {
    final uid = _uploadAccountUid(task);
    if (uid.isEmpty) {
      throw LanzouException(
        NotificationService.i18n?.uploadNeedLogin ?? '请先登录后再上传',
      );
    }
    final client = _app.clientFor(uid);
    await client.uploadFile(
      name: task.name,
      folderId: task.folderId,
      path: task.localFilePath.isEmpty ? null : task.localFilePath,
      streamFactory: task.streamFactory,
      size: task.sourceSize > 0 ? task.sourceSize : null,
      cancelToken: task.cancelToken,
      onProgress: (sent, total) {
        task.received = sent;
        if (total > 0) task.total = total;
        notifyListeners();
        _syncProgressNotification();
      },
    );
  }

  Future<void> _runDownload(TransferTask task) async {
    // SAF 目录和公共 Downloads 都先下到应用专属中转目录，完成后由原生
    // 流式写入目标；固定路径 / 应用专属目录仍可直接写。
    final target = await _app.downloadTargetMode();
    final treeUri = target == DownloadTargetMode.safDirectory
        ? _app.safDownloadTree
        : null;
    final staged =
        treeUri != null || target == DownloadTargetMode.sharedDownloads;
    final path = staged
        ? await _app.safTempFilePath(task.id, task.name)
        : await _app.uniqueSavePath(task.name);
    try {
      final dio = task.via?.dio ?? Dio();
      await dio.download(
        task.url,
        path,
        cancelToken: task.cancelToken,
        onReceiveProgress: (received, total) {
          task.received = received;
          if (total > 0) task.total = total;
          notifyListeners();
          _syncProgressNotification();
        },
        options: Options(
          headers: {
            'User-Agent': kUserAgent,
            if (task.referer.isNotEmpty) 'Referer': task.referer,
          },
          receiveTimeout: const Duration(hours: 2),
        ),
      );
      if (task.total == 0) {
        final f = File(path);
        if (await f.exists()) task.total = await f.length();
      }
      // 被风控拦截时会保存成校验页，这里识别并清理
      final file = File(path);
      if (await file.exists()) {
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
        task.savedPath = path;
        return;
      }
      // 用户已取消：不把中转文件写进最终目录
      if (task.status == TransferStatus.canceled ||
          task.cancelToken.isCancelled) {
        return;
      }
      if (treeUri != null) {
        await _exportToSafDir(task, treeUri, path);
      } else {
        await _exportToSharedDownloads(task, path);
      }
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
      if (staged) {
        try {
          final tmp = File(path);
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
      }
    }
  }

  /// 把中转文件写入 Android 10+ 的公共 `Download/LanCloud`。
  Future<void> _exportToSharedDownloads(TransferTask task, String path) async {
    final i18n = NotificationService.i18n;
    // 下载阶段已到 100%，复制阶段重新从 0 开始显示
    task.received = 0;
    try {
      final saved = await SharedDownloadsStorage.save(
        sourcePath: path,
        fileName: task.name,
        mime: mimeForFileName(task.name),
        jobId: task.id,
        onProgress: (copied, total) {
          task.received = copied;
          if (total > 0) task.total = total;
          notifyListeners();
          _syncProgressNotification();
        },
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
        onProgress: (copied, total) {
          task.received = copied;
          if (total > 0) task.total = total;
          notifyListeners();
          _syncProgressNotification();
        },
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
}
