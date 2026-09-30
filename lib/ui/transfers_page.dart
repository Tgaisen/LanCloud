import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/transfer/transfer_manager.dart';
import 'common.dart';
import 'scroll_tint.dart';

class TransfersPage extends StatefulWidget {
  const TransfersPage({super.key});

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final hideTop = app.settings.hideTopBar;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: hideTop,
            snap: false,
            pinned: !hideTop,
            backgroundColor: Color.lerp(
              scheme.surface,
              scheme.surfaceContainerHighest,
              ScrollTint.of(context),
            ),
            scrolledUnderElevation: 0,
            title: const Text('传输管理'),
            actions: [
              IconButton(
                tooltip: '清除已完成',
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
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        label: Text('上传'),
                        icon: Icon(Icons.upload_file),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('下载'),
                        icon: Icon(Icons.download),
                      ),
                    ],
                    selected: {_tab},
                    showSelectedIcon: false,
                    onSelectionChanged: (values) =>
                        setState(() => _tab = values.first),
                  ),
                ),
              ),
            ),
          ),
          _TransferListSliver(
            kind: _tab == 0 ? TransferKind.upload : TransferKind.download,
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
    final tasks = manager.byKind(kind);
    if (tasks.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: EmptyHint(
            icon: kind == TransferKind.upload
                ? Icons.upload_file
                : Icons.download,
            text: kind == TransferKind.upload ? '暂无上传任务' : '暂无下载任务',
          ),
        ),
      );
    }
    bool isActive(TransferTask t) =>
        t.status == TransferStatus.queued ||
        t.status == TransferStatus.running;
    final active = tasks.where(isActive).toList();
    final finished = tasks.where((t) => !isActive(t)).toList();
    return SliverPadding(
      padding: const EdgeInsets.all(12),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          if (active.isNotEmpty) ...[
            _SectionHeader(title: '进行中', count: active.length),
            for (final task in active) _TransferCard(task: task),
          ],
          if (finished.isNotEmpty) ...[
            _SectionHeader(title: '已结束', count: finished.length),
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

  String get _statusText {
    switch (task.status) {
      case TransferStatus.queued:
        return '排队中';
      case TransferStatus.running:
        return task.kind == TransferKind.upload ? '上传中' : '下载中';
      case TransferStatus.done:
        return '已完成';
      case TransferStatus.failed:
        return '失败：${task.error ?? '未知错误'}';
      case TransferStatus.canceled:
        return '已取消';
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.read<TransferManager>();
    final scheme = Theme.of(context).colorScheme;
    final active = task.status == TransferStatus.running || task.status == TransferStatus.queued;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
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
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.status == TransferStatus.done ? 1 : task.progress,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.status == TransferStatus.failed
                        ? _statusText
                        : '$_statusText · ${formatBytes(task.received)} / ${task.total > 0 ? formatBytes(task.total) : '未知大小'}',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (active)
                  IconButton(
                    tooltip: '取消',
                    icon: const Icon(Icons.close),
                    onPressed: () => manager.cancel(task.id),
                  ),
                if (task.status == TransferStatus.failed)
                  IconButton(
                    tooltip: '重试',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => manager.retry(task.id),
                  ),
                if (task.status == TransferStatus.done && task.savedPath != null) ...[
                  IconButton(
                    tooltip: '打开',
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