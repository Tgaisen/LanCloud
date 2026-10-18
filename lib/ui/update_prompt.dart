import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import 'update_page.dart';

/// 全局更新提醒：自动检测到新版本时，在当前页面主动弹一次更新弹窗。
///
/// 挂在「条款已同意」之后的 [RootShell] 外层（仍在 Navigator 之下）：
/// - 首次启动还没同意条款时不打扰；
/// - 同一个版本每次会话只提醒一次，用户点「取消」后不再反复弹；
/// - 弹窗复用更新页的 [showUpdateDialog]，正文、详情链接与下载行为完全一致。
class UpdatePromptHost extends StatefulWidget {
  const UpdatePromptHost({super.key, required this.child});

  final Widget child;

  @override
  State<UpdatePromptHost> createState() => _UpdatePromptHostState();
}

class _UpdatePromptHostState extends State<UpdatePromptHost> {
  AppController? _app;

  /// 本次会话已经提醒过的版本，避免重复弹窗。
  String? _promptedVersion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppController>();
    if (identical(app, _app)) return;
    _app?.updates.removeListener(_onUpdates);
    _app = app;
    app.updates.addListener(_onUpdates);
    // 自动检测可能在首帧之前就完成：进树后补查一次
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt());
  }

  @override
  void dispose() {
    _app?.updates.removeListener(_onUpdates);
    super.dispose();
  }

  void _onUpdates() => _maybePrompt();

  void _maybePrompt() {
    final app = _app;
    if (app == null || !mounted) return;
    final version = app.updates.autoUpdateNotice;
    if (version == null || version == _promptedVersion) return;
    _promptedVersion = version;
    // 消费掉标记：取消弹窗后本次会话不再重复提醒
    app.updates.clearAutoUpdateNotice();
    // 通知可能发生在 build 期间：等这一帧结束后再开弹窗
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showUpdateDialog(context, app.updates);
    });
    // addPostFrameCallback 自己不调度帧：界面空闲时要主动排一帧，
    // 否则弹窗会一直等到下一次有动画 / 交互才出现
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
