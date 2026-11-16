import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/favorites/favorite_monitor_reporter_adapter.dart';
import 'package:lancloud/core/favorites/favorite_monitor_reporter.dart';
import 'package:lancloud/core/foreground_task_coordinator.dart';
import 'package:lancloud/core/notifications.dart';

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

void main() {
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
