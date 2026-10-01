import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/lanzou_client.dart';
import '../app_controller.dart';
import '../notifications.dart';

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

  double get progress => total > 0 ? (received / total).clamp(0, 1).toDouble() : 0;
}

class TransferManager extends ChangeNotifier {
  TransferManager(this._app) {
    _restore();
  }

  static const int maxUploads = 1;
  static const int maxDownloads = 3;

  final AppController _app;
  final List<TransferTask> tasks = [];
  int _seq = 0;

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
        if (status == TransferStatus.running || status == TransferStatus.queued) {
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
      tasks.where((t) => t.kind == kind).toList().reversed.toList();

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
        .where((t) =>
            t.status == TransferStatus.done ||
            t.status == TransferStatus.canceled)
        .map((t) => t.id)
        .toList();
    tasks.removeWhere((t) =>
        t.status == TransferStatus.done ||
        t.status == TransferStatus.canceled);
    for (final id in removed) {
      _app.db.deleteTransfer(id);
    }
    notifyListeners();
  }

  TransferTask? _find(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _pump() {
    var runningUploads = tasks
        .where((t) => t.kind == TransferKind.upload && t.status == TransferStatus.running)
        .length;
    var runningDownloads = tasks
        .where((t) => t.kind == TransferKind.download && t.status == TransferStatus.running)
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
      if (task.status != TransferStatus.canceled) task.status = TransferStatus.done;
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
      ns.showDone(
        upload: task.kind == TransferKind.upload,
        name: task.name,
      );
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
    final path = await _app.uniqueSavePath(task.name);
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
    task.savedPath = path;
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
  }

  String _dioMessage(DioException e) {
    final status = e.response?.statusCode;
    if (status != null) return '网络错误（HTTP $status）';
    return e.message ?? '网络错误';
  }
}
