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
    with AutomaticKeepAliveClientMixin {
  static const _anim = Duration(milliseconds: 200);

  int _tab = 0;
  final ScrollController _scroll = ScrollController();
  bool _selecting = false;
  final Set<String> _selected = {};
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.transferDeleteConfirmTitle),
        content: Text(l10n.transferDeleteConfirmMessage(count)),
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
    );
    if (ok != true || !mounted) return;
    final manager = context.read<TransferManager>();
    final ids = _selected.toList();
    _exitSelection();
    for (final id in ids) {
      manager.removeTask(id);
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
      body: Stack(
        children: [
          ScrollTint(
            hideDistance: headerHeight,
            readBarsHidden: () => app.topBarHide.value,
            onBarsHidden:
                app.settings.hideTopBar ? app.setTopBarHideFromScroll : null,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
              // 顶栏不占布局，这里留出等高占位
              SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
              _TransferListSliver(
                kind: _kind,
                selecting: _selecting,
                selected: _selected,
                onToggle: _toggleSelected,
                onLongPress: _enterSelection,
              ),
              ],
            ),
          ),
          // 顶栏浮层：与底栏共用收起进度，切换视图时会下滑出现
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: TopBarOverlay(
              height: headerHeight,
              // 显式高度：带 bottom 的 AppBar 需要有限高度约束
              child: SizedBox(
                height: headerHeight,
                child: AppBar(
                backgroundColor: Color.lerp(
                  scheme.surface,
                  scheme.surfaceContainerHighest,
                  ScrollTint.of(context),
                ),
                scrolledUnderElevation: 0,
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
                  preferredSize: const Size.fromHeight(58),
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
                          onSelectionChanged: (values) =>
                              setState(() => _tab = values.first),
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
                child: Material(
                  elevation: 0,
                  color: scheme.surfaceContainer,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
    required this.onToggle,
    required this.onLongPress,
  });

  final TransferKind kind;
  final bool selecting;
  final Set<String> selected;
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
        child: Center(
          child: EmptyHint(
            icon: kind == TransferKind.upload
                ? Icons.upload_file
                : Icons.download,
            text: kind == TransferKind.upload ? l10n.noUploads : l10n.noDownloads,
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
    final scheme = Theme.of(context).colorScheme;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          if (active.isNotEmpty) ...[
            SectionHeader(title: l10n.inProgress, count: active.length),
            // MD3E 连接式列表：进行中的任务成组显示
            SegmentedList(
              children: [
                for (final task in active)
                  _TransferTile(
                    task: task,
                    selecting: selecting,
                    selected: selected.contains(task.id),
                    onTap: () => onToggle(task.id),
                    onLongPress: () => onLongPress(taskId: task.id),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (finished.isNotEmpty) ...[
            SectionHeader(title: l10n.finished, count: finished.length),
            SegmentedList(
              // 已结束整体淡一层主题色，和进行中区分
              color: Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.06),
                scheme.surfaceContainerLow,
              ),
              children: [
                for (final task in finished)
                  _TransferTile(
                    task: task,
                    selecting: selecting,
                    selected: selected.contains(task.id),
                    onTap: () => onToggle(task.id),
                    onLongPress: () => onLongPress(taskId: task.id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 96),
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
  });

  final TransferTask task;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

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
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ColoredBox(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 文件类型图标（跟随文件名后缀）
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.transparent
                      : active
                      ? scheme.secondaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  selected ? Icons.check_circle : iconForFile(task.name),
                  size: 22,
                  color: selected
                      ? scheme.primary
                      : active
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusLine(l10n),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              // 多选期间隐藏行内操作，避免误触
              if (!selecting && active)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  tooltip: l10n.cancel,
                  icon: const Icon(Icons.close),
                  onPressed: () => manager.cancel(task.id),
                ),
              if (!selecting && task.status == TransferStatus.failed)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  tooltip: l10n.retry,
                  icon: const Icon(Icons.refresh),
                  onPressed: () => manager.retry(task.id),
                ),
              if (!selecting && done) ...[
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
          if (active) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        ],
      ),
          ),
        ),
      ),
    );
  }
}
