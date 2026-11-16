import '../data/app_db.dart';
import '../favorite_monitor_models.dart';
import '../foreground_task_coordinator.dart';
import '../notifications.dart';
import '../../l10n/l10n.dart';
import 'favorite_monitor_reporter.dart';

class AppFavoriteMonitorReporter implements FavoriteMonitorReporter {
  const AppFavoriteMonitorReporter({
    required this.notifications,
    required this.foregroundTasks,
  });

  final NotificationService notifications;
  final ForegroundTaskCoordinator foregroundTasks;

  @override
  Future<void> start({
    required int total,
    required FavoriteCheckOperation operation,
  }) async {
    final title =
        NotificationService.i18n?.foregroundServiceRunningTitle ?? '前台服务运行中';
    final text =
        NotificationService.i18n?.foregroundServiceRunningBody ?? '点按打开应用';
    foregroundTasks.acquire(
      ForegroundTaskReason.favoriteCheck,
      title: title,
      text: text,
    );
    await notifications.showFavoriteCheckProgress(
      title: favoriteCheckProgressTitle(operation, NotificationService.i18n),
      completed: 0,
      total: total,
      name: '',
    );
  }

  @override
  Future<void> progress({
    required int completed,
    required int total,
    required String name,
    required FavoriteCheckOperation operation,
  }) async {
    final title =
        NotificationService.i18n?.foregroundServiceRunningTitle ?? '前台服务运行中';
    final text =
        NotificationService.i18n?.foregroundServiceRunningBody ?? '点按打开应用';
    foregroundTasks.update(
      ForegroundTaskReason.favoriteCheck,
      title: title,
      text: text,
    );
    await notifications.showFavoriteCheckProgress(
      title: favoriteCheckProgressTitle(operation, NotificationService.i18n),
      completed: completed,
      total: total,
      name: name,
    );
  }

  @override
  Future<void> folderUpdated({
    required FavoriteItem favorite,
    required FavoriteFolderHead? head,
  }) => notifications.showFavoriteFolderUpdate(
    ref: favorite.ref,
    name: favorite.displayName,
    time: head?.time ?? '',
  );

  @override
  Future<void> folderUpdateCleared({required String ref}) =>
      notifications.cancelFavoriteFolderUpdate(ref);

  @override
  Future<void> finish({
    required int total,
    required int succeeded,
    required int failed,
  }) async {
    foregroundTasks.release(ForegroundTaskReason.favoriteCheck);
    await notifications.cancelFavoriteCheckProgress();
  }
}

String favoriteCheckProgressTitle(
  FavoriteCheckOperation operation,
  AppLocalizations? strings,
) => switch (operation) {
  FavoriteCheckOperation.folderUpdates =>
    strings?.favoriteCheckProgressTitle ?? '正在检测收藏夹更新',
  FavoriteCheckOperation.shareAccess =>
    strings?.favoriteAccessCheckProgressTitle ?? '正在检测收藏夹失效项目',
};
