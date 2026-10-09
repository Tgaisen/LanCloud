import 'dart:io';

import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/platform_support.dart';
import '../core/system_open.dart';
import '../core/system_share.dart';
import '../core/transfer/transfer_manager.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';
import 'reduce_motion.dart';
import 'scroll_tint.dart';

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
    final tasks = manager.tasks.where((t) => _selected.contains(t.id)).toList();
    final ids = _selected.toList();
    _exitSelection();
    // 批量删除不逐条播动画：一次落库、一次通知，列表整体刷新一遍
    manager.removeTasks(ids);
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
                          openFile: widget.openFile ?? openFileWithSystem,
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
                                  if (reduceMotionOf(context)) {
                                    // 少动效：切上传 / 下载直接到位
                                    _tabAnim.value = 1;
                                  } else {
                                    _tabAnim.forward(from: 0);
                                  }
                                  // 切换上传 / 下载：整组重播一次入场动画
                                  _replayEnter();
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
              icon: kind == TransferKind.upload
                  ? Icons.upload_file
                  : Icons.download,
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
    final active =
        task.status == TransferStatus.running ||
        task.status == TransferStatus.queued;
    final done = task.status == TransferStatus.done && task.savedPath != null;
    // 与首页 / 收藏共用同一套列表项布局，圆角由外层 SegmentedList 控制
    return Md3ListItem(
      key: ValueKey('transfer-${task.id}'),
      index: index,
      // 入场动画由外层 ListEnterAnimation 统一驱动（只播一次）
      animateIn: false,
      removing: removing,
      icon: iconForFile(task.name),
      title: task.name,
      subtitle: _statusLine(l10n),
      titleMaxLines: 2,
      subtitleMaxLines: 2,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      // 多选期间隐藏行内操作（避免误触），但保留占位：条目高度不跳
      trailing: HideKeepingSpace(
        hidden: selecting,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active)
              IconButton(
                visualDensity: VisualDensity.standard,
                iconSize: 20,
                tooltip: l10n.cancel,
                icon: const Icon(Icons.close),
                onPressed: () => manager.cancel(task.id),
              ),
            if (task.status == TransferStatus.failed)
              IconButton(
                visualDensity: VisualDensity.standard,
                iconSize: 20,
                tooltip: l10n.retry,
                icon: const Icon(Icons.refresh),
                onPressed: () => manager.retry(task.id),
              ),
            if (done) ...[
              // 点击条目即打开文件；这个按钮移动端走系统分享面板，
              // 桌面端没有分享面板，改为「打开所在文件夹」
              //（SystemShare.shareFile 在桌面端就是资源管理器定位）
              IconButton(
                visualDensity: VisualDensity.standard,
                iconSize: 20,
                tooltip: PlatformSupport.isDesktop
                    ? l10n.openContainingFolder
                    : l10n.share,
                icon: Icon(
                  PlatformSupport.isDesktop
                      ? Icons.folder_open
                      : Icons.share_outlined,
                ),
                onPressed: () => SystemShare.shareFile(
                  task.savedPath!,
                  subject: task.name,
                  mime: _shareMimeFor(task.name),
                ),
              ),
            ],
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
    );
  }
}

/// 分享下载文件时用的 MIME：APK 单独识别（其它应用按包安装），
/// 其余交给系统按扩展名兜底。
String _shareMimeFor(String name) => name.toLowerCase().endsWith('.apk')
    ? 'application/vnd.android.package-archive'
    : 'application/octet-stream';
