import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/file_open_result.dart';
import '../core/navigation_appearance_settings_state.dart';
import '../core/navigation_state.dart';
import '../core/platform_support.dart';
import '../core/saved_file.dart';
import '../core/system_open.dart';
import '../core/system_share.dart';
import '../core/transfer/transfer_manager.dart';
import '../core/transfer/transfer_manager_provider.dart';
import '../core/transfer/transfer_issue.dart';
import '../core/transfer/upload_rename.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'file_open_feedback.dart';
import 'm3e.dart';
import 'reduce_motion.dart';
import 'scroll_tint.dart';
import 'transfer_rename_dialogs.dart';

/// 传输条目 ⋯ 菜单里的动作。
///
/// 「打开 / 分享」只对已下载完成的条目有意义，「重试」只对失败条目有意义，
/// 「删除记录与文件」只对下载且文件已落盘、任务已停下（不在跑）的条目给出。
enum _TransferMenuAction {
  open,
  share,
  pause,
  resume,
  cancel,
  rename,
  retry,
  uploadAnyway,
  removeRecord,
  removeRecordAndFile,
}

enum TransferDeleteReason {
  selected,
  cancelActive,
  clearCompleted,
  clearFailed,
  clearSkipped,
  clearPending,
}

class TransferDeleteResult {
  const TransferDeleteResult({required this.deleteFiles});

  final bool deleteFiles;
}

/// 传输记录删除确认。仅在下载场景显示“同时删除文件”，并把无选择掩码的
/// 批量操作与多选删除使用各自面向用户的文案。
Future<TransferDeleteResult?> showTransferDeleteDialog(
  BuildContext context, {
  required TransferKind kind,
  required int count,
  required TransferDeleteReason reason,
  required bool showDeleteFiles,
}) {
  final l10n = context.l10n;
  final title = switch (reason) {
    TransferDeleteReason.selected => l10n.transferDeleteConfirmTitle,
    TransferDeleteReason.cancelActive => l10n.cancelInProgressTransfers,
    TransferDeleteReason.clearCompleted => l10n.clearFinishedTransfers,
    TransferDeleteReason.clearFailed => l10n.clearFailedTransfers,
    TransferDeleteReason.clearSkipped => l10n.clearSkippedUploads,
    TransferDeleteReason.clearPending => l10n.clearPendingUploads,
  };
  final message = switch (reason) {
    TransferDeleteReason.selected => l10n.transferDeleteConfirmMessage(count),
    TransferDeleteReason.cancelActive =>
      kind == TransferKind.upload
          ? l10n.cancelAllUploadsConfirmMessage(count)
          : l10n.cancelAllDownloadsConfirmMessage(count),
    TransferDeleteReason.clearCompleted =>
      kind == TransferKind.upload
          ? l10n.clearFinishedUploadsConfirmMessage(count)
          : l10n.clearFinishedDownloadsConfirmMessage(count),
    TransferDeleteReason.clearFailed => l10n.clearFailedConfirmMessage(count),
    TransferDeleteReason.clearSkipped => l10n.clearSkippedUploadsConfirmMessage(
      count,
    ),
    TransferDeleteReason.clearPending => l10n.clearPendingUploadsConfirmMessage(
      count,
    ),
  };
  final confirmLabel = switch (reason) {
    TransferDeleteReason.selected => l10n.delete,
    TransferDeleteReason.cancelActive => l10n.cancelAll,
    TransferDeleteReason.clearCompleted => l10n.clearAll,
    TransferDeleteReason.clearFailed => l10n.clearAll,
    TransferDeleteReason.clearSkipped => l10n.clearAll,
    TransferDeleteReason.clearPending => l10n.clearAll,
  };
  var deleteFiles = false;
  return showDialog<TransferDeleteResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(title),
        // M3 对话框内容边距 24dp；列表组外边距 0，组沿落在 24dp 上
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            if (showDeleteFiles) ...[
              const SizedBox(height: 16),
              DialogListGroup(
                children: [
                  M3ePickTile(
                    label: l10n.deleteFilesToo,
                    selected: deleteFiles,
                    onTap: () =>
                        setDialogState(() => deleteFiles = !deleteFiles),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('transfer-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(
              TransferDeleteResult(deleteFiles: showDeleteFiles && deleteFiles),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
}

typedef TransferFileOpener = Future<FileOpenResult> Function(
  String path, {
  String? name,
});

bool _isInProgressTask(TransferTask task) =>
    task.status == TransferStatus.queued ||
    task.status == TransferStatus.resolving ||
    task.status == TransferStatus.running ||
    task.status == TransferStatus.resuming ||
    task.status == TransferStatus.paused ||
    task.status == TransferStatus.saving;

bool _isCompletedTask(TransferTask task) => task.status == TransferStatus.done;

bool _isFailedTask(TransferTask task) => task.status == TransferStatus.failed;

List<TransferTask> _newestFirst(Iterable<TransferTask> tasks) =>
    tasks.toList().reversed.toList();

bool _isSkippedUpload(TransferTask task) =>
    task.kind == TransferKind.upload && task.status == TransferStatus.skipped;

bool _isPendingUpload(TransferTask task) =>
    task.kind == TransferKind.upload && task.status == TransferStatus.pending;

bool _isPausableDownload(TransferTask task) =>
    task.kind == TransferKind.download &&
    (task.status == TransferStatus.queued ||
        task.status == TransferStatus.running) &&
    !task.exporting;

class TransfersPage extends ConsumerStatefulWidget {
  const TransfersPage({super.key, this.openFile});

  /// 打开已下载文件；默认交给系统「打开」，测试注入以免真的调起系统应用。
  final TransferFileOpener? openFile;

  @override
  ConsumerState<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends ConsumerState<TransfersPage>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  static const _anim = Duration(milliseconds: 200);

  /// 传输页默认展示下载列表。
  int _tab = 1;

  /// 上传 / 下载切换时列表淡入
  late final AnimationController _tabAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  late final Animation<double> _tabFade = CurvedAnimation(
    parent: _tabAnim,
    curve: Curves.easeOutCubic,
  );

  /// 列表入场动画：只在首次加载 / 切换上传下载时整组播一次，
  /// 滑动时懒构建出来的条目不再重播（与收藏页一致，改用共享进度驱动）；
  /// 切走再切回本视图也不重播（页面保活，动画状态与其它页一样保留）。
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: ListEnterAnimation.duration,
  );
  final ScrollController _scroll = ScrollController();
  bool _selecting = false;
  bool _bulkResumeRunning = false;
  final Set<String> _selected = {};

  /// 正在播放删除动画的记录（动画播完再真正移除）
  final Set<String> _removing = {};

  /// 外壳导航状态：dispose 里不能再读 context，退出多选要用它。
  late final NavigationState _navigation;

  /// 整组入场动画：系统要求少动效时直接显示（不做错峰淡入 / 位移）。
  void _replayEnter() {
    if (reduceMotionOf(context)) {
      _enter.value = 1;
      return;
    }
    _enter.forward(from: 0);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _navigation = ref.read(navigationStateProvider);
    // 首次加载：整组播一次入场动画（之后只在切换上传 / 下载时重播）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _replayEnter();
    });
  }

  @override
  void dispose() {
    if (_selecting) {
      _navigation.setSelectionMode(false);
      _navigation.onRequestExitSelection = null;
    }
    _tabAnim.dispose();
    _enter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  TransferKind get _kind =>
      _tab == 0 ? TransferKind.upload : TransferKind.download;

  List<TransferTask> _tasksOf(TransferManager manager) => manager.byKind(_kind);

  void _enterSelection({String? taskId}) {
    final wasSelecting = _selecting;
    if (!_selecting) {
      // 其它页面可能正处于多选：先退出，避免两处状态打架
      _navigation.onRequestExitSelection?.call();
    }
    setState(() {
      _selecting = true;
      if (taskId != null) _selected.add(taskId);
    });
    _navigation.onRequestExitSelection = _exitSelection;
    _navigation.setSelectionMode(true);
    if (!wasSelecting) announceEnteredMultiSelect(context);
  }

  void _exitSelection() {
    if (!_selecting) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    _navigation.onRequestExitSelection = null;
    _navigation.setSelectionMode(false);
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
    // 选中数归零 → 自动退出多选
    if (_selected.isEmpty) _exitSelection();
  }

  void _selectAll() {
    final manager = ref.read(transferManagerProvider);
    setState(() {
      _selected
        ..clear()
        ..addAll(_tasksOf(manager).map((t) => t.id));
    });
    if (_selected.isEmpty) _exitSelection();
  }

  /// 点顶栏空白处回到列表顶部（与网盘页一致）。
  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _invertSelection() {
    final manager = ref.read(transferManagerProvider);
    setState(() {
      for (final task in _tasksOf(manager)) {
        if (!_selected.remove(task.id)) _selected.add(task.id);
      }
    });
    if (_selected.isEmpty) _exitSelection();
  }

  Future<void> _cancelActive() async {
    final manager = ref.read(transferManagerProvider);
    final tasks = _tasksOf(manager)
        .where(_isInProgressTask)
        .toList(growable: false);
    if (tasks.isEmpty) return;
    final result = await showTransferDeleteDialog(
      context,
      kind: _kind,
      count: tasks.length,
      reason: TransferDeleteReason.cancelActive,
      showDeleteFiles: false,
    );
    if (result == null || !mounted) return;
    manager.removeTasks([for (final task in tasks) task.id]);
    // “全部取消”按用户预期连带清理下载文件。
    if (_kind == TransferKind.download) await _deleteTaskFiles(tasks);
  }

  Future<void> _clearCompletedSection() async {
    final manager = ref.read(transferManagerProvider);
    final tasks = _tasksOf(manager)
        .where(_isCompletedTask)
        .toList(growable: false);
    if (tasks.isEmpty) return;
    final result = await showTransferDeleteDialog(
      context,
      kind: _kind,
      count: tasks.length,
      reason: TransferDeleteReason.clearCompleted,
      showDeleteFiles: _kind == TransferKind.download,
    );
    if (result == null || !mounted) return;
    final removed = manager.clearCompleted(_kind);
    if (result.deleteFiles) await _deleteTaskFiles(removed);
  }

  Future<void> _clearFailedSection() async {
    final manager = ref.read(transferManagerProvider);
    final tasks = _tasksOf(manager)
        .where(_isFailedTask)
        .toList(growable: false);
    if (tasks.isEmpty) return;
    final result = await showTransferDeleteDialog(
      context,
      kind: _kind,
      count: tasks.length,
      reason: TransferDeleteReason.clearFailed,
      showDeleteFiles: false,
    );
    if (result == null || !mounted) return;
    manager.clearFailed(_kind);
  }

  Future<void> _clearSkippedSection() async {
    final manager = ref.read(transferManagerProvider);
    final tasks = _tasksOf(manager)
        .where(_isSkippedUpload)
        .toList(growable: false);
    if (tasks.isEmpty) return;
    final result = await showTransferDeleteDialog(
      context,
      kind: TransferKind.upload,
      count: tasks.length,
      reason: TransferDeleteReason.clearSkipped,
      showDeleteFiles: false,
    );
    if (result == null || !mounted) return;
    manager.clearSkippedUploads();
  }

  Future<void> _clearPendingSection() async {
    final manager = ref.read(transferManagerProvider);
    final tasks = _tasksOf(manager)
        .where(_isPendingUpload)
        .toList(growable: false);
    if (tasks.isEmpty) return;
    final result = await showTransferDeleteDialog(
      context,
      kind: TransferKind.upload,
      count: tasks.length,
      reason: TransferDeleteReason.clearPending,
      showDeleteFiles: false,
    );
    if (result == null || !mounted) return;
    manager.clearPendingUploads();
  }

  Future<void> _renameTask(TransferTask task) async {
    final name = await showSingleUploadRenameDialog(context, task: task);
    if (name == null || !mounted) return;
    final applied = ref.read(transferManagerProvider).renameUploads([
      UploadRenameChange(id: task.id, originalName: task.name, newName: name),
    ]);
    if (applied == 0 || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.renamedUploads(applied))),
    );
  }

  Future<void> _renameSelected() async {
    final tasks = ref
        .read(transferManagerProvider)
        .tasks
        .where(
          (task) =>
              _selected.contains(task.id) &&
              (task.status == TransferStatus.pending ||
                  task.status == TransferStatus.skipped),
        )
        .toList(growable: false);
    if (tasks.isEmpty) return;
    final changes = await showBatchUploadRenameDialog(context, tasks: tasks);
    if (changes == null || !mounted) return;
    final applied = ref.read(transferManagerProvider).renameUploads(changes);
    _exitSelection();
    if (applied == 0 || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.renamedUploads(applied))),
    );
  }

  void _uploadSelected() {
    final ids = ref
        .read(transferManagerProvider)
        .tasks
        .where(
          (task) =>
              _selected.contains(task.id) &&
              task.status == TransferStatus.pending,
        )
        .map((task) => task.id)
        .toList(growable: false);
    if (ids.isEmpty) return;
    _exitSelection();
    ref.read(transferManagerProvider).startUploads(ids);
  }

  void _selectSection(Iterable<String> ids) {
    if (!_selecting) return;
    final values = ids.toSet();
    if (values.isEmpty) return;
    setState(() => _selected.addAll(values));
  }

  void _uploadPendingSection() {
    final ids = ref
        .read(transferManagerProvider)
        .byKind(TransferKind.upload)
        .where(_isPendingUpload)
        .map((task) => task.id)
        .toList(growable: false);
    if (ids.isEmpty) return;
    ref.read(transferManagerProvider).startUploads(ids);
  }

  Future<void> _shareSelected() async {
    final tasks = ref
        .read(transferManagerProvider)
        .tasks
        .where(
          (task) =>
              _selected.contains(task.id) &&
              task.kind == TransferKind.download &&
              task.status == TransferStatus.done &&
              (task.savedPath?.isNotEmpty ?? false),
        )
        .toList(growable: false);
    if (tasks.isEmpty) return;
    final paths = <String>{for (final task in tasks) ?task.savedPath};
    if (paths.isEmpty || !mounted) return;
    final subject = context.l10n.share;
    final mime = tasks.length == 1 ? _shareMimeFor(tasks.single.name) : null;
    _exitSelection();
    await SystemShare.shareFiles(paths, subject: subject, mime: mime);
  }

  void _pauseAll() {
    final manager = ref.read(transferManagerProvider);
    final ids = _tasksOf(manager)
        .where(_isPausableDownload)
        .map((task) => task.id)
        .toList(growable: false);
    manager.pauseDownloads(ids);
  }

  Future<void> _resumeAll() async {
    if (_bulkResumeRunning) return;
    final manager = ref.read(transferManagerProvider);
    final ids = _tasksOf(manager)
        .where((task) => task.status == TransferStatus.paused)
        .map((task) => task.id)
        .toList(growable: false);
    if (ids.isEmpty) return;
    setState(() => _bulkResumeRunning = true);
    final failed = await manager.resumeDownloads(ids);
    if (!mounted) return;
    setState(() => _bulkResumeRunning = false);
    if (failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.resumeAllPartialFailed(failed))),
      );
    }
  }

  /// 删除选中的传输记录（进行中的会先取消）。
  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final manager = ref.read(transferManagerProvider);
    final tasks = manager.tasks.where((t) => _selected.contains(t.id)).toList();
    if (tasks.isEmpty) return;
    final result = await showTransferDeleteDialog(
      context,
      kind: _kind,
      count: tasks.length,
      reason: TransferDeleteReason.selected,
      showDeleteFiles: _kind == TransferKind.download,
    );
    if (result == null || !mounted) return;
    final ids = [for (final task in tasks) task.id];
    _exitSelection();
    // 批量删除不逐条播动画：一次落库、一次通知，列表整体刷新一遍
    manager.removeTasks(ids);
    // 下载到本地的文件由本应用写入：普通路径直接删，SAF 文件走系统授权删
    if (result.deleteFiles) await _deleteTaskFiles(tasks);
  }

  /// 重试选中的失败项（其它状态忽略）。
  ///
  /// 重启后的下载任务要先重新解析直链，所以整批都放在进度弹窗里跑
  /// （和首页批量下载同一套样式），结束后提示结果。
  Future<void> _retrySelected() async {
    final manager = ref.read(transferManagerProvider);
    final l10n = context.l10n;
    final failed = _tasksOf(manager)
        .where(
          (t) => _selected.contains(t.id) && t.status == TransferStatus.failed,
        )
        .toList();
    if (failed.isEmpty) return;
    _exitSelection();
    var failedCount = 0;
    await runBatchWithProgress(
      context,
      title: l10n.batchRetry,
      total: failed.length,
      run: (report) async {
        for (var i = 0; i < failed.length; i++) {
          final task = failed[i];
          report(i + 1, task.name);
          final message = await manager.retry(task.id);
          if (message != null) failedCount += 1;
        }
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failedCount == 0
              ? l10n.retriedDownloads(failed.length)
              : l10n.retriedDownloadsPartial(
                  failed.length - failedCount,
                  failedCount,
                ),
        ),
      ),
    );
  }

  /// 打开已下载的文件（与点击条目同一个入口，测试注入的 openFile 也走这里）。
  Future<FileOpenResult> _openTaskFile(TransferTask task) async {
    try {
      return await (widget.openFile ?? openFileWithSystem)(
        task.savedPath!,
        name: task.name,
      );
    } catch (_) {
      return const FileOpenResult.failed(FileOpenFailure.systemError);
    }
  }

  /// 条目 ⋯ 菜单：按条目状态给出可用动作。
  ///
  /// [anchorContext] 是那颗 ⋯ 按钮（鼠标右键时是整行）的 context——
  /// 菜单贴它下方右对齐弹出。
  Future<void> _taskMenu(
    TransferTask task,
    BuildContext anchorContext, {
    Offset? pointerPosition,
  }) async {
    if (task.status == TransferStatus.saving) return;
    final anchor = m3eMenuAnchorOf(anchorContext);
    if (anchor == null) return;
    final l10n = context.l10n;
    final manager = ref.read(transferManagerProvider);
    final path = task.savedPath;
    final done = task.status == TransferStatus.done && path != null;
    final failed = task.status == TransferStatus.failed;
    final resolving = task.status == TransferStatus.resolving;
    final resuming = task.status == TransferStatus.resuming;
    final paused = task.status == TransferStatus.paused;
    final skipped = _isSkippedUpload(task);
    final pending = _isPendingUpload(task);
    final active =
        task.status == TransferStatus.queued ||
        task.status == TransferStatus.running;
    // 「删除记录与文件」只在任务停下之后给：正在写的半截文件删掉会打断下载器
    final stopped =
        task.status != TransferStatus.running &&
        task.status != TransferStatus.queued &&
        task.status != TransferStatus.resolving &&
        task.status != TransferStatus.resuming;
    final desktop = PlatformSupport.isDesktop;
    final _TransferMenuAction? action = await showM3eMenu<_TransferMenuAction>(
      context: context,
      anchor: anchor,
      pointerPosition: pointerPosition,
      // ⋯ 贴着右边缘：菜单右缘对齐，免得被屏幕右上角夹歪
      alignEnd: true,
      items: [
        if (task.kind == TransferKind.download && done) ...[
          M3eMenuItem(
            value: _TransferMenuAction.open,
            label: l10n.open,
            icon: Icons.open_in_new,
          ),
          M3eMenuItem(
            value: _TransferMenuAction.share,
            // 桌面端没有分享面板：SystemShare.shareFile 在桌面端就是资源管理器定位
            label: desktop ? l10n.openContainingFolder : l10n.share,
            icon: desktop ? Icons.folder_open : Icons.share_outlined,
          ),
        ],
        if (failed)
          M3eMenuItem(
            value: _TransferMenuAction.retry,
            label: l10n.retry,
            icon: Icons.refresh,
          ),
        if (pending || skipped)
          M3eMenuItem(
            value: _TransferMenuAction.rename,
            label: l10n.rename,
            icon: Icons.input_field,
          ),
        if (skipped)
          M3eMenuItem(
            value: _TransferMenuAction.uploadAnyway,
            label: l10n.uploadAnyway,
            icon: Icons.upload,
          ),
        if (task.kind == TransferKind.download && active)
          M3eMenuItem(
            value: _TransferMenuAction.pause,
            label: l10n.pauseDownload,
            icon: Icons.pause,
          ),
        if (task.kind == TransferKind.download && paused)
          M3eMenuItem(
            value: _TransferMenuAction.resume,
            label: l10n.resumeDownload,
            icon: Icons.play_arrow,
          ),
        if (task.kind == TransferKind.download &&
            (active || resolving || resuming || paused))
          M3eMenuItem(
            value: _TransferMenuAction.cancel,
            label: l10n.cancelDownload,
            icon: Icons.close,
          ),
        if (pending)
          M3eMenuItem(
            value: _TransferMenuAction.cancel,
            label: l10n.cancelUpload,
            icon: Icons.close,
          )
        else
          M3eMenuItem(
            value: _TransferMenuAction.removeRecord,
            label: l10n.deleteRecord,
            icon: Icons.playlist_remove,
          ),
        if (task.kind == TransferKind.download &&
            stopped &&
            path != null &&
            path.isNotEmpty)
          M3eMenuItem(
            value: _TransferMenuAction.removeRecordAndFile,
            label: l10n.deleteRecordAndFile,
            icon: Icons.delete_outline,
          ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _TransferMenuAction.open:
        final opened = await _openTaskFile(task);
        if (!opened.isSuccess && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                fileOpenFailureMessage(
                  l10n,
                  opened.failure ?? FileOpenFailure.systemError,
                ),
              ),
            ),
          );
        }
      case _TransferMenuAction.share:
        await SystemShare.shareFile(
          path!,
          subject: task.name,
          mime: _shareMimeFor(task.name),
        );
      case _TransferMenuAction.pause:
        manager.pause(task.id);
      case _TransferMenuAction.resume:
        final message = await manager.resume(task.id);
        if (!mounted) return;
        if (message != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      case _TransferMenuAction.cancel:
        manager.cancel(task.id);
      case _TransferMenuAction.rename:
        await _renameTask(task);
      case _TransferMenuAction.retry:
        final message = await manager.retry(task.id);
        if (!mounted) return;
        if (message != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      case _TransferMenuAction.uploadAnyway:
        final message = await manager.uploadSkipped(task.id);
        if (!mounted) return;
        if (message != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      case _TransferMenuAction.removeRecord:
        await _removeTask(task);
      case _TransferMenuAction.removeRecordAndFile:
        await _removeTask(task, deleteFile: true);
    }
  }

  /// 删除一条传输记录：先播删除动画（与收藏页一致），动画放完再真正移除；
  /// [deleteFile] 为真时连同本地文件一起删。
  Future<void> _removeTask(TransferTask task, {bool deleteFile = false}) async {
    final manager = ref.read(transferManagerProvider);
    setState(() => _removing.add(task.id));
    await Future<void>.delayed(const Duration(milliseconds: 220));
    // 动画期间页面可能已经被移出树（比如返回了上一页）：记录照删
    if (mounted) setState(() => _removing.remove(task.id));
    manager.removeTasks([task.id]);
    // 文件删除放最后、不挡动画，失败也静默（和批量删除同一个口径）
    if (deleteFile) unawaited(_deleteTaskFile(task));
  }

  /// 删掉下载下来的本地文件（文件由本应用写入，删除属于正常操作）。
  Future<void> _deleteTaskFile(TransferTask task) => _deleteTaskFiles([task]);

  Future<void> _deleteTaskFiles(Iterable<TransferTask> tasks) async {
    final paths = <String>{
      for (final task in tasks)
        if (task.savedPath case final path? when path.isNotEmpty) path,
    };
    for (final path in paths) {
      await deleteSavedFile(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final appearance = ref.watch(navigationAppearanceSettingsStateProvider);
    final manager = ref.watch(transferManagerProvider);
    return ListenableBuilder(
      listenable: appearance.revision,
      builder: (context, _) => ListenableBuilder(
        listenable: manager,
        builder: (context, _) =>
            _buildPage(context, appearance.hideTopBar, _navigation, manager),
      ),
    );
  }

  Widget _buildPage(
    BuildContext context,
    bool hideTopBar,
    NavigationState navigation,
    TransferManager manager,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final headerHeight =
        MediaQuery.paddingOf(context).top + kToolbarHeight + 58;
    final tasks = _tasksOf(manager);
    final selectedCount = _selected.length;
    final uploadTab = _kind == TransferKind.upload;
    final pendingCount = uploadTab
        ? tasks
              .where(
                (task) =>
                    _selected.contains(task.id) &&
                    task.status == TransferStatus.pending,
              )
              .length
        : 0;
    final renameCount = uploadTab
        ? tasks
              .where(
                (task) =>
                    _selected.contains(task.id) &&
                    (task.status == TransferStatus.pending ||
                        task.status == TransferStatus.skipped),
              )
              .length
        : 0;
    final shareCount = !uploadTab
        ? tasks
              .where(
                (task) =>
                    _selected.contains(task.id) &&
                    task.status == TransferStatus.done &&
                    (task.savedPath?.isNotEmpty ?? false),
              )
              .length
        : 0;
    final retryCount = tasks
        .where(
          (t) => _selected.contains(t.id) && t.status == TransferStatus.failed,
        )
        .length;
    return PopScope(
      // 独立页面（_openView 打开的二级路由）没有外壳的返回处理：
      // 多选状态下返回先退出多选；位于底栏（首个路由）时交给外壳统一处理。
      canPop: inRootShell(context) || !_selecting,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selecting) _exitSelection();
      },
      child: Scaffold(
        // 大屏外壳里的页面：背景交给外壳的圆角卡片
        backgroundColor: transparentPageBackground(context)
            ? Colors.transparent
            : null,
        body: Stack(
          children: [
            // 小屏：正文区整体让开左右挖孔 / 侧边导航栏；顶栏（浮层）保持原样
            BodySideInset(
              child: ScrollTint(
                hideDistance: headerHeight,
                readBarsHidden: () => navigation.topBarHide.value,
                onBarsHidden: hideTopBar
                    ? navigation.setTopBarHideFromScroll
                    : null,
                // 列表快速滑动条（可拖拽）
                child: FastScrollbar(
                  controller: _scroll,
                  // 顶栏（含上传/下载分段条）是浮层：滑块从它下方开始
                  padding: EdgeInsets.only(
                    top: headerHeight,
                    bottom: shellBottomBarInset(context),
                  ),
                  child: CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      // 顶栏不占布局，这里留出等高占位
                      SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
                      SliverFadeTransition(
                        opacity: _tabFade,
                        sliver: _TransferListSliver(
                          kind: _kind,
                          manager: manager,
                          tasks: tasks,
                          selecting: _selecting,
                          selected: _selected,
                          removing: _removing,
                          enter: _enter,
                          onToggle: _toggleSelected,
                          onLongPress: _enterSelection,
                          onMenu: _taskMenu,
                          openFile: widget.openFile ?? openFileWithSystem,
                          onCancelActive: _cancelActive,
                          onClearCompleted: _clearCompletedSection,
                          onClearFailed: _clearFailedSection,
                          onClearSkipped: _clearSkippedSection,
                          onClearPending: _clearPendingSection,
                          onUploadPending: _uploadPendingSection,
                          onSelectTasks: _selectSection,
                          onPauseAll: _pauseAll,
                          onResumeAll: _resumeAll,
                          bulkResumeRunning: _bulkResumeRunning,
                        ),
                      ),
                      // 底栏盖在正文上方（extendBody）时，补足列表末尾留白
                      // 空列表时不要加：占满高度的空状态已经算好可见区域，
                      // 再加这份留白会让「暂无上传任务」这类提示能往下滑
                      if (tasks.isNotEmpty)
                        SliverToBoxAdapter(
                          child: SizedBox(height: shellBottomBarInset(context)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // 顶栏浮层：与底栏共用收起进度，切换视图时会下滑出现
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: TopBarOverlay(
                height: headerHeight,
                background: topBarBackgroundColor(context, scheme),
                // 显式高度：带 bottom 的 AppBar 需要有限高度约束
                builder: (context) => SizedBox(
                  height: headerHeight,
                  // 点顶栏空白处回到列表顶部（按钮 / 分段按钮自行响应）
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _scrollToTop,
                    child: AppBar(
                      backgroundColor: Colors.transparent,
                      scrolledUnderElevation: 0,
                      leading: (ModalRoute.of(context)?.isFirst ?? true)
                          ? null
                          : const AppBarBackButton(),
                      title: Text(l10n.transfers),
                      actions: [
                        IconButton(
                          tooltip: l10n.multiSelect,
                          icon: const Icon(Icons.checklist),
                          onPressed: () => _enterSelection(),
                        ),
                      ],
                      bottom: PreferredSize(
                        preferredSize: const Size.fromHeight(
                          kTransfersTabBarHeight,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          // 多选期间也可以切换上传 / 下载：切换后自动退出多选
                          child: SizedBox(
                            width: double.infinity,
                            child: M3eConnectedButtonGroup<int>(
                              // 下载更高频，固定在左侧并作为默认页面。
                              values: const [1, 0],
                              selected: _tab,
                              onSelected: (value) {
                                if (value == _tab) return;
                                if (_selecting) _exitSelection();
                                setState(() => _tab = value);
                                if (reduceMotionOf(context)) {
                                  // 少动效：切上传 / 下载直接到位
                                  _tabAnim.value = 1;
                                } else {
                                  _tabAnim.forward(from: 0);
                                }
                                // 切换上传 / 下载：整组重播一次入场动画
                                _replayEnter();
                              },
                              labelOf: (value) => Text(
                                value == 1 ? l10n.download : l10n.upload,
                              ),
                              iconOf: (value) => Icon(
                                value == 1 ? Icons.download : Icons.upload,
                              ),
                              semanticLabel:
                                  '${l10n.download} / ${l10n.upload}',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 多选顶栏：覆盖标题行（上传/下载切换保留在下方）
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                ignoring: !_selecting,
                child: AnimatedOpacity(
                  opacity: _selecting ? 1 : 0,
                  duration: _anim,
                  curve: Curves.easeInOut,
                  child: Material(
                    elevation: 0,
                    // 与网盘页多选条一致：小屏随滚动渐变，大屏保持侧栏同色
                    color: topBarBackgroundColor(context, scheme),
                    // 显式高度：Stack 的 Positioned 不提供高度约束
                    child: SizedBox(
                      height:
                          MediaQuery.paddingOf(context).top + kToolbarHeight,
                      child: AppBar(
                        key: const ValueKey('transfers-selection-appbar'),
                        // 底色由外层 Material 提供（与网盘页多选条一致），
                        // 否则 AppBar 会用自己的 surface 把外层颜色盖住
                        backgroundColor: Colors.transparent,
                        scrolledUnderElevation: 0,
                        leading: IconButton(
                          tooltip: l10n.exitSelection,
                          icon: const Icon(Icons.close),
                          onPressed: _exitSelection,
                        ),
                        title: Text(l10n.selectedCount(selectedCount)),
                        actions: [
                          IconButton(
                            tooltip: l10n.selectAll,
                            icon: const Icon(Icons.select_all),
                            onPressed: _selectAll,
                          ),
                          IconButton(
                            tooltip: l10n.invertSelection,
                            icon: const Icon(Icons.flip),
                            onPressed: _invertSelection,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 多选操作栏
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_selecting,
                child: AnimatedOpacity(
                  opacity: _selecting ? 1 : 0,
                  duration: _anim,
                  curve: Curves.easeInOut,
                  child: BatchActionBar(
                    children: [
                      if (uploadTab) ...[
                        BatchAction(
                          icon: Icons.input_field,
                          label: l10n.rename,
                          onPressed: renameCount == 0 ? null : _renameSelected,
                        ),
                        BatchAction(
                          icon: Icons.upload,
                          label: l10n.upload,
                          onPressed: pendingCount == 0 ? null : _uploadSelected,
                        ),
                      ],
                      if (!uploadTab && PlatformSupport.isAndroid)
                        BatchAction(
                          icon: Icons.share_outlined,
                          label: l10n.share,
                          onPressed: shareCount == 0 ? null : _shareSelected,
                        ),
                      BatchAction(
                        icon: Icons.delete_outline,
                        label: l10n.delete,
                        onPressed: selectedCount == 0 ? null : _deleteSelected,
                      ),
                      BatchAction(
                        icon: Icons.refresh,
                        label: l10n.retry,
                        onPressed: retryCount == 0 ? null : _retrySelected,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferListSliver extends StatelessWidget {
  const _TransferListSliver({
    required this.kind,
    required this.manager,
    required this.tasks,
    required this.selecting,
    required this.selected,
    required this.removing,
    required this.enter,
    required this.onToggle,
    required this.onLongPress,
    required this.onMenu,
    required this.openFile,
    required this.onCancelActive,
    required this.onClearCompleted,
    required this.onClearFailed,
    required this.onClearSkipped,
    required this.onClearPending,
    required this.onUploadPending,
    required this.onSelectTasks,
    required this.onPauseAll,
    required this.onResumeAll,
    required this.bulkResumeRunning,
  });

  final TransferKind kind;
  final TransferManager manager;
  final List<TransferTask> tasks;
  final bool selecting;
  final Set<String> selected;

  /// 正在播放删除动画的记录 id。
  final Set<String> removing;

  /// 列表入场动画的共享进度（只播一次，懒加载进来的条目不重播）。
  final Animation<double> enter;
  final void Function(String id) onToggle;
  final void Function({String? taskId}) onLongPress;

  /// 点 ⋯ / 鼠标右键：打开条目菜单（锚点是行或⋯按钮的 context）。
  final void Function(
    TransferTask task,
    BuildContext anchorContext, {
    Offset? pointerPosition,
  })
  onMenu;

  /// 打开已下载的文件（外壳注入，默认交给系统默认程序）。
  final TransferFileOpener openFile;

  final VoidCallback onCancelActive;
  final VoidCallback onClearCompleted;
  final VoidCallback onClearFailed;
  final VoidCallback onClearSkipped;
  final VoidCallback onClearPending;
  final VoidCallback onUploadPending;
  final void Function(Iterable<String>) onSelectTasks;
  final VoidCallback onPauseAll;
  final VoidCallback onResumeAll;
  final bool bulkResumeRunning;

  /// 点击条目：多选中切换选中；否则只有「下载完成」的条目能打开文件，
  /// 上传条目（以及进行中 / 失败的下载）点击不做任何反应。
  Future<void> _handleTap(BuildContext context, TransferTask task) async {
    if (selecting) {
      onToggle(task.id);
      return;
    }
    final path = task.savedPath;
    if (task.kind == TransferKind.download &&
        task.status == TransferStatus.done &&
        path != null) {
      final opened = await openFile(path, name: task.name);
      if (!opened.isSuccess && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fileOpenFailureMessage(
                context.l10n,
                opened.failure ?? FileOpenFailure.systemError,
              ),
            ),
          ),
        );
      }
    }
  }

  Widget _actionButton({
    required String key,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return TextButton(
      key: ValueKey(key),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: Text(label, maxLines: 1, softWrap: false),
    );
  }

  List<Widget> _sectionActions({
    required AppLocalizations l10n,
    required String key,
    required Iterable<TransferTask> tasks,
    required List<Widget> actions,
  }) {
    if (!selecting) return actions;
    return [
      _actionButton(
        key: key,
        label: l10n.select,
        onPressed: () => onSelectTasks(tasks.map((task) => task.id)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (tasks.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          // 底栏盖在正文上方时，空状态保持在可见区域居中
          padding: EdgeInsets.only(bottom: shellBottomBarInset(context)),
          child: Center(
            child: EmptyHint(
              icon: kind == TransferKind.upload ? Icons.upload : Icons.download,
              text: kind == TransferKind.upload
                  ? l10n.noUploads
                  : l10n.noDownloads,
            ),
          ),
        ),
      );
    }
    final pending = _newestFirst(tasks.where(_isPendingUpload));
    final active = _newestFirst(tasks.where(_isInProgressTask));
    final skipped = _newestFirst(tasks.where(_isSkippedUpload));
    final failed = _newestFirst(tasks.where(_isFailedTask));
    final completed = _newestFirst(tasks.where(_isCompletedTask));
    final paused = active
        .where((task) => task.status == TransferStatus.paused)
        .length;
    final pausable = active.where(_isPausableDownload).length;
    final activeActions = <Widget>[];
    if (kind == TransferKind.upload) {
      activeActions.add(
        _actionButton(
          key: 'transfers-cancel-all',
          label: l10n.cancelAll,
          onPressed: onCancelActive,
        ),
      );
    } else if (paused == 0) {
      activeActions.add(
        _actionButton(
          key: 'transfers-pause-all',
          label: l10n.pauseAll,
          onPressed: pausable == 0 ? null : onPauseAll,
        ),
      );
    } else if (pausable > 0) {
      activeActions.add(
        _actionButton(
          key: 'transfers-resume-all',
          label: l10n.resumeAll,
          onPressed: bulkResumeRunning ? null : onResumeAll,
        ),
      );
    } else {
      activeActions.addAll([
        _actionButton(
          key: 'transfers-cancel-all',
          label: l10n.cancelAll,
          onPressed: onCancelActive,
        ),
        _actionButton(
          key: 'transfers-resume-all',
          label: l10n.resumeAll,
          onPressed: bulkResumeRunning ? null : onResumeAll,
        ),
      ]);
    }
    return SliverPadding(
      // 与收藏页一致：外层 12 + SegmentedList 自带 4
      // 底部留白与首页 / 网盘 / 收藏保持一致
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      sliver: SliverMainAxisGroup(
        slivers: [
          if (pending.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: l10n.pendingUploads,
                count: pending.length,
                compact: !PlatformSupport.isDesktop,
                actions: _sectionActions(
                  l10n: l10n,
                  key: 'transfers-select-pending',
                  tasks: pending,
                  actions: [
                    _actionButton(
                      key: 'transfers-clear-pending',
                      label: l10n.clearAll,
                      onPressed: onClearPending,
                    ),
                    _actionButton(
                      key: 'transfers-upload-pending',
                      label: l10n.upload,
                      onPressed: onUploadPending,
                    ),
                  ],
                ),
              ),
            ),
            SegmentedSliverList(
              adaptive: true,
              minItemWidth: kAdaptiveDenseListItemMinWidth,
              findChildIndexCallback: childIndexLookup(
                pending,
                (t) => ValueKey('transfer-${t.id}'),
              ),
              itemCount: pending.length,
              itemBuilder: (context, index) => ListEnterAnimation(
                key: ValueKey('transfer-${pending[index].id}'),
                progress: enter,
                index: index,
                child: _TransferTile(
                  task: pending[index],
                  manager: manager,
                  index: index,
                  removing: removing.contains(pending[index].id),
                  selecting: selecting,
                  selected: selected.contains(pending[index].id),
                  onTap: () => _handleTap(context, pending[index]),
                  onLongPress: () => onLongPress(taskId: pending[index].id),
                  onMenu: (anchorContext, {pointerPosition}) => onMenu(
                    pending[index],
                    anchorContext,
                    pointerPosition: pointerPosition,
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
          if (active.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: l10n.inProgress,
                count: active.length,
                compact: !PlatformSupport.isDesktop,
                actions: _sectionActions(
                  l10n: l10n,
                  key: 'transfers-select-active',
                  tasks: active,
                  actions: activeActions,
                ),
              ),
            ),
            // MD3E 连接式列表（懒加载）：组外侧 16dp / 组内相邻 4dp，和收藏页同款
            SegmentedSliverList(
              adaptive: true,
              minItemWidth: kAdaptiveDenseListItemMinWidth,
              // 幸存条目按 key 复用元素，删除后不重播出现动画
              findChildIndexCallback: childIndexLookup(
                active,
                (t) => ValueKey('transfer-${t.id}'),
              ),
              itemCount: active.length,
              itemBuilder: (context, index) => ListEnterAnimation(
                // key 挂在最外层：sliver 靠它把条目认回来（见 findChildIndexCallback）
                key: ValueKey('transfer-${active[index].id}'),
                progress: enter,
                index: index,
                child: _TransferTile(
                  task: active[index],
                  manager: manager,
                  index: index,
                  removing: removing.contains(active[index].id),
                  selecting: selecting,
                  selected: selected.contains(active[index].id),
                  onTap: () => _handleTap(context, active[index]),
                  onLongPress: () => onLongPress(taskId: active[index].id),
                  onMenu: (anchorContext, {pointerPosition}) => onMenu(
                    active[index],
                    anchorContext,
                    pointerPosition: pointerPosition,
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
          if (skipped.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: l10n.skippedUploads,
                count: skipped.length,
                compact: !PlatformSupport.isDesktop,
                actions: _sectionActions(
                  l10n: l10n,
                  key: 'transfers-select-skipped',
                  tasks: skipped,
                  actions: [
                    _actionButton(
                      key: 'transfers-clear-skipped',
                      label: l10n.clearAll,
                      onPressed: onClearSkipped,
                    ),
                  ],
                ),
              ),
            ),
            SegmentedSliverList(
              adaptive: true,
              minItemWidth: kAdaptiveDenseListItemMinWidth,
              findChildIndexCallback: childIndexLookup(
                skipped,
                (t) => ValueKey('transfer-${t.id}'),
              ),
              itemCount: skipped.length,
              itemBuilder: (context, index) => ListEnterAnimation(
                key: ValueKey('transfer-${skipped[index].id}'),
                progress: enter,
                index: index,
                child: _TransferTile(
                  task: skipped[index],
                  manager: manager,
                  index: index,
                  removing: removing.contains(skipped[index].id),
                  selecting: selecting,
                  selected: selected.contains(skipped[index].id),
                  onTap: () => _handleTap(context, skipped[index]),
                  onLongPress: () => onLongPress(taskId: skipped[index].id),
                  onMenu: (anchorContext, {pointerPosition}) => onMenu(
                    skipped[index],
                    anchorContext,
                    pointerPosition: pointerPosition,
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
          if (failed.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: l10n.failed,
                count: failed.length,
                compact: !PlatformSupport.isDesktop,
                actions: _sectionActions(
                  l10n: l10n,
                  key: 'transfers-select-failed',
                  tasks: failed,
                  actions: [
                    _actionButton(
                      key: 'transfers-clear-failed',
                      label: l10n.clearAll,
                      onPressed: onClearFailed,
                    ),
                  ],
                ),
              ),
            ),
            SegmentedSliverList(
              adaptive: true,
              minItemWidth: kAdaptiveDenseListItemMinWidth,
              findChildIndexCallback: childIndexLookup(
                failed,
                (t) => ValueKey('transfer-${t.id}'),
              ),
              itemCount: failed.length,
              itemBuilder: (context, index) => ListEnterAnimation(
                key: ValueKey('transfer-${failed[index].id}'),
                progress: enter,
                index: index,
                child: _TransferTile(
                  task: failed[index],
                  manager: manager,
                  index: index,
                  removing: removing.contains(failed[index].id),
                  selecting: selecting,
                  selected: selected.contains(failed[index].id),
                  onTap: () => _handleTap(context, failed[index]),
                  onLongPress: () => onLongPress(taskId: failed[index].id),
                  onMenu: (anchorContext, {pointerPosition}) => onMenu(
                    failed[index],
                    anchorContext,
                    pointerPosition: pointerPosition,
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
          if (completed.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: l10n.finished,
                count: completed.length,
                compact: !PlatformSupport.isDesktop,
                actions: _sectionActions(
                  l10n: l10n,
                  key: 'transfers-select-finished',
                  tasks: completed,
                  actions: [
                    _actionButton(
                      key: 'transfers-clear-finished',
                      label: l10n.clearAll,
                      onPressed: onClearCompleted,
                    ),
                  ],
                ),
              ),
            ),
            SegmentedSliverList(
              adaptive: true,
              minItemWidth: kAdaptiveDenseListItemMinWidth,
              findChildIndexCallback: childIndexLookup(
                completed,
                (t) => ValueKey('transfer-${t.id}'),
              ),
              // 与收藏页同色（SegmentedList 默认 surfaceContainerLow）
              itemCount: completed.length,
              itemBuilder: (context, index) => ListEnterAnimation(
                key: ValueKey('transfer-${completed[index].id}'),
                progress: enter,
                index: index,
                child: _TransferTile(
                  task: completed[index],
                  manager: manager,
                  index: index,
                  removing: removing.contains(completed[index].id),
                  selecting: selecting,
                  selected: selected.contains(completed[index].id),
                  onTap: () => _handleTap(context, completed[index]),
                  onLongPress: () => onLongPress(taskId: completed[index].id),
                  onMenu: (anchorContext, {pointerPosition}) => onMenu(
                    completed[index],
                    anchorContext,
                    pointerPosition: pointerPosition,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单条传输记录：MD3E 列表条目 —— 文件类型图标（圆角容器）+ 名称/状态 + 操作，
/// 进行中在下方显示进度条。
class _TransferTile extends StatelessWidget {
  const _TransferTile({
    required this.task,
    required this.manager,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenu,
    this.index = 0,
    this.removing = false,
  });

  final TransferTask task;
  final TransferManager manager;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// 点 ⋯ / 鼠标右键：打开条目菜单（锚点分别为按钮 / 整行）。
  final void Function(BuildContext anchorContext, {Offset? pointerPosition})
  onMenu;
  final int index;
  final bool removing;

  String? _issueText(AppLocalizations l10n) {
    final issue = TransferIssue.decode(task.error);
    if (issue == null) return null;
    return switch (issue.code) {
      TransferIssueCode.skippedOversize =>
        issue.detail.isEmpty
            ? null
            : l10n.uploadSkippedReasonOversize(issue.detail),
      TransferIssueCode.skippedUnsupported =>
        l10n.uploadSkippedReasonUnsupported,
      TransferIssueCode.uploadSourceMissing => l10n.retryUploadFileGone,
      TransferIssueCode.uploadPermissionExpired =>
        l10n.retryUploadPermissionExpired,
      TransferIssueCode.uploadSourceUnavailable => l10n.retryUploadUnavailable,
      TransferIssueCode.uploadNeedLogin => l10n.uploadNeedLogin,
    };
  }

  String _statusText(AppLocalizations l10n) {
    switch (task.status) {
      case TransferStatus.pending:
        return l10n.pendingUploads;
      case TransferStatus.queued:
        return l10n.queued;
      case TransferStatus.resolving:
        return l10n.resolving;
      case TransferStatus.running:
        return task.kind == TransferKind.upload
            ? l10n.uploading
            : l10n.downloading;
      case TransferStatus.resuming:
        return l10n.resumingDownload;
      case TransferStatus.paused:
        return l10n.paused;
      case TransferStatus.saving:
        return l10n.saving;
      case TransferStatus.skipped:
        return l10n.skippedUploads;
      case TransferStatus.done:
        return l10n.completed;
      case TransferStatus.failed:
        return _issueText(l10n) ??
            l10n.transferFailureDetail(error: task.error);
      case TransferStatus.canceled:
        return l10n.canceled;
    }
  }

  String _sizeText(AppLocalizations l10n) {
    if (task.total <= 0) {
      return task.status == TransferStatus.running ||
              task.status == TransferStatus.resolving ||
              task.status == TransferStatus.resuming ||
              task.status == TransferStatus.saving
          ? l10n.unknownSize
          : '';
    }
    if (task.status == TransferStatus.pending) return formatBytes(task.total);
    if (task.received >= task.total) return formatBytes(task.total);
    return '${formatBytes(task.received)} / ${formatBytes(task.total)}';
  }

  String _statusLine(AppLocalizations l10n) {
    final status = _statusText(l10n);
    if (task.status == TransferStatus.done) {
      return task.total > 0 ? formatBytes(task.total) : '';
    }
    if (task.status == TransferStatus.failed) return status;
    if (task.status == TransferStatus.pending) {
      final issueText = _issueText(l10n);
      if (issueText != null) return issueText;
    }
    if (task.status == TransferStatus.skipped) {
      final issueText = _issueText(l10n);
      if (issueText != null) return issueText;
      final reason = task.error?.trim() ?? '';
      if (reason.isEmpty) return status;
      return reason;
    }
    final size = _sizeText(l10n);
    return size.isEmpty ? status : '$status · $size';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final active =
        task.status == TransferStatus.running ||
        task.status == TransferStatus.queued;
    final resolving = task.status == TransferStatus.resolving;
    final resuming = task.status == TransferStatus.resuming;
    final paused = task.status == TransferStatus.paused;
    final saving = task.status == TransferStatus.saving;
    final skipped = _isSkippedUpload(task);
    final pending = _isPendingUpload(task);
    final completed = _isCompletedTask(task);
    final failed = _isFailedTask(task);
    final terminal = completed || failed;
    // 与首页 / 收藏共用同一套列表项布局，圆角由外层 SegmentedList 控制
    // 菜单要贴在被点的那颗 ⋯（鼠标右键时是整行）下方，所以这里得拿到两个 context
    return Builder(
      builder: (BuildContext rowContext) => Md3ListItem(
        key: ValueKey('transfer-${task.id}'),
        index: index,
        // 入场动画由外层 ListEnterAnimation 统一驱动（只播一次）
        animateIn: false,
        removing: removing,
        icon: iconForFile(task.name),
        iconColor: fileIconColor(task.name, brightness: scheme.brightness),
        title: task.name,
        subtitle: _statusLine(l10n),
        titleMaxLines: 2,
        subtitleMaxLines: 2,
        selected: selected,
        onTap: onTap,
        onLongPress: onLongPress,
        // 鼠标：点图标块 = 进入多选并选中 / 已选中时取消选中
        onIconTap: iconTapFor(
          selected: selected,
          onTap: onTap,
          onLongPress: onLongPress,
        ),
        // 右键与 ⋯ 菜单可用性一致：多选和进行中任务都不响应。
        onSecondaryTap: selecting || (!terminal && !skipped && !pending)
            ? null
            : (Offset position) =>
                  onMenu(rowContext, pointerPosition: position),
        // 多选期间隐藏行内操作（避免误触），但保留占位：条目高度不跳
        trailing: HideKeepingSpace(
          hidden: selecting,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (task.kind == TransferKind.download &&
                  (active || resolving || resuming || saving))
                M3eIconButton(
                  tooltip: l10n.pauseDownload,
                  icon: Icons.pause,
                  onPressed: active ? () => manager.pause(task.id) : null,
                ),
              if (paused)
                M3eIconButton(
                  tooltip: l10n.resumeDownload,
                  icon: Icons.play_arrow,
                  onPressed: () => manager.resume(task.id),
                ),
              if (active || resolving || resuming || paused || saving)
                M3eIconButton(
                  tooltip: l10n.cancelTask,
                  icon: Icons.close,
                  onPressed: saving ? null : () => manager.removeTask(task.id),
                ),
              if (pending)
                M3eIconButton(
                  key: ValueKey('upload-start-${task.id}'),
                  tooltip: l10n.upload,
                  icon: Icons.upload,
                  onPressed: () => manager.startUploads([task.id]),
                ),
              if (terminal || skipped || pending)
                Builder(
                  builder: (BuildContext buttonContext) => M3eIconButton(
                    tooltip: l10n.moreActions,
                    icon: Icons.more_vert,
                    onPressed: () => onMenu(buttonContext),
                  ),
                ),
            ],
          ),
        ),
        bottom: active || resolving || resuming || paused || saving
            ? M3eLinearProgressIndicator(
                // 只有真正下载运行时才用波浪；解析、排队、暂停、恢复、
                // 保存和上传阶段都保持平直，避免和实际传输状态混淆。
                // 进度 / 轨道用 M3 的默认角色（primary / secondary container），
                // 不再另外指定颜色。
                value: resolving ? null : task.progress,
                wavy:
                    task.kind == TransferKind.download &&
                    task.status == TransferStatus.running,
              )
            : null,
      ),
    );
  }
}

/// 分享下载文件时用的 MIME：APK 单独识别（其它应用按包安装），
/// 其余交给系统按扩展名兜底。
String _shareMimeFor(String name) => name.toLowerCase().endsWith('.apk')
    ? 'application/vnd.android.package-archive'
    : 'application/octet-stream';
