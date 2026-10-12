import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../api/lanzou_client.dart';
import '../app_controller.dart';
import '../notifications.dart';
import '../platform_support.dart';
import '../saf_storage.dart';
import '../saved_file.dart';

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
  final String url;
  final String referer;
  final Stream<List<int>> Function()? streamFactory;
  final int sourceSize;
  final LanzouClient? via;
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
          error = '应用已退出，任务中断';
        }
        final task = TransferTask(
          id: '${row['id']}',
          kind: kind,
          name: '${row['name']}',
          accountUid: '',
          folderId: '${row['folder_id'] ?? ''}',
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
      via: via,
      refId: refId,
    )..total = size;
    tasks.add(task);
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
    _persist(task);
    notifyListeners();
    _pump();
  }

  void retry(String id) {
    final task = _find(id);
    if (task == null || task.status != TransferStatus.failed) return;
    if (task.kind == TransferKind.upload && task.localFilePath.isEmpty) {
      task.error = '应用重启后无法继续该上传，请重新上传';
      notifyListeners();
      return;
    }
    if (task.kind == TransferKind.download && task.url.isEmpty) {
      task.error = '应用重启后请重新发起下载';
      notifyListeners();
      return;
    }
    task.status = TransferStatus.queued;
    task.error = null;
    task.received = 0;
    _persist(task);
    notifyListeners();
    _pump();
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
      task.error = e.message;
    } catch (e) {
      task.status = TransferStatus.failed;
      task.error = '$e';
    } finally {
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
    final done = tasks.where((t) => t.status == TransferStatus.done).length;
    for (final t in running) {
      received += t.received;
      if (t.total > 0) {
        total += t.total;
        known += 1;
      }
    }
    ns.showProgress(
      count: running.length,
      done: done,
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

  Future<void> _runUpload(TransferTask task) async {
    final client = _app.clientFor(task.accountUid);
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
    // SAF 模式（Android 用户授权目录）：先下到应用专属中转目录，
    // 完成后由原生写入授权目录；其它情况直接写目标路径。
    final treeUri = _app.safDownloadTree;
    final path = treeUri == null
        ? await _app.uniqueSavePath(task.name)
        : await _app.safTempFilePath(task.id, task.name);
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
          throw const LanzouException('下载被风控拦截，请稍后重试');
        }
      }
      if (treeUri == null) {
        task.savedPath = path;
        return;
      }
      // 用户已取消：不把中转文件写进授权目录
      if (task.status == TransferStatus.canceled ||
          task.cancelToken.isCancelled) {
        return;
      }
      await _exportToSafDir(task, treeUri, path);
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
      if (treeUri != null) {
        try {
          final tmp = File(path);
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
      }
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
    final status = e.response?.statusCode;
    if (status != null) return '网络错误（HTTP $status）';
    return e.message ?? '网络错误';
  }
}
