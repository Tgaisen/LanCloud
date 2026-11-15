import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/lanzou_client.dart';
import '../api/models.dart';
import '../app_log_provider.dart';
import '../data/app_db.dart';
import '../data/app_db_provider.dart';
import '../favorite_monitor_models.dart';
import '../favorite_monitor_settings_state.dart';
import 'favorite_check_gateway.dart';
import 'favorite_monitor_reporter.dart';

typedef FavoriteMonitorClock = DateTime Function();

final favoriteMonitorClockProvider = Provider<FavoriteMonitorClock>(
  (_) => DateTime.now,
);

final favoriteMonitorProvider =
    NotifierProvider<FavoriteMonitor, FavoriteMonitorState>(
      FavoriteMonitor.new,
    );

final favoriteUpdateCountProvider = Provider<int>(
  (ref) =>
      ref.watch(favoriteMonitorProvider.select((state) => state.updateCount)),
);

final favoriteShareIssueCountProvider = Provider<int>(
  (ref) => ref.watch(
    favoriteMonitorProvider.select((state) => state.shareIssueCount),
  ),
);

final favoriteCheckRunningProvider = Provider<bool>(
  (ref) => ref.watch(favoriteMonitorProvider.select((state) => state.checking)),
);

@immutable
class FavoriteMonitorRunResult {
  const FavoriteMonitorRunResult({
    required this.total,
    required this.succeeded,
    required this.failed,
  });

  final int total;
  final int succeeded;
  final int failed;

  bool get hasFailures => failed > 0;
}

@immutable
class FavoriteMonitorState {
  const FavoriteMonitorState({
    this.checking = false,
    this.completed = 0,
    this.total = 0,
    this.currentName = '',
    this.updateCount = 0,
    this.shareIssueCount = 0,
    this.lastAttemptAt,
    this.lastCompletedAt,
    this.lastResult,
  });

  final bool checking;
  final int completed;
  final int total;
  final String currentName;
  final int updateCount;
  final int shareIssueCount;
  final DateTime? lastAttemptAt;
  final DateTime? lastCompletedAt;
  final FavoriteMonitorRunResult? lastResult;

  FavoriteMonitorState copyWith({
    bool? checking,
    int? completed,
    int? total,
    String? currentName,
    int? updateCount,
    int? shareIssueCount,
    DateTime? lastAttemptAt,
    DateTime? lastCompletedAt,
    FavoriteMonitorRunResult? lastResult,
  }) => FavoriteMonitorState(
    checking: checking ?? this.checking,
    completed: completed ?? this.completed,
    total: total ?? this.total,
    currentName: currentName ?? this.currentName,
    updateCount: updateCount ?? this.updateCount,
    shareIssueCount: shareIssueCount ?? this.shareIssueCount,
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
    lastResult: lastResult ?? this.lastResult,
  );
}

/// 收藏文件夹更新和收藏分享失效检测的唯一任务所有者。
class FavoriteMonitor extends Notifier<FavoriteMonitorState> {
  static const _keyLastAttempt = 'favorite_monitor_last_attempt_at';
  static const _keyLastCompleted = 'favorite_monitor_last_completed_at';
  static const _keyLastTotal = 'favorite_monitor_last_total';
  static const _keyLastSucceeded = 'favorite_monitor_last_succeeded';
  static const _keyLastFailed = 'favorite_monitor_last_failed';

  bool _initialized = false;
  bool _disposed = false;
  bool _runReserved = false;

  AppDb get _db => ref.read(appDbProvider);

  FavoriteMonitorSettingsState get _settings =>
      ref.read(favoriteMonitorSettingsStateProvider);

  FavoriteCheckGateway get _gateway => ref.read(favoriteCheckGatewayProvider);

  FavoriteMonitorReporter get _reporter =>
      ref.read(favoriteMonitorReporterProvider);

  DateTime get _now => ref.read(favoriteMonitorClockProvider)();

  @override
  FavoriteMonitorState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
    });
    return const FavoriteMonitorState();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final attempt = prefs.getInt(_keyLastAttempt);
      final completed = prefs.getInt(_keyLastCompleted);
      final total = prefs.getInt(_keyLastTotal);
      final succeeded = prefs.getInt(_keyLastSucceeded);
      final failed = prefs.getInt(_keyLastFailed);
      state = state.copyWith(
        lastAttemptAt: attempt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(attempt),
        lastCompletedAt: completed == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(completed),
        lastResult: total == null || succeeded == null || failed == null
            ? null
            : FavoriteMonitorRunResult(
                total: total,
                succeeded: succeeded,
                failed: failed,
              ),
      );
    } catch (_) {
      // 偏好存储不可用时只影响跨重启时间，不影响本次检测。
    }
    await refreshSummary();
  }

  Future<void> refreshSummary() async {
    try {
      final favorites = await _db.favorites();
      if (_disposed) return;
      updateSummaryFromFavorites(favorites);
    } catch (_) {
      // 数据库尚未就绪或读取失败时保留上一次摘要。
    }
  }

  /// 页面已经拿到收藏列表时直接更新摘要，避免再触发一次异步数据库查询。
  void updateSummaryFromFavorites(List<FavoriteItem> favorites) {
    if (_disposed) return;
    final updates = favorites
        .where(
          (item) =>
              item.kind == 'shareFolder' &&
              item.folderHasUpdate &&
              item.shareStatus.accessible,
        )
        .length;
    final issues = favorites
        .where(
          (item) =>
              (item.kind == 'shareFolder' || item.kind == 'shareFile') &&
              !item.shareStatus.accessible,
        )
        .length;
    if (updates == state.updateCount && issues == state.shareIssueCount) {
      return;
    }
    state = state.copyWith(updateCount: updates, shareIssueCount: issues);
  }

  /// 启动和回前台补检入口。只检查开关、到期时间和互斥状态，不创建 Timer。
  Future<bool> maybeAutoCheck() async {
    await initialize();
    if (!_settings.autoCheck || state.checking || _runReserved) return false;
    if (!favoriteMonitorCheckDue(
      lastAttemptAt: state.lastAttemptAt,
      now: _now,
      frequency: _settings.frequency,
    )) {
      return false;
    }
    return await checkFolders() != null;
  }

  /// 按设置范围检测收藏文件夹更新。
  Future<FavoriteMonitorRunResult?> checkFolders() async {
    if (!_reserveRun()) return null;
    try {
      await initialize();
      final settings = _settings;
      final scopedRefs = settings.checkRefs;
      final favorites = await _db.favorites();
      final targets = [
        for (final favorite in favorites)
          if (favorite.kind == 'shareFolder' &&
              (settings.checkAll || scopedRefs.contains(favorite.ref)))
            favorite,
      ];
      return await _run(targets, updateFolders: true);
    } finally {
      _finishReservedRun();
    }
  }

  /// 手动检测单个收藏文件夹；与批量任务共用同一把互斥锁。
  Future<FavoriteMonitorRunResult?> checkFolder(FavoriteItem favorite) async {
    if (favorite.kind != 'shareFolder' || !_reserveRun()) return null;
    try {
      await initialize();
      return await _run([favorite], updateFolders: true);
    } finally {
      _finishReservedRun();
    }
  }

  /// 检测所有分享文件 / 文件夹是否仍可访问。
  Future<FavoriteMonitorRunResult?> checkAllShareAccess() async {
    if (!_reserveRun()) return null;
    try {
      await initialize();
      final favorites = await _db.favorites();
      final targets = [
        for (final favorite in favorites)
          if (favorite.kind == 'shareFolder' || favorite.kind == 'shareFile')
            favorite,
      ];
      return await _run(targets, updateFolders: false);
    } finally {
      _finishReservedRun();
    }
  }

  bool _reserveRun() {
    if (state.checking || _runReserved) return false;
    _runReserved = true;
    return true;
  }

  void _finishReservedRun() {
    _runReserved = false;
    if (state.checking) {
      state = state.copyWith(checking: false, currentName: '');
    }
  }

  Future<FavoriteMonitorRunResult?> _run(
    List<FavoriteItem> targets, {
    required bool updateFolders,
  }) async {
    final startedAt = _now;
    state = state.copyWith(
      checking: true,
      completed: 0,
      total: targets.length,
      currentName: '',
      lastAttemptAt: startedAt,
    );
    await _persistLastAttempt(startedAt);
    await _safeReporter(() => _reporter.start(total: targets.length));

    var succeeded = 0;
    var failed = 0;
    var completed = 0;
    try {
      for (final target in targets) {
        if (_disposed) break;
        final favorite = await _db.favoriteByRef(target.ref);
        if (favorite == null) {
          completed += 1;
          state = state.copyWith(completed: completed, currentName: '');
          continue;
        }
        state = state.copyWith(
          completed: completed,
          currentName: favorite.displayName,
        );
        await _safeReporter(
          () => _reporter.progress(
            completed: completed,
            total: targets.length,
            name: favorite.displayName,
          ),
        );

        final checkedAt = _now.millisecondsSinceEpoch;
        var targetSucceeded = false;
        if (favorite.kind == 'shareFolder') {
          targetSucceeded = await _checkFolderTarget(
            favorite,
            checkedAt: checkedAt,
            updateSnapshot: updateFolders,
          );
        } else if (favorite.kind == 'shareFile') {
          targetSucceeded = await _checkFileTarget(
            favorite,
            checkedAt: checkedAt,
          );
        }
        completed += 1;
        if (targetSucceeded) {
          succeeded += 1;
        } else {
          failed += 1;
        }
        state = state.copyWith(completed: completed, currentName: '');
      }
    } catch (error, stack) {
      ref.read(appLogProvider).error('favorite_monitor_run', error, stack);
      final remaining = targets.length - completed;
      failed += remaining < 0 ? 0 : remaining;
      completed = targets.length;
    }

    final result = FavoriteMonitorRunResult(
      total: targets.length,
      succeeded: succeeded,
      failed: failed,
    );
    final completedAt = _now;
    state = state.copyWith(
      checking: false,
      completed: completed,
      total: targets.length,
      currentName: '',
      lastCompletedAt: completedAt,
      lastResult: result,
    );
    await _persistLastResult(completedAt, result);
    await _safeReporter(
      () => _reporter.finish(
        total: targets.length,
        succeeded: succeeded,
        failed: failed,
      ),
    );
    await refreshSummary();
    return result;
  }

  Future<bool> _checkFolderTarget(
    FavoriteItem favorite, {
    required int checkedAt,
    required bool updateSnapshot,
  }) async {
    try {
      final folder = await _gateway.resolveFolder(
        url: favorite.ref,
        pwd: favorite.pwd,
      );
      final snapshot = favoriteFolderSnapshotFromDetail(
        folder,
        checkedAt: checkedAt,
      );
      if (updateSnapshot) {
        final changed = favoriteFolderHasChanged(
          favorite.folderSnapshot,
          snapshot,
        );
        final hasUpdate = favorite.folderHasUpdate || changed;
        final updateAt = changed ? checkedAt : favorite.folderUpdateAt;
        await _db.saveFavoriteFolderSnapshot(
          id: favorite.id,
          snapshot: snapshot,
          hasUpdate: hasUpdate,
          updateAt: updateAt,
        );
        if (changed && _settings.notifyUpdates) {
          await _safeReporter(
            () => _reporter.folderUpdated(
              favorite: favorite,
              head: favoriteFolderHeadOf(snapshot),
            ),
          );
        }
      } else if (favorite.folderSnapshot == null) {
        await _db.saveFavoriteFolderSnapshot(
          id: favorite.id,
          snapshot: snapshot,
          hasUpdate: false,
        );
      } else {
        await _db.saveFavoriteShareStatus(
          id: favorite.id,
          status: FavoriteShareStatus.valid,
          checkedAt: checkedAt,
        );
      }
      return true;
    } catch (error, stack) {
      await _recordAccessError(favorite, error, stack, checkedAt: checkedAt);
      return false;
    }
  }

  Future<bool> _checkFileTarget(
    FavoriteItem favorite, {
    required int checkedAt,
  }) async {
    try {
      await _gateway.validateFile(url: favorite.ref, pwd: favorite.pwd);
      await _db.saveFavoriteShareStatus(
        id: favorite.id,
        status: FavoriteShareStatus.valid,
        checkedAt: checkedAt,
      );
      return true;
    } catch (error, stack) {
      await _recordAccessError(favorite, error, stack, checkedAt: checkedAt);
      return false;
    }
  }

  Future<void> _recordAccessError(
    FavoriteItem favorite,
    Object error,
    StackTrace stack, {
    required int checkedAt,
  }) async {
    final status = favoriteShareStatusForError(error);
    if (status != null) {
      await _db.saveFavoriteShareStatus(
        id: favorite.id,
        status: status,
        checkedAt: checkedAt,
      );
      return;
    }
    ref.read(appLogProvider).error('favorite_monitor', error, stack);
  }

  /// 新收藏在后台补一次首项基线；失败不阻断收藏本身，也不产生更新提醒。
  Future<void> initializeFolderBaseline(FavoriteItem favorite) async {
    if (favorite.kind != 'shareFolder' || favorite.folderSnapshot != null) {
      return;
    }
    final checkedAt = _now.millisecondsSinceEpoch;
    try {
      final folder = await _gateway.resolveFolder(
        url: favorite.ref,
        pwd: favorite.pwd,
      );
      await saveFolderBaselineFromDetail(favorite, folder);
    } catch (error, stack) {
      await _recordAccessError(favorite, error, stack, checkedAt: checkedAt);
    }
  }

  /// 已经解析过文件夹详情时直接保存基线，避免新收藏流程重复请求分享页。
  Future<void> saveFolderBaselineFromDetail(
    FavoriteItem favorite,
    FolderShareDetail folder,
  ) async {
    if (favorite.kind != 'shareFolder' || favorite.folderSnapshot != null) {
      return;
    }
    await _db.saveFavoriteFolderSnapshot(
      id: favorite.id,
      snapshot: favoriteFolderSnapshotFromDetail(
        folder,
        checkedAt: _now.millisecondsSinceEpoch,
      ),
      hasUpdate: false,
    );
  }

  /// 收藏文件夹成功打开后刷新基线、清更新 badge 并撤掉旧通知。
  Future<void> markFolderOpened(
    FavoriteItem favorite,
    FolderShareDetail folder,
  ) async {
    final checkedAt = _now.millisecondsSinceEpoch;
    await _db.clearFavoriteFolderUpdate(
      id: favorite.id,
      snapshot: favoriteFolderSnapshotFromDetail(folder, checkedAt: checkedAt),
    );
    await _safeReporter(() => _reporter.folderUpdateCleared(ref: favorite.ref));
    await refreshSummary();
  }

  Future<void> _safeReporter(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stack) {
      ref.read(appLogProvider).error('favorite_monitor_reporter', error, stack);
    }
  }

  Future<void> _persistLastAttempt(DateTime value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLastAttempt, value.millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<void> _persistLastResult(
    DateTime completedAt,
    FavoriteMonitorRunResult result,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLastCompleted, completedAt.millisecondsSinceEpoch);
      await prefs.setInt(_keyLastTotal, result.total);
      await prefs.setInt(_keyLastSucceeded, result.succeeded);
      await prefs.setInt(_keyLastFailed, result.failed);
    } catch (_) {}
  }
}

FavoriteFolderSnapshot favoriteFolderSnapshotFromDetail(
  FolderShareDetail folder, {
  required int checkedAt,
}) {
  if (folder.files.isEmpty) {
    return EmptyFavoriteFolderSnapshot(checkedAt: checkedAt);
  }
  final first = folder.files.first;
  return HeadFavoriteFolderSnapshot(
    checkedAt: checkedAt,
    head: FavoriteFolderHead(
      remoteId: first.remoteId.isEmpty ? first.url : first.remoteId,
      name: first.name,
      time: first.time,
      size: first.size,
    ),
  );
}

FavoriteFolderHead? favoriteFolderHeadOf(FavoriteFolderSnapshot snapshot) =>
    switch (snapshot) {
      HeadFavoriteFolderSnapshot(:final head) => head,
      EmptyFavoriteFolderSnapshot() => null,
    };

FavoriteShareStatus? favoriteShareStatusForError(Object error) {
  if (error is NeedPasswordException || error is WrongPasswordException) {
    return FavoriteShareStatus.passwordChanged;
  }
  if (error is LanzouException &&
      (error.code == LanzouErrorCode.folderShareUnavailable ||
          error.code == LanzouErrorCode.fileShareUnavailable)) {
    return FavoriteShareStatus.unavailable;
  }
  return null;
}

bool favoriteMonitorCheckDue({
  required DateTime? lastAttemptAt,
  required DateTime now,
  required FavoriteCheckFrequency frequency,
}) {
  if (lastAttemptAt == null) return true;
  final next = switch (frequency) {
    FavoriteCheckFrequency.daily => lastAttemptAt.add(const Duration(days: 1)),
    FavoriteCheckFrequency.weekly => lastAttemptAt.add(const Duration(days: 7)),
    FavoriteCheckFrequency.monthly => DateTime(
      lastAttemptAt.year,
      lastAttemptAt.month + 1,
      lastAttemptAt.day,
      lastAttemptAt.hour,
      lastAttemptAt.minute,
      lastAttemptAt.second,
      lastAttemptAt.millisecond,
      lastAttemptAt.microsecond,
    ),
  };
  return !now.isBefore(next);
}
