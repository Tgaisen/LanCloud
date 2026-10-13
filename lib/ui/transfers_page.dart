import 'dart:async';

import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/platform_support.dart';
import '../core/saved_file.dart';
import '../core/system_open.dart';
import '../core/system_share.dart';
import '../core/transfer/transfer_manager.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';
import 'reduce_motion.dart';
import 'scroll_tint.dart';

/// 传输条目 ⋯ 菜单里的动作。
///
/// 「打开 / 分享」只对已下载完成的条目有意义，「重试」只对失败条目有意义，
/// 「删除记录与文件」只对下载且文件已落盘、任务已停下（不在跑）的条目给出。
enum _TransferMenuAction {
  open,
  share,
  retry,
  removeRecord,
  removeRecordAndFile,
}

class TransfersPage extends StatefulWidget {
  const TransfersPage({super.key, this.tabIndex, this.openFile});

  /// 外壳中的 page 视图下标；作为独立路由打开时为 null（不响应切换通知）。
  final int? tabIndex;

  /// 打开已下载文件；默认交给系统「打开」，测试注入以免真的调起系统应用。
  final Future<void> Function(String path)? openFile;

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
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

  /// 列表入场动画：只在首次加载 / 切到本视图 / 切换上传下载时整组播一次，
  /// 滑动时懒构建出来的条目不再重播（与收藏页一致，改用共享进度驱动）。
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: ListEnterAnimation.duration,
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
    final app = context.read<AppController>();
    if (!identical(app, _app)) {
      _app?.activeTab.removeListener(_onActiveTabChanged);
      _app = app;
      app.activeTab.addListener(_onActiveTabChanged);
    }
  }

  /// 切到本视图时重播一次入场动画（与收藏页同款）。
  void _onActiveTabChanged() {
    final app = _app;
    if (app == null || widget.tabIndex == null) return;
    if (app.activeTab.value == widget.tabIndex) {
      _replayEnter();
    }
  }

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
    // 首次加载：整组播一次入场动画（之后靠切视图 / 切 tab 重播）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _replayEnter();
    });
  }

  @override
  void dispose() {
    if (_selecting && _app != null) {
      final app = _app!;
      app.setSelectionMode(false);
      app.onRequestExitSelection = null;
    }
    _app?.activeTab.removeListener(_onActiveTabChanged);
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
      context.read<AppController>().onRequestExitSelection?.call();
    }
    setState(() {
      _selecting = true;
      if (taskId != null) _selected.add(taskId);
    });
    final app = context.read<AppController>();
    app.onRequestExitSelection = _exitSelection;
    app.setSelectionMode(true);
    if (!wasSelecting) announceEnteredMultiSelect(context);
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
          // 内容不加左右内边距：复选行自己铺满弹窗宽度，
          // 点按波纹 / 悬停高亮和「恢复确认」弹窗一样覆盖整行
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(l10n.transferDeleteConfirmMessage(count)),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                // 文字与弹窗内其它内容左对齐，但墨水区域是整行
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
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
    final tasks = manager.tasks.where((t) => _selected.contains(t.id)).toList();
    final ids = _selected.toList();
    _exitSelection();
    // 批量删除不逐条播动画：一次落库、一次通知，列表整体刷新一遍
    manager.removeTasks(ids);
    // 下载到本地的文件由本应用写入：普通路径直接删，SAF 文件走系统授权删
    if (deleteFiles) {
      for (final task in tasks) {
        final path = task.savedPath;
        if (path == null || path.isEmpty) continue;
        await deleteSavedFile(path);
      }
    }
  }

  /// 重试选中的失败项（其它状态忽略）。
  ///
  /// 重启后的下载任务要先重新解析直链，所以整批都放在进度弹窗里跑
  /// （和首页批量下载同一套样式），结束后提示结果。
  Future<void> _retrySelected() async {
    final manager = context.read<TransferManager>();
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
  Future<void> _openTaskFile(String path) =>
      (widget.openFile ?? openFileWithSystem)(path);

  /// 条目 ⋯ 菜单：按条目状态给出可用动作。
  ///
  /// [anchorContext] 是那颗 ⋯ 按钮（桌面端右键时是整行）的 context——
  /// 菜单贴它下方右对齐弹出。
  Future<void> _taskMenu(TransferTask task, BuildContext anchorContext) async {
    final anchor = m3eMenuAnchorOf(anchorContext);
    if (anchor == null) return;
    final l10n = context.l10n;
    final manager = context.read<TransferManager>();
    final path = task.savedPath;
    final done = task.status == TransferStatus.done && path != null;
    final failed = task.status == TransferStatus.failed;
    // 「删除记录与文件」只在任务停下之后给：正在写的半截文件删掉会打断下载器
    final stopped =
        task.status != TransferStatus.running &&
        task.status != TransferStatus.queued;
    final desktop = PlatformSupport.isDesktop;
    final _TransferMenuAction? action = await showM3eMenu<_TransferMenuAction>(
      context: context,
      anchor: anchor,
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
        M3eMenuItem(
          value: _TransferMenuAction.removeRecord,
          // 下载任务叫「删除下载记录」；上传没有本地文件语义，沿用「删除此条记录」
          label: task.kind == TransferKind.download
              ? l10n.deleteDownloadRecord
              : l10n.deleteRecord,
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
        await _openTaskFile(path!);
      case _TransferMenuAction.share:
        await SystemShare.shareFile(
          path!,
          subject: task.name,
          mime: _shareMimeFor(task.name),
        );
      case _TransferMenuAction.retry:
        final message = await manager.retry(task.id);
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
    final manager = context.read<TransferManager>();
    setState(() => _removing.add(task.id));
    await Future<void>.delayed(const Duration(milliseconds: 220));
    // 动画期间页面可能已经被移出树（比如返回了上一页）：记录照删
    if (mounted) setState(() => _removing.remove(task.id));
    manager.removeTasks([task.id]);
    // 文件删除放最后、不挡动画，失败也静默（和批量删除同一个口径）
    if (deleteFile) unawaited(_deleteTaskFile(task));
  }

  /// 删掉下载下来的本地文件（文件由本应用写入，删除属于正常操作）。
  Future<void> _deleteTaskFile(TransferTask task) async {
    final path = task.savedPath;
    if (path == null || path.isEmpty) return;
    await deleteSavedFile(path);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.read<AppController>();
    final manager = context.watch<TransferManager>();
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final headerHeight =
        MediaQuery.paddingOf(context).top + kToolbarHeight + 58;
    final tasks = _tasksOf(manager);
    final selectedCount = _selected.length;
    final retryCount = tasks
        .where(
          (t) => _selected.contains(t.id) && t.status == TransferStatus.failed,
        )
        .length;
    return PopScope(
      // 独立页面（_openView 打开的二级路由）没有外壳的返回处理：
      // 多选状态下返回先退出多选；位于底栏（首个路由）时交给外壳统一处理。
      // 注意不能用 tabIndex 判断：独立打开时它也带着同一个值。
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
                readBarsHidden: () => app.topBarHide.value,
                onBarsHidden: app.settings.hideTopBar
                    ? app.setTopBarHideFromScroll
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
                          selecting: _selecting,
                          selected: _selected,
                          removing: _removing,
                          enter: _enter,
                          onToggle: _toggleSelected,
                          onLongPress: _enterSelection,
                          onMenu: _taskMenu,
                          openFile: widget.openFile ?? openFileWithSystem,
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
                        IconButton(
                          tooltip: l10n.clearFinished,
                          icon: const Icon(Icons.delete_sweep_outlined),
                          onPressed: () =>
                              context.read<TransferManager>().clearFinished(),
                        ),
                      ],
                      bottom: PreferredSize(
                        preferredSize: const Size.fromHeight(
                          kTransfersTabBarHeight,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          // 多选期间禁用切换上传/下载
                          child: IgnorePointer(
                            ignoring: _selecting,
                            child: SizedBox(
                              width: double.infinity,
                              child: M3eConnectedButtonGroup<int>(
                                values: const [0, 1],
                                selected: _tab,
                                onSelected: (value) {
                                  if (value == _tab) return;
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
                                  value == 0 ? l10n.upload : l10n.download,
                                ),
                                iconOf: (value) => Icon(
                                  value == 0 ? Icons.upload : Icons.download,
                                ),
                                semanticLabel:
                                    '${l10n.upload} / ${l10n.download}',
                              ),
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
                    // 大屏（底栏变侧栏）时和网盘页多选条同色；小屏保持原样
                    color: isLargeLayout(context)
                        ? scheme.surfaceContainer
                        : scheme.surface,
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
    required this.selecting,
    required this.selected,
    required this.removing,
    required this.enter,
    required this.onToggle,
    required this.onLongPress,
    required this.onMenu,
    required this.openFile,
  });

  final TransferKind kind;
  final bool selecting;
  final Set<String> selected;

  /// 正在播放删除动画的记录 id。
  final Set<String> removing;

  /// 列表入场动画的共享进度（只播一次，懒加载进来的条目不重播）。
  final Animation<double> enter;
  final void Function(String id) onToggle;
  final void Function({String? taskId}) onLongPress;

  /// 点 ⋯ / 桌面端右键：打开条目菜单（锚点是行或⋯按钮的 context）。
  final void Function(TransferTask task, BuildContext anchorContext) onMenu;

  /// 打开已下载的文件（外壳注入，默认交给系统默认程序）。
  final Future<void> Function(String path) openFile;

  /// 点击条目：多选中切换选中；否则只有「下载完成」的条目能打开文件，
  /// 上传条目（以及进行中 / 失败的下载）点击不做任何反应。
  void _handleTap(TransferTask task) {
    if (selecting) {
      onToggle(task.id);
      return;
    }
    final path = task.savedPath;
    if (task.kind == TransferKind.download &&
        task.status == TransferStatus.done &&
        path != null) {
      openFile(path);
    }
  }

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
              icon: kind == TransferKind.upload ? Icons.upload : Icons.download,
              text: kind == TransferKind.upload
                  ? l10n.noUploads
                  : l10n.noDownloads,
            ),
          ),
        ),
      );
    }
    bool isActive(TransferTask t) =>
        t.status == TransferStatus.queued || t.status == TransferStatus.running;
    final active = tasks.where(isActive).toList();
    final finished = tasks
        .where((t) => !isActive(t))
        .toList()
        .reversed
        .toList();
    return SliverPadding(
      // 与收藏页一致：外层 12 + SegmentedList 自带 4
      // 底部留白与首页 / 网盘 / 收藏保持一致
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      sliver: SliverMainAxisGroup(
        slivers: [
          if (active.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: l10n.inProgress,
                count: active.length,
              ),
            ),
            // MD3E 连接式列表（懒加载）：组外侧 16dp / 组内相邻 4dp，和收藏页同款
            SegmentedSliverList(
              adaptive: true,
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
                  index: index,
                  removing: removing.contains(active[index].id),
                  selecting: selecting,
                  selected: selected.contains(active[index].id),
                  onTap: () => _handleTap(active[index]),
                  onLongPress: () => onLongPress(taskId: active[index].id),
                  onMenu: (anchorContext) =>
                      onMenu(active[index], anchorContext),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
          if (finished.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: l10n.finished,
                count: finished.length,
              ),
            ),
            SegmentedSliverList(
              adaptive: true,
              findChildIndexCallback: childIndexLookup(
                finished,
                (t) => ValueKey('transfer-${t.id}'),
              ),
              // 与收藏页同色（SegmentedList 默认 surfaceContainerLow）
              itemCount: finished.length,
              itemBuilder: (context, index) => ListEnterAnimation(
                key: ValueKey('transfer-${finished[index].id}'),
                progress: enter,
                index: index,
                child: _TransferTile(
                  task: finished[index],
                  index: index,
                  removing: removing.contains(finished[index].id),
                  selecting: selecting,
                  selected: selected.contains(finished[index].id),
                  onTap: () => _handleTap(finished[index]),
                  onLongPress: () => onLongPress(taskId: finished[index].id),
                  onMenu: (anchorContext) =>
                      onMenu(finished[index], anchorContext),
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
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenu,
    this.index = 0,
    this.removing = false,
  });

  final TransferTask task;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// 点 ⋯ / 桌面端右键：打开条目菜单（锚点分别为按钮 / 整行）。
  final void Function(BuildContext anchorContext) onMenu;
  final int index;
  final bool removing;

  String _statusText(AppLocalizations l10n) {
    switch (task.status) {
      case TransferStatus.queued:
        return l10n.queued;
      case TransferStatus.running:
        return task.kind == TransferKind.upload
            ? l10n.uploading
            : l10n.downloading;
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
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final active =
        task.status == TransferStatus.running ||
        task.status == TransferStatus.queued;
    // 与首页 / 收藏共用同一套列表项布局，圆角由外层 SegmentedList 控制
    // 菜单要贴在被点的那颗 ⋯（桌面端右键时是整行）下方，所以这里得拿到两个 context
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
        // 桌面端右键：与 ⋯ 菜单同一套操作（多选时不响应，和 ⋯ 一起隐藏）
        onSecondaryTap: selecting ? null : () => onMenu(rowContext),
        // 多选期间隐藏行内操作（避免误触），但保留占位：条目高度不跳
        trailing: HideKeepingSpace(
          hidden: selecting,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (active)
                M3eIconButton(
                  tooltip: l10n.cancel,
                  icon: Icons.close,
                  onPressed: () => manager.cancel(task.id),
                ),
              // 完成 / 失败 / 删除这些操作都收进 ⋯ 菜单（菜单项按状态给出），
              // 行里只留「取消」这颗抢时间的按钮
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
        bottom: active
            ? M3eLinearProgressIndicator(
                // 传输是长任务：用 MD3E 波浪进度条，等待时不那么呆板。
                // 进度 / 轨道用 M3 的默认角色（primary / secondary container），
                // 不再另外指定颜色。
                value: task.progress,
                wavy: true,
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
