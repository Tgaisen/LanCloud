import 'dart:io';

import 'package:flutter/material.dart' hide Icons;
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/apk_installer.dart';
import '../core/transfer/transfer_manager.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'scroll_tint.dart';

class TransfersPage extends StatefulWidget {
  const TransfersPage({super.key, this.tabIndex});

  /// 外壳中的 page 视图下标；作为独立路由打开时为 null（不响应切换通知）。
  final int? tabIndex;

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  static const _anim = Duration(milliseconds: 200);

  int _tab = 0;
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
  final ScrollController _scroll = ScrollController();
  bool _selecting = false;
  final Set<String> _selected = {};
  /// 正在播放删除动画的记录（动画播完再真正移除）
  final Set<String> _removing = {};
  AppController? _app;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = context.read<AppController>();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    if (_selecting && _app != null) {
      final app = _app!;
      app.setSelectionMode(false);
      app.onRequestExitSelection = null;
    }
    _tabAnim.dispose();
    _scroll.dispose();
    super.dispose();
  }

  TransferKind get _kind =>
      _tab == 0 ? TransferKind.upload : TransferKind.download;

  List<TransferTask> _tasksOf(TransferManager manager) =>
      manager.byKind(_kind);

  void _enterSelection({String? taskId}) {
    if (!_selecting) {
      // 其它页面可能正处于多选：先退出，避免两处状态打架
      context.read<AppController>().onRequestExitSelection?.call();
    }
    setState(() {
      _selecting = true;
      if (taskId != null) _selected.add(taskId);
    });
    final app = context.read<AppController>();
    app.onRequestExitSelection = _exitSelection;
    app.setSelectionMode(true);
  }

  void _exitSelection() {
    if (!_selecting) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    final app = context.read<AppController>();
    app.onRequestExitSelection = null;
    app.setSelectionMode(false);
  }

  void _toggleSelected(String id) {
    // 不在多选时点击条目：直接进入多选并选中它（否则只会亮起却看不到多选栏）
    if (!_selecting) {
      _enterSelection(taskId: id);
      return;
    }
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _selectAll() {
    final manager = context.read<TransferManager>();
    setState(() {
      _selected
        ..clear()
        ..addAll(_tasksOf(manager).map((t) => t.id));
    });
  }

  void _invertSelection() {
    final manager = context.read<TransferManager>();
    setState(() {
      for (final task in _tasksOf(manager)) {
        if (!_selected.remove(task.id)) _selected.add(task.id);
      }
    });
  }

  /// 删除选中的传输记录（进行中的会先取消）。
  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final l10n = context.l10n;
    final count = _selected.length;
    var deleteFiles = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.transferDeleteConfirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.transferDeleteConfirmMessage(count)),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: deleteFiles,
                onChanged: (value) =>
                    setDialogState(() => deleteFiles = value ?? false),
                title: Text(l10n.deleteFilesToo),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final manager = context.read<TransferManager>();
    final tasks =
        manager.tasks.where((t) => _selected.contains(t.id)).toList();
    final ids = _selected.toList();
    _exitSelection();
    // 先播放删除动画，再真正移除记录
    setState(() => _removing.addAll(ids));
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    for (final id in ids) {
      manager.removeTask(id);
    }
    if (mounted) setState(() => _removing.removeAll(ids));
    // 下载到本地的文件由本应用写入，删除属于正常操作（不需要额外权限）
    if (deleteFiles) {
      for (final task in tasks) {
        final path = task.savedPath;
        if (path == null || path.isEmpty) continue;
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  /// 重试选中的失败项（其它状态忽略）。
  void _retrySelected() {
    final manager = context.read<TransferManager>();
    final failed = _tasksOf(manager)
        .where(
          (t) => _selected.contains(t.id) && t.status == TransferStatus.failed,
        )
        .toList();
    if (failed.isEmpty) return;
    _exitSelection();
    for (final task in failed) {
      manager.retry(task.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.read<AppController>();
    final manager = context.watch<TransferManager>();
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final headerHeight = MediaQuery.paddingOf(context).top + kToolbarHeight + 58;
    final tasks = _tasksOf(manager);
    final selectedCount = _selected.length;
    final retryCount = tasks
        .where(
          (t) => _selected.contains(t.id) && t.status == TransferStatus.failed,
        )
        .length;
    return Scaffold(
      // 大屏外壳里的页面：背景交给外壳的圆角卡片
      backgroundColor:
          transparentPageBackground(context) ? Colors.transparent : null,
      body: Stack(
        children: [
          // 小屏：正文区整体让开左右挖孔 / 侧边导航栏；顶栏（浮层）保持原样
          BodySideInset(
            child: ScrollTint(
              hideDistance: headerHeight,
              readBarsHidden: () => app.topBarHide.value,
              onBarsHidden:
                  app.settings.hideTopBar ? app.setTopBarHideFromScroll : null,
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                // 顶栏不占布局，这里留出等高占位
                SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
                SliverFadeTransition(
                  opacity: _tabFade,
                  sliver: _TransferListSliver(
                    kind: _kind,
                    selecting: _selecting,
                    selected: _selected,
                    removing: _removing,
                    onToggle: _toggleSelected,
                    onLongPress: _enterSelection,
                  ),
                ),
                // 底栏盖在正文上方（extendBody）时，补足列表末尾留白
                SliverToBoxAdapter(
                  child: SizedBox(height: shellBottomBarInset(context)),
                ),
                ],
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
                child: AppBar(
                backgroundColor: Colors.transparent,
                scrolledUnderElevation: 0,
                leading: (ModalRoute.of(context)?.isFirst ?? true)
                    ? null
                    : const AppBarBackButton(),
                title: Text(l10n.transfers),
                actions: [
                  IconButton(
                    tooltip: l10n.clearFinished,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () =>
                        context.read<TransferManager>().clearFinished(),
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(kTransfersTabBarHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    // 多选期间禁用切换上传/下载
                    child: IgnorePointer(
                      ignoring: _selecting,
                      child: SizedBox(
                        width: double.infinity,
                        child: ConnectedSegmentedButton<int>(
                          segments: [
                            ButtonSegment(
                              value: 0,
                              label: Text(l10n.upload),
                              icon: const Icon(Icons.upload),
                            ),
                            ButtonSegment(
                              value: 1,
                              label: Text(l10n.download),
                              icon: const Icon(Icons.download),
                            ),
                          ],
                          selected: {_tab},
                          onSelectionChanged: (values) {
                            if (values.first == _tab) return;
                            setState(() => _tab = values.first);
                            _tabAnim.forward(from: 0);
                          },
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
                  color: scheme.surface,
                  // 显式高度：Stack 的 Positioned 不提供高度约束
                  child: SizedBox(
                    height:
                        MediaQuery.paddingOf(context).top + kToolbarHeight,
                    child: AppBar(
                      key: const ValueKey('transfers-selection-appbar'),
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
                    BatchAction(
                      icon: Icons.delete_outline,
                      label: l10n.delete,
                      onPressed:
                          selectedCount == 0 ? null : _deleteSelected,
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
    );
  }
}

class _TransferListSliver extends StatelessWidget {
  const _TransferListSliver({
    required this.kind,
    required this.selecting,
    required this.selected,
    required this.removing,
    required this.onToggle,
    required this.onLongPress,
  });

  final TransferKind kind;
  final bool selecting;
  final Set<String> selected;
  /// 正在播放删除动画的记录 id。
  final Set<String> removing;
  final void Function(String id) onToggle;
  final void Function({String? taskId}) onLongPress;

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<TransferManager>();
    final l10n = context.l10n;
    final tasks = manager.byKind(kind);
    if (tasks.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          // 底栏盖在正文上方时，空状态保持在可见区域居中
          padding: EdgeInsets.only(bottom: shellBottomBarInset(context)),
          child: Center(
            child: EmptyHint(
              icon: kind == TransferKind.upload
                  ? Icons.upload_file
                  : Icons.download,
              text:
                  kind == TransferKind.upload ? l10n.noUploads : l10n.noDownloads,
            ),
          ),
        ),
      );
    }
    bool isActive(TransferTask t) =>
        t.status == TransferStatus.queued ||
        t.status == TransferStatus.running;
    final active = tasks.where(isActive).toList();
    final finished =
        tasks.where((t) => !isActive(t)).toList().reversed.toList();
    return SliverPadding(
      // 与收藏页一致：外层 12 + SegmentedList 自带 4
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          if (active.isNotEmpty) ...[
            SectionHeader(title: l10n.inProgress, count: active.length),
            // MD3E 连接式列表：组外侧 16dp / 组内相邻 4dp，和收藏页同款
            SegmentedList(
              adaptive: true,
              children: [
                for (var i = 0; i < active.length; i++)
                  _TransferTile(
                    task: active[i],
                    index: i,
                    removing: removing.contains(active[i].id),
                    selecting: selecting,
                    selected: selected.contains(active[i].id),
                    onTap: () => onToggle(active[i].id),
                    onLongPress: () => onLongPress(taskId: active[i].id),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (finished.isNotEmpty) ...[
            SectionHeader(title: l10n.finished, count: finished.length),
            SegmentedList(
              adaptive: true,
              // 与收藏页同色（SegmentedList 默认 surfaceContainerLow）
              children: [
                for (var i = 0; i < finished.length; i++)
                  _TransferTile(
                    task: finished[i],
                    index: i,
                    removing: removing.contains(finished[i].id),
                    selecting: selecting,
                    selected: selected.contains(finished[i].id),
                    onTap: () => onToggle(finished[i].id),
                    onLongPress: () => onLongPress(taskId: finished[i].id),
                  ),
              ],
            ),
          ],
          // 外壳里给悬浮 / 收起的底栏让位；作为独立页面打开时
          // 末尾由 shellBottomBarInset 按系统导航栏补，这里不重复
          if (inRootShell(context)) const SizedBox(height: 96),
        ]),
      ),
    );
  }
}
/// 单条传输记录：MD3E 列表条目 —— 文件类型图标（圆角容器）+ 名称/状态 + 操作，
/// 进行中在下方显示进度条。
class _TransferTile extends StatelessWidget {
  const _TransferTile({
    required this.task,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.index = 0,
    this.removing = false,
  });

  final TransferTask task;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final int index;
  final bool removing;

  String _statusText(AppLocalizations l10n) {
    switch (task.status) {
      case TransferStatus.queued:
        return l10n.queued;
      case TransferStatus.running:
        return task.kind == TransferKind.upload ? l10n.uploading : l10n.downloading;
      case TransferStatus.done:
        return l10n.completed;
      case TransferStatus.failed:
        return l10n.failedWithError(task.error ?? l10n.unknownError);
      case TransferStatus.canceled:
        return l10n.canceled;
    }
  }

  String _sizeText(AppLocalizations l10n) {
    if (task.total <= 0) {
      return task.status == TransferStatus.running ? l10n.unknownSize : '';
    }
    if (task.received >= task.total) return formatBytes(task.total);
    return '${formatBytes(task.received)} / ${formatBytes(task.total)}';
  }

  String _statusLine(AppLocalizations l10n) {
    final status = _statusText(l10n);
    if (task.status == TransferStatus.failed) return status;
    final size = _sizeText(l10n);
    return size.isEmpty ? status : '$status · $size';
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.read<TransferManager>();
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final active = task.status == TransferStatus.running || task.status == TransferStatus.queued;
    final done = task.status == TransferStatus.done && task.savedPath != null;
    // 与首页 / 收藏共用同一套列表项布局，圆角由外层 SegmentedList 控制
    return Md3ListItem(
      key: ValueKey('transfer-${task.id}'),
      index: index,
      removing: removing,
      icon: iconForFile(task.name),
      title: task.name,
      subtitle: _statusLine(l10n),
      titleMaxLines: 2,
      subtitleMaxLines: 2,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      // 多选期间隐藏行内操作，避免误触
      trailing: selecting
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    tooltip: l10n.cancel,
                    icon: const Icon(Icons.close),
                    onPressed: () => manager.cancel(task.id),
                  ),
                if (task.status == TransferStatus.failed)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    tooltip: l10n.retry,
                    icon: const Icon(Icons.refresh),
                    onPressed: () => manager.retry(task.id),
                  ),
                if (done) ...[
                  if (task.name.toLowerCase().endsWith('.apk'))
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      tooltip: l10n.install,
                      icon: const Icon(Icons.install_mobile),
                      onPressed: () async {
                        try {
                          await ApkInstaller.installApk(task.savedPath!);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                        }
                      },
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    tooltip: l10n.open,
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => OpenFilex.open(task.savedPath!),
                  ),
                ],
              ],
            ),
      bottom: active
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerLowest,
              ),
            )
          : null,
    );
  }
}
