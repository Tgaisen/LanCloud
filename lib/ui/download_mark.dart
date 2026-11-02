import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform_support.dart';
import '../core/saved_file.dart';
import '../core/system_open.dart';
import '../core/system_share.dart';
import '../core/transfer/transfer_manager.dart';
import '../core/transfer/transfer_manager_provider.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'm3e.dart';

/// 网盘文件的「已加入下载」标记 key：与下载任务的 `refId`（"账号uid:文件id"）一致。
String driveDownloadKey(String uid, String fileId) => '$uid:$fileId';

/// 网盘批量下载前是否需要跳过：同一文件当前已在传输列表中。
///
/// 失败任务仍算“已加入下载”，应去传输页重试；取消会直接移除任务记录。
bool shouldSkipDriveBatchDownload({
  required String ref,
  required TransferManager transfers,
}) => transfers.downloadMarkOf(ref) != null;

/// 「已加入下载」小标记：有匹配任务（已取消的不算）时显示一个 `download_done`
/// 小图标，位置风格和网盘文件的密码锁图标一致。
///
/// 只监听 [TransferManager.marksRevision]（低频）：下载进度更新不会让长列表
/// 重建；进度可视化在属性弹窗里做（见 [showDownloadTaskMenu] 的入口）。
class DownloadMarkIcon extends StatelessWidget {
  const DownloadMarkIcon({
    super.key,
    required this.markKey,
    this.size = 16,
    this.gap = 4,
  });

  /// 匹配键：网盘文件用 [driveDownloadKey]，分享文件用分享链接。
  final String markKey;
  final double size;

  /// 图标左侧留白；没有标记时整块（含留白）不占位。
  final double gap;

  @override
  Widget build(BuildContext context) {
    // 单独拿这个小组件做测试 / 预览时允许没有 ProviderScope：
    // 直接不显示标记，而不是让整个属性卡构建失败。
    final ProviderContainer container;
    try {
      container = ProviderScope.containerOf(context);
    } on StateError {
      return const SizedBox.shrink();
    }
    final manager = container.read(transferManagerProvider);
    return ListenableBuilder(
      listenable: manager.marksRevision,
      builder: (BuildContext context, _) {
        final task = manager.downloadMarkOf(markKey);
        if (task == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: EdgeInsetsDirectional.only(start: gap),
          child: Icon(
            task.status == TransferStatus.saving
                ? Icons.save
                : Icons.download_done,
            size: size,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}

enum _DownloadMenuAction {
  open,
  share,
  pause,
  resume,
  stop,
  deleteFile,
  redownload,
}

/// 「已加入下载」入口的二级菜单（两步菜单：点入口后弹这一层）：
/// 打开 / 分享（桌面端为在资源管理器定位）/ 取消下载或删除任务记录 / 重新下载。
///
/// [task] 是当前匹配到的下载任务（[TransferManager.downloadMarkOf]）；
/// [onRedownload] 由各页面提供——本函数先把旧任务删掉，再回调重新发起下载
/// （网盘是重新取分享信息再下、分享弹窗是再走一遍 downloadShareFile）。
Future<void> showDownloadTaskMenu(
  BuildContext context, {
  required Rect anchor,
  required TransferTask task,
  required Future<void> Function() onRedownload,
}) async {
  if (task.status == TransferStatus.saving) return;
  final manager = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(transferManagerProvider);
  final l10n = context.l10n;
  final bool running =
      task.status == TransferStatus.queued ||
      task.status == TransferStatus.running;
  final bool resuming = task.status == TransferStatus.resuming;
  final bool transferActive = running || resuming;
  final bool paused = task.status == TransferStatus.paused;
  final String? savedPath = task.savedPath;
  final bool hasFile =
      task.status == TransferStatus.done &&
      savedPath != null &&
      savedPath.isNotEmpty;
  final bool desktop = PlatformSupport.isDesktop;
  // 打开菜单时的状态快照：只有这条任务自己的状态变了 / 被删了，才自动收起
  // 菜单（别的任务完成不该把用户正看着的菜单关掉）
  final TransferStatus openedStatus = task.status;

  final _DownloadMenuAction? action = await showM3eMenu<_DownloadMenuAction>(
    context: context,
    anchor: anchor,
    closeOn: manager.marksRevision,
    closeWhen: () =>
        task.removed ||
        task.status != openedStatus ||
        !manager.tasks.contains(task),
    items: [
      M3eMenuItem(
        value: _DownloadMenuAction.open,
        label: l10n.open,
        icon: Icons.open_in_new,
        enabled: hasFile,
      ),
      M3eMenuItem(
        value: _DownloadMenuAction.share,
        label: desktop ? l10n.openContainingFolder : l10n.share,
        icon: desktop ? Icons.folder_open : Icons.share_outlined,
        enabled: hasFile,
      ),
      // 进行中才是「取消下载」，其余状态是删掉这条任务记录（M3 规范：不用的
      // 操作置灰或换说法，而不是留一个点了没反应的入口）
      if (running)
        M3eMenuItem(
          value: _DownloadMenuAction.pause,
          label: l10n.pauseDownload,
          icon: Icons.pause,
        ),
      if (paused)
        M3eMenuItem(
          value: _DownloadMenuAction.resume,
          label: l10n.resumeDownload,
          icon: Icons.play_arrow,
        ),
      M3eMenuItem(
        value: _DownloadMenuAction.stop,
        label: transferActive || paused
            ? l10n.cancelDownload
            : l10n.deleteDownloadRecord,
        icon: transferActive || paused ? Icons.close : Icons.playlist_remove,
      ),
      // 连文件一起删：删完标记消失，属性弹窗恢复「下载」原状
      M3eMenuItem(
        value: _DownloadMenuAction.deleteFile,
        label: l10n.deleteRecordAndFile,
        icon: Icons.delete_outline,
        enabled: hasFile,
      ),
      M3eMenuItem(
        value: _DownloadMenuAction.redownload,
        label: l10n.redownload,
        icon: Icons.refresh,
        enabled: !transferActive,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _DownloadMenuAction.open:
      final opened = await openFileWithSystem(savedPath!, name: task.name);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.openFileFailed)));
      }
    case _DownloadMenuAction.share:
      if (desktop) {
        await revealInExplorer(savedPath!);
      } else {
        await SystemShare.shareFile(
          savedPath!,
          subject: task.name,
          mime: _shareMimeFor(task.name),
        );
      }
    case _DownloadMenuAction.pause:
      manager.pause(task.id);
    case _DownloadMenuAction.resume:
      final message = await manager.resume(task.id);
      if (message != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    case _DownloadMenuAction.stop:
      if (transferActive || paused) {
        manager.cancel(task.id);
      } else {
        manager.removeTask(task.id);
      }
    case _DownloadMenuAction.deleteFile:
      // 先删记录（标记立即消失、弹窗恢复原状），再删本地文件
      manager.removeTask(task.id);
      await deleteSavedFile(savedPath!);
    case _DownloadMenuAction.redownload:
      manager.removeTask(task.id);
      await onRedownload();
  }
}

/// 分享下载文件时用的 MIME（与传输页一致）：APK 单独识别。
String _shareMimeFor(String name) => name.toLowerCase().endsWith('.apk')
    ? 'application/vnd.android.package-archive'
    : 'application/octet-stream';
