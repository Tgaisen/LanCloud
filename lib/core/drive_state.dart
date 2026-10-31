import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'drive_cache.dart';

/// 网盘页当前所在目录：id + 相对根目录的路径。
class DriveLocation {
  const DriveLocation({this.id = '-1', this.path = ''});

  final String id;

  /// 例如 `abc/def`；根目录时为空串。
  final String path;

  @override
  bool operator ==(Object other) =>
      other is DriveLocation && other.id == id && other.path == path;

  @override
  int get hashCode => Object.hash(id, path);
}

/// 网盘页与首页之间的目录导航状态，以及拖拽上传的页面可见性探针。
class DriveState {
  /// 按账号隔离的网盘目录内存/根快照缓存。
  final DriveCache cache = DriveCache();

  /// 首页“目录打开方式 = 网盘页”时请求打开的目录 id（消费后置空）。
  final ValueNotifier<String?> folderRequest = ValueNotifier(null);

  /// 网盘页当前所在目录（拖拽上传确认条使用）。
  final ValueNotifier<DriveLocation> location = ValueNotifier(
    const DriveLocation(),
  );

  final List<bool Function()> _driveProbes = [];
  final List<bool Function()> _favoritesProbes = [];

  void addDriveProbe(bool Function() probe) => _driveProbes.add(probe);

  void removeDriveProbe(bool Function() probe) => _driveProbes.remove(probe);

  bool get driveVisible => _driveProbes.any(_safeProbe);

  void addFavoritesProbe(bool Function() probe) => _favoritesProbes.add(probe);

  void removeFavoritesProbe(bool Function() probe) =>
      _favoritesProbes.remove(probe);

  bool get favoritesVisible => _favoritesProbes.any(_safeProbe);

  static bool _safeProbe(bool Function() probe) {
    try {
      return probe();
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    folderRequest.dispose();
    location.dispose();
  }
}

/// 应用级网盘导航状态。
final driveStateProvider = Provider<DriveState>((ref) {
  throw StateError('driveStateProvider 必须由应用入口覆盖');
});

/// 从唯一 [DriveState] 派生的目录缓存入口。
final driveCacheProvider = Provider<DriveCache>(
  (ref) => ref.watch(driveStateProvider).cache,
);
