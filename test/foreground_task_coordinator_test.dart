import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/favorites/favorite_monitor_reporter_adapter.dart';
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
      title: '收藏检测',
      text: '1/3',
    );
    expect(backend.events, ['start:收藏检测:1/3']);

    coordinator.acquire(
      ForegroundTaskReason.transfers,
      title: '传输中',
      text: '2 个任务',
    );
    expect(backend.events.last, 'update:传输中:2 个任务');

    coordinator.update(
      ForegroundTaskReason.favoriteCheck,
      title: '收藏检测',
      text: '2/3',
    );
    // 传输保活优先展示，收藏检测结束不能覆盖传输通知。
    expect(backend.events.last, 'update:传输中:2 个任务');

    coordinator.release(ForegroundTaskReason.transfers);
    expect(backend.events.last, 'update:收藏检测:2/3');

    coordinator.release(ForegroundTaskReason.favoriteCheck);
    expect(backend.events.last, 'stop');
    expect(coordinator.activeReasons, isEmpty);
  });

  test('重复释放同一 reason 不会提前停止其它保活', () {
    final backend = _RecordingBackend();
    final coordinator = ForegroundTaskCoordinator(backend);
    coordinator.acquire(
      ForegroundTaskReason.transfers,
      title: '传输中',
      text: '1 个任务',
    );
    coordinator.release(ForegroundTaskReason.transfers);
    coordinator.release(ForegroundTaskReason.transfers);

    expect(backend.events, ['start:传输中:1 个任务', 'stop']);
  });

  test('收藏检测 reporter 开始和结束成对持有前台服务', () async {
    final backend = _RecordingBackend();
    final coordinator = ForegroundTaskCoordinator(backend);
    final reporter = AppFavoriteMonitorReporter(
      notifications: NotificationService.instance,
      foregroundTasks: coordinator,
    );

    await reporter.start(total: 3);
    expect(coordinator.activeReasons, {ForegroundTaskReason.favoriteCheck});
    expect(backend.events.single, startsWith('start:正在检测收藏夹更新:'));

    await reporter.finish(total: 3, succeeded: 2, failed: 1);
    expect(coordinator.activeReasons, isEmpty);
    expect(backend.events.last, 'stop');
  });
}
