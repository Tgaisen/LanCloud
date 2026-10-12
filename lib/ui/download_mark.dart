import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/platform_support.dart';
import '../core/system_open.dart';
import '../core/system_share.dart';
import '../core/transfer/transfer_manager.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'm3e.dart';

/// 网盘文件的「已下载」标记 key：与下载任务的 `refId`（"账号uid:文件id"）一致。
String driveDownloadKey(String uid, String fileId) => '$uid:$fileId';

/// 「已添加下载」小标记：有匹配任务（已取消的不算）时显示一个 `download_done`
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
    // 可空读取：单独拿这个小组件做测试 / 预览（没有 Provider 的树）时
    // 直接不显示标记，而不是抛 ProviderNotFound。
    final manager = context.read<TransferManager?>();
    if (manager == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: manager.marksRevision,
      builder: (BuildContext context, _) {
        if (manager.downloadMarkOf(markKey) == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: EdgeInsetsDirectional.only(start: gap),
          child: Icon(
            Icons.download_done,
            size: size,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}

enum _DownloadMenuAction { open, share, stop, redownload }

/// 「已下载」入口的二级菜单（两步菜单：点入口后弹这一层）：
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
  final manager = context.read<TransferManager>();
  final l10n = context.l10n;
  final bool running =
      task.status == TransferStatus.queued ||
      task.status == TransferStatus.running;
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
      M3eMenuItem(
        value: _DownloadMenuAction.stop,
        label: running ? l10n.cancelDownload : l10n.deleteRecord,
        icon: running ? Icons.close : Icons.playlist_remove,
      ),
      M3eMenuItem(
        value: _DownloadMenuAction.redownload,
        label: l10n.redownload,
        icon: Icons.refresh,
        enabled: !running,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _DownloadMenuAction.open:
      await openFileWithSystem(savedPath!);
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
    case _DownloadMenuAction.stop:
      if (running) {
        manager.cancel(task.id);
      } else {
        manager.removeTask(task.id);
      }
    case _DownloadMenuAction.redownload:
      manager.removeTask(task.id);
      await onRedownload();
  }
}

/// 分享下载文件时用的 MIME（与传输页一致）：APK 单独识别。
String _shareMimeFor(String name) => name.toLowerCase().endsWith('.apk')
    ? 'application/vnd.android.package-archive'
    : 'application/octet-stream';
