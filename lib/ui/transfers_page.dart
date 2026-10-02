import 'package:flutter/material.dart' hide Icons;
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final headerHeight = MediaQuery.paddingOf(context).top + kToolbarHeight + 58;
    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            slivers: [
              // 顶栏不占布局，这里留出等高占位
              SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
              _TransferListSliver(
                kind: _tab == 0 ? TransferKind.upload : TransferKind.download,
              ),
            ],
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
                      child: SegmentedButton<int>(
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
                        selectedIcon: const Icon(Icons.check),
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
    return SliverPadding(
      padding: const EdgeInsets.all(12),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          if (active.isNotEmpty) ...[
            _SectionHeader(title: l10n.inProgress, count: active.length),
            for (final task in active) _TransferCard(task: task),
          ],
          if (finished.isNotEmpty) ...[
            _SectionHeader(title: l10n.finished, count: finished.length),
            for (final task in finished) _TransferCard(task: task),
          ],
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
          Text(
            '$count',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.task});

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
    final finished = !active;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: finished
          ? Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.06),
              scheme.surfaceContainerLow,
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  task.kind == TransferKind.upload
                      ? Icons.upload_file
                      : iconForFile(task.name),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    task.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (active) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _statusLine(l10n),
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (active)
                  IconButton(
                    tooltip: l10n.cancel,
                    icon: const Icon(Icons.close),
                    onPressed: () => manager.cancel(task.id),
                  ),
                if (task.status == TransferStatus.failed)
                  IconButton(
                    tooltip: l10n.retry,
                    icon: const Icon(Icons.refresh),
                    onPressed: () => manager.retry(task.id),
                  ),
                if (task.status == TransferStatus.done && task.savedPath != null) ...[
                  if (task.name.toLowerCase().endsWith('.apk'))
                    IconButton(
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
                    tooltip: l10n.open,
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => OpenFilex.open(task.savedPath!),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
