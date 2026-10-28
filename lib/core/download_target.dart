/// 下载最终写入的位置。
enum DownloadTargetMode {
  /// Android 未设置目录且系统不支持 MediaStore Downloads 时的应用专属目录。
  appDirectory,

  /// 普通文件路径目录（桌面端或用户明确设置的固定路径）。
  fixedDirectory,

  /// 用户授权的 SAF 目录。
  safDirectory,

  /// Android 10+ 的公共 `Download/LanCloud`，经 MediaStore 无授权写入。
  sharedDownloads,
}

/// 根据平台、显式目录设置与系统能力选择下载落盘方式。
///
/// 显式设置始终优先；只有 Android 未设置任何目录且系统支持 MediaStore
/// Downloads 时，才使用公共 `Download/LanCloud`。
DownloadTargetMode resolveDownloadTargetMode({
  required bool isAndroid,
  required bool supportsSharedDownloads,
  String? directory,
  String? treeUri,
}) {
  if (!isAndroid) return DownloadTargetMode.fixedDirectory;
  if (treeUri != null && treeUri.isNotEmpty) {
    return DownloadTargetMode.safDirectory;
  }
  if (directory != null && directory.isNotEmpty) {
    return DownloadTargetMode.fixedDirectory;
  }
  if (supportsSharedDownloads) {
    return DownloadTargetMode.sharedDownloads;
  }
  return DownloadTargetMode.appDirectory;
}
