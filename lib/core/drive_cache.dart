import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toJson() => {
        'folders': folders.map((f) => f.toJson()).toList(),
        'files': files.map((f) => f.toJson()).toList(),
        'path': path.map((p) => p.toJson()).toList(),
        'page': page,
        'hasMore': hasMore,
      };

  factory CachedFolder.fromJson(Map<String, dynamic> j) => CachedFolder(
        folders: (j['folders'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => LzFolder.fromJson(e.cast<String, dynamic>()))
            .toList(),
        files: (j['files'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => LzFile.fromJson(e.cast<String, dynamic>()))
            .toList(),
        path: (j['path'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => PathNode.fromJson(e.cast<String, dynamic>()))
            .toList(),
        page: (j['page'] as num?)?.toInt() ?? 1,
        hasMore: j['hasMore'] as bool? ?? false,
      );
}

/// 网盘目录的内存缓存：返回上一级时直接命中，避免重复请求。
/// 根目录（-1）会持久化，冷启动时可直接展示。
/// 缓存按账号隔离：换账号时会整体清空，根快照也按账号分开存。
class DriveCache {
  static const _prefsPrefix = 'drive_cache_root';
  /// 旧版本只有一个全局快照，无法判断属于哪个账号，绑定账号时直接丢弃。
  static const _legacyPrefsKey = 'drive_cache_root';

  final Map<String, CachedFolder> _folders = {};
  String? _uid;

  String get _prefsKey => '${_prefsPrefix}_${_uid ?? 'anon'}';

  /// 绑定当前账号：账号变化时清空内存缓存，并读取该账号自己的根快照。
  Future<void> bindAccount(String? uid) async {
    if (_uid == uid) return;
    _uid = uid;
    _folders.clear();
    await loadFromDisk();
  }

  CachedFolder? get(String folderId) => _folders[folderId];

  void put(String folderId, CachedFolder value) {
    _folders[folderId] = value;
    // 键名在这里就取好：写入是异步的，期间可能已经换了账号
    if (folderId == '-1') _persistRoot(value, _prefsKey);
  }

  /// 冷启动 / 换账号时读取该账号上次持久化的根目录快照。
  Future<void> loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 旧版本的全局快照作废，避免新账号读到别的账号的目录
      if (prefs.containsKey(_legacyPrefsKey)) {
        await prefs.remove(_legacyPrefsKey);
      }
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty || _folders.containsKey('-1')) return;
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) {
        final cached = CachedFolder.fromJson(map);
        // 根目录快照不应带路径；坏快照直接丢弃，冷启动走网络重拉
        if (cached.path.isEmpty) _folders['-1'] = cached;
      }
    } catch (_) {
      // 缓存损坏时忽略，走正常网络加载
    }
  }

  Future<void> _persistRoot(CachedFolder value, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(value.toJson()));
    } catch (_) {}
  }

  void clear() => _folders.clear();
}
