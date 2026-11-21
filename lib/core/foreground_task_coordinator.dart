import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_capabilities.dart';

enum ForegroundTaskReason { transfers, favoriteCheck, webdavBackup }

abstract interface class ForegroundTaskBackend {
  void start({required String title, required String text});

  void update({required String title, required String text});

  void stop();
}

abstract interface class ForegroundTaskPlatform {
  void start({required String title, required String text});

  void update({required String title, required String text});

  void stop();
}

final class _FlutterForegroundTaskPlatform implements ForegroundTaskPlatform {
  const _FlutterForegroundTaskPlatform();

  @override
  void start({required String title, required String text}) {
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
    unawaited(
      FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      ),
    );
  }

  @override
  void stop() {
    unawaited(FlutterForegroundTask.stopService());
  }
}

class FlutterForegroundTaskBackend implements ForegroundTaskBackend {
  FlutterForegroundTaskBackend({
    PlatformCapabilities? capabilities,
    ForegroundTaskPlatform? platform,
  }) : _capabilities = capabilities ?? PlatformCapabilities.current,
       _platform = platform ?? const _FlutterForegroundTaskPlatform();

  final PlatformCapabilities _capabilities;
  final ForegroundTaskPlatform _platform;

  @override
  void start({required String title, required String text}) {
    if (!_capabilities.supportsForegroundTask) return;
    _platform.start(title: title, text: text);
  }

  @override
  void update({required String title, required String text}) {
    if (!_capabilities.supportsForegroundTask) return;
    _platform.update(title: title, text: text);
  }

  @override
  void stop() {
    if (!_capabilities.supportsForegroundTask) return;
    _platform.stop();
  }
}

/// 传输、收藏检测和 WebDAV 备份共享的唯一前台服务。
///
/// 每个功能只持有自己的 reason；只有所有 reason 都释放后才停止服务，避免
/// 收藏检测结束时误停仍在运行的传输保活。
class ForegroundTaskCoordinator {
  ForegroundTaskCoordinator(this._backend);

  static final ForegroundTaskCoordinator instance = ForegroundTaskCoordinator(
    FlutterForegroundTaskBackend(),
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
