import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/update/update_service.dart';
import 'update_page.dart';

/// 全局更新提醒：自动检测到新版本时，在当前页面主动弹一次更新弹窗。
///
/// 挂在「条款已同意」之后的 [RootShell] 外层（仍在 Navigator 之下）：
/// - 首次启动还没同意条款时不打扰；
/// - 同一个版本每次会话只提醒一次，用户点「取消」后不再反复弹；
/// - 弹窗复用更新页的 [showUpdateDialog]，正文、详情链接与下载行为完全一致。
class UpdatePromptHost extends ConsumerStatefulWidget {
  const UpdatePromptHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdatePromptHost> createState() => _UpdatePromptHostState();
}

class _UpdatePromptHostState extends ConsumerState<UpdatePromptHost> {
  /// 本次会话已经提醒过的版本，避免重复弹窗。
  String? _promptedVersion;
  bool _checkedInitialNotice = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      updateServiceProvider.select((state) => state.autoUpdateNotice),
      (_, version) => _schedulePrompt(version),
    );
    // 自动检测可能在首帧之前就完成：进树后补查一次。
    if (!_checkedInitialNotice) {
      _checkedInitialNotice = true;
      _schedulePrompt(ref.read(updateServiceProvider).autoUpdateNotice);
    }
    return widget.child;
  }

  void _schedulePrompt(String? version) {
    if (version == null || version == _promptedVersion) return;
    _promptedVersion = version;
    // 通知可能发生在 build 期间：等这一帧结束后再消费标记并开弹窗。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(updateServiceProvider);
      if (state.autoUpdateNotice != version) return;
      final release = state.cachedRelease;
      ref.read(updateServiceProvider.notifier).clearAutoUpdateNotice();
      if (release == null) return;
      showUpdateDialog(
        context,
        release: release,
        downloadUrl: ref.read(updateServiceProvider.notifier).downloadUrl,
      );
    });
    // addPostFrameCallback 自己不调度帧：界面空闲时要主动排一帧，
    // 否则弹窗会一直等到下一次有动画 / 交互才出现。
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}
