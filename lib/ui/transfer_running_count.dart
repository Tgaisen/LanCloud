import 'package:flutter/widgets.dart';

import '../core/transfer/transfer_manager.dart';

/// 只订阅运行中 / 排队任务数。
///
/// `TransferManager` 仍以 `ChangeNotifier` 高频报告进度，普通 Riverpod
/// `Provider` 不会转发这些通知；这里过滤掉同数量的更新，只在任务数变化时
/// 重建调用方，保留原 `context.select` 的窄订阅语义。
class TransferRunningCount extends StatefulWidget {
  const TransferRunningCount({
    super.key,
    required this.manager,
    required this.builder,
  });

  final TransferManager manager;
  final Widget Function(BuildContext context, int running) builder;

  @override
  State<TransferRunningCount> createState() => _TransferRunningCountState();
}

class _TransferRunningCountState extends State<TransferRunningCount> {
  late int _running = _count(widget.manager);

  static int _count(TransferManager manager) => manager.tasks
      .where(
        (task) =>
            task.status == TransferStatus.running ||
            task.status == TransferStatus.queued,
      )
      .length;

  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_handleManagerChanged);
  }

  @override
  void didUpdateWidget(covariant TransferRunningCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.manager, widget.manager)) return;
    oldWidget.manager.removeListener(_handleManagerChanged);
    widget.manager.addListener(_handleManagerChanged);
    _running = _count(widget.manager);
  }

  void _handleManagerChanged() {
    final next = _count(widget.manager);
    if (!mounted || next == _running) return;
    setState(() => _running = next);
  }

  @override
  void dispose() {
    widget.manager.removeListener(_handleManagerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _running);
}
