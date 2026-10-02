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
  int _tab = 0;
  final ScrollController _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.read<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final headerHeight = MediaQuery.paddingOf(context).top + kToolbarHeight + 58;
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
                kind: _tab == 0 ? TransferKind.upload : TransferKind.download,
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
        ],
      ),
    );
  }
}

class _TransferListSliver extends StatelessWidget {
  const _TransferListSliver({required this.kind});

  final TransferKind kind;

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
            _SectionHeader(title: l10n.inProgress, count: active.length),
            // MD3E 连接式列表：进行中的任务成组显示
            SegmentedList(
              children: [for (final task in active) _TransferTile(task: task)],
            ),
            const SizedBox(height: 20),
          ],
          if (finished.isNotEmpty) ...[
            _SectionHeader(title: l10n.finished, count: finished.length),
            SegmentedList(
              // 已结束整体淡一层主题色，和进行中区分
              color: Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.06),
                scheme.surfaceContainerLow,
              ),
              children: [
                for (final task in finished) _TransferTile(task: task),
              ],
            ),
          ],
          const SizedBox(height: 96),
        ]),
      ),
    );
  }
}
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单条传输记录：MD3E 列表条目 —— 文件类型图标（圆角容器）+ 名称/状态 + 操作，
/// 进行中在下方显示进度条。
class _TransferTile extends StatelessWidget {
  const _TransferTile({required this.task});

  final TransferTask task;

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
    return Padding(
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
                  color: active
                      ? scheme.secondaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  iconForFile(task.name),
                  size: 22,
                  color: active
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
    );
  }
}
