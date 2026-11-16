import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_db.dart';
import '../favorite_monitor_models.dart';

enum FavoriteCheckOperation { folderUpdates, shareAccess }

/// 收藏检测过程的外部副作用端口。
///
/// 真实实现负责前台服务进度通知和完成提醒；核心检测只通过这个窄接口触发，
/// 单元测试不会碰平台插件。
abstract interface class FavoriteMonitorReporter {
  Future<void> start({
    required int total,
    required FavoriteCheckOperation operation,
  });

  Future<void> progress({
    required int completed,
    required int total,
    required String name,
    required FavoriteCheckOperation operation,
  });

  Future<void> folderUpdated({
    required FavoriteItem favorite,
    required FavoriteFolderHead? head,
  });

  Future<void> folderUpdateCleared({required String ref});

  Future<void> finish({
    required int total,
    required int succeeded,
    required int failed,
  });
}

class NoopFavoriteMonitorReporter implements FavoriteMonitorReporter {
  const NoopFavoriteMonitorReporter();

  @override
  Future<void> start({
    required int total,
    required FavoriteCheckOperation operation,
  }) async {}

  @override
  Future<void> progress({
    required int completed,
    required int total,
    required String name,
    required FavoriteCheckOperation operation,
  }) async {}

  @override
  Future<void> folderUpdated({
    required FavoriteItem favorite,
    required FavoriteFolderHead? head,
  }) async {}

  @override
  Future<void> folderUpdateCleared({required String ref}) async {}

  @override
  Future<void> finish({
    required int total,
    required int succeeded,
    required int failed,
  }) async {}
}

final favoriteMonitorReporterProvider = Provider<FavoriteMonitorReporter>(
  (_) => const NoopFavoriteMonitorReporter(),
);
