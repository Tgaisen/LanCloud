import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/favorites/favorite_monitor_reporter_adapter.dart';
import 'package:lancloud/core/favorites/favorite_monitor_reporter.dart';
import 'package:lancloud/core/foreground_task_coordinator.dart';
import 'package:lancloud/core/notifications.dart';
import 'package:lancloud/core/platform_capabilities.dart';

class _RecordingBackend implements ForegroundTaskBackend {
  final List<String> events = [];

  @override
  void start({required String title, required String text}) {
    events.add('start:$title:$text');
  }

  @override
  void update({required String title, required String text}) {
    events.add('update:$title:$text');
  }

  @override
  void stop() {
    events.add('stop');
  }
}

class _RecordingPlatform implements ForegroundTaskPlatform {
  final List<String> events = [];

  @override
  void start({required String title, required String text}) {
    events.add('start:$title:$text');
  }

  @override
  void update({required String title, required String text}) {
    events.add('update:$title:$text');
  }

  @override
  void stop() {
    events.add('stop');
  }
}

void main() {
  test('Android 前台后端转发插件调用', () {
    final platform = _RecordingPlatform();
    final backend = FlutterForegroundTaskBackend(
      capabilities: PlatformCapabilities.android,
      platform: platform,
    );

    backend.start(title: '运行中', text: '传输中');
    backend.update(title: '更新', text: '进度');
    backend.stop();

    expect(platform.events, ['start:运行中:传输中', 'update:更新:进度', 'stop']);
  });

  test('Windows 与 iOS 前台后端 fail closed', () {
    for (final (:name, :capabilities) in [
      (name: 'Windows', capabilities: PlatformCapabilities.windows),
      (name: 'iOS', capabilities: PlatformCapabilities.ios),
    ]) {
      final platform = _RecordingPlatform();
      final backend = FlutterForegroundTaskBackend(
        capabilities: capabilities,
        platform: platform,
      );

      backend.start(title: '运行中', text: '传输中');
      backend.update(title: '更新', text: '进度');
      backend.stop();

      expect(platform.events, isEmpty, reason: name);
    }
  });

  test('前台服务按 reason 共享，最后一个 reason 释放后才停止', () {
    final backend = _RecordingBackend();
    final coordinator = ForegroundTaskCoordinator(backend);

    coordinator.acquire(
      ForegroundTaskReason.favoriteCheck,
      title: '前台服务运行中',
      text: '后台任务运行中',
    );
    expect(backend.events, ['start:前台服务运行中:后台任务运行中']);

    coordinator.acquire(
      ForegroundTaskReason.transfers,
      title: '前台服务运行中',
      text: '后台任务运行中',
    );
    expect(backend.events.last, 'update:前台服务运行中:后台任务运行中');

    coordinator.update(
      ForegroundTaskReason.favoriteCheck,
      title: '前台服务运行中',
      text: '后台任务运行中',
    );
    expect(backend.events.last, 'update:前台服务运行中:后台任务运行中');

    coordinator.release(ForegroundTaskReason.transfers);
    expect(backend.events.last, 'update:前台服务运行中:后台任务运行中');

    coordinator.release(ForegroundTaskReason.favoriteCheck);
    expect(backend.events.last, 'stop');
    expect(coordinator.activeReasons, isEmpty);
  });

  test('重复释放同一 reason 不会提前停止其它保活', () {
    final backend = _RecordingBackend();
    final coordinator = ForegroundTaskCoordinator(backend);
    coordinator.acquire(
      ForegroundTaskReason.transfers,
      title: '前台服务运行中',
      text: '后台任务运行中',
    );
    coordinator.release(ForegroundTaskReason.transfers);
    coordinator.release(ForegroundTaskReason.transfers);

    expect(backend.events, ['start:前台服务运行中:后台任务运行中', 'stop']);
  });

  test('收藏检测 reporter 开始和结束成对持有前台服务', () async {
    final backend = _RecordingBackend();
    final coordinator = ForegroundTaskCoordinator(backend);
    final reporter = AppFavoriteMonitorReporter(
      notifications: NotificationService.instance,
      foregroundTasks: coordinator,
    );

    await reporter.start(
      total: 3,
      operation: FavoriteCheckOperation.folderUpdates,
    );
    expect(coordinator.activeReasons, {ForegroundTaskReason.favoriteCheck});
    expect(backend.events.single, 'start:前台服务运行中:点按打开应用');

    await reporter.finish(total: 3, succeeded: 2, failed: 1);
    expect(coordinator.activeReasons, isEmpty);
    expect(backend.events.last, 'stop');
  });
}
