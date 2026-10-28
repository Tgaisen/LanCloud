import 'package:path/path.dart' as p;

/// 下载目录分类：设置页副标题按它加前缀（私有 / 公共 / 非公共）。
enum DownloadDirKind {
  /// 应用专属目录（Android 9 及以下未设置目录时的默认位置）。
  privateDir,

  /// 系统标准公共目录（Download、Documents 等），Android 11+ 可直接写入。
  publicDir,

  /// 其它目录：经系统授权写入，较大文件需要先中转。
  customDir,
}

/// 与原生侧放行列表一致的标准公共目录（统一按小写比较）。
const Set<String> _standardPublicDirs = {
  'music',
  'podcasts',
  'ringtones',
  'alarms',
  'notifications',
  'pictures',
  'movies',
  'download',
  'dcim',
  'documents',
  'audiobooks',
  'recordings',
};

/// 从默认下载目录推出外部存储根（如 `/storage/emulated/0`）。
/// 推不出来（桌面端、取到的是应用内部目录）返回 null。
String? publicStorageRootFrom(String defaultPath) {
  if (!p.posix.isAbsolute(defaultPath)) return null;
  // 这些是 Android（Linux）路径，固定用 posix 语义，避免受测试主机影响。
  final parts = p.posix.split(defaultPath);
  final androidIndex = parts.indexOf('Android');
  if (androidIndex > 1) {
    return p.posix.joinAll(parts.sublist(0, androidIndex));
  }
  // 新版默认目录直接位于 /storage/<卷>/[用户]/Download，路径中没有
  // Android 段，不能再只按旧版应用专属路径反推。
  if (parts.length < 3 || parts[1] != 'storage') return null;
  if (parts[2] == 'emulated') {
    if (parts.length < 4 || int.tryParse(parts[3]) == null) return null;
    return p.posix.joinAll(parts.sublist(0, 4));
  }
  return p.posix.joinAll(parts.sublist(0, 3));
}

/// 判断 [path] 属于哪一类下载目录。
///
/// [privateRoots] 是应用专属目录（旧系统默认下载目录所在的根）；
/// [publicRoot] 是外部存储根，其下的标准公共目录可直接写入；
/// 其余归入 [DownloadDirKind.customDir]。
DownloadDirKind classifyDownloadDir(
  String path, {
  required Iterable<String> privateRoots,
  String? publicRoot,
}) {
  for (final root in privateRoots) {
    if (root.isEmpty) continue;
    if (p.posix.equals(path, root) || p.posix.isWithin(root, path)) {
      return DownloadDirKind.privateDir;
    }
  }
  final root = publicRoot;
  if (root != null && root.isNotEmpty && p.posix.isWithin(root, path)) {
    final first = p.posix.split(p.posix.relative(path, from: root)).first;
    if (_standardPublicDirs.contains(first.toLowerCase())) {
      return DownloadDirKind.publicDir;
    }
  }
  return DownloadDirKind.customDir;
}
