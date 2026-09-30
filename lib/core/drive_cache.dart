import 'api/models.dart';

class CachedFolder {
  CachedFolder({
    required this.folders,
    required this.files,
    required this.path,
    required this.page,
    required this.hasMore,
  });

  final List<LzFolder> folders;
  final List<LzFile> files;
  final List<PathNode> path;
  final int page;
  final bool hasMore;
}

/// 网盘目录的内存缓存：返回上一级时直接命中，避免重复请求。
class DriveCache {
  final Map<String, CachedFolder> _folders = {};

  CachedFolder? get(String folderId) => _folders[folderId];

  void put(String folderId, CachedFolder value) => _folders[folderId] = value;

  void clear() => _folders.clear();
}
