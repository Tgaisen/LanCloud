import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_support.dart';

enum ForegroundTaskReason { transfers, favoriteCheck, webdavBackup }

abstract interface class ForegroundTaskBackend {
  void start({required String title, required String text});

  void update({required String title, required String text});

  void stop();
}

class FlutterForegroundTaskBackend implements ForegroundTaskBackend {
  const FlutterForegroundTaskBackend();

  @override
  void start({required String title, required String text}) {
    if (!PlatformSupport.isMobile) return;
    unawaited(
      FlutterForegroundTask.startService(
        serviceId: 1000,
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: title,
        notificationText: text,
      ),
    );
  }

  @override
  void update({required String title, required String text}) {
    if (!PlatformSupport.isMobile) return;
    unawaited(
      FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      ),
    );
  }

  @override
  void stop() {
    if (!PlatformSupport.isMobile) return;
    unawaited(FlutterForegroundTask.stopService());
  }
}

/// 传输、收藏检测和 WebDAV 备份共享的唯一前台服务。
///
/// 每个功能只持有自己的 reason；只有所有 reason 都释放后才停止服务，避免
/// 收藏检测结束时误停仍在运行的传输保活。
class ForegroundTaskCoordinator {
  ForegroundTaskCoordinator(this._backend);

  static final ForegroundTaskCoordinator instance = ForegroundTaskCoordinator(
    const FlutterForegroundTaskBackend(),
  );

  final ForegroundTaskBackend _backend;
  final Map<ForegroundTaskReason, ({String title, String text})> _active = {};
  bool _running = false;

  @visibleForTesting
  Set<ForegroundTaskReason> get activeReasons => _active.keys.toSet();

  void acquire(
    ForegroundTaskReason reason, {
    required String title,
    required String text,
  }) {
    _active[reason] = (title: title, text: text);
    _sync();
  }

  void update(
    ForegroundTaskReason reason, {
    required String title,
    required String text,
  }) {
    if (!_active.containsKey(reason)) return;
    _active[reason] = (title: title, text: text);
    _sync();
  }

  void release(ForegroundTaskReason reason) {
    if (_active.remove(reason) == null) return;
    _sync();
  }

  void _sync() {
    if (_active.isEmpty) {
      if (_running) {
        _running = false;
        _backend.stop();
      }
      return;
    }
    final details =
        _active[ForegroundTaskReason.transfers] ??
        _active[ForegroundTaskReason.favoriteCheck] ??
        _active[ForegroundTaskReason.webdavBackup]!;
    if (_running) {
      _backend.update(title: details.title, text: details.text);
    } else {
      _running = true;
      _backend.start(title: details.title, text: details.text);
    }
  }
}

final foregroundTaskCoordinatorProvider = Provider<ForegroundTaskCoordinator>(
  (_) => ForegroundTaskCoordinator.instance,
);
