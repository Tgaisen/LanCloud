import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/app_info.dart';
import '../core/external_link.dart';
import '../core/update/changelog.dart';
import '../core/update/update_service.dart';
import '../l10n/l10n.dart';
import 'about_page.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';
import 'reduce_motion.dart';

/// 更新页：更新状态卡片 + 版本信息 / 更新日志 + 更新通道 / 自动检查更新。
class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  /// 页面列表；传给 TopBarOverlayScaffold 后点顶栏空白即可回到顶部。
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TopBarOverlayScaffold(
      controller: _scroll,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: const AppBarBackButton(),
        title: Text(l10n.update),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          // 整块布局：避免懒布局估算导致滚动条滑块抖动（见 SliverColumn）
          sliver: SliverToBoxAdapter(child: UpdateContent()),
        ),
      ],
    );
  }
}

/// 更新页正文：状态卡片 + 两个列表组。
/// 独立页（小屏 push）与「我的」右侧详情窗格共用同一份内容。
class UpdateContent extends StatelessWidget {
  const UpdateContent({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final l10n = context.l10n;
    final service = app.updates;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UpdateStatusPanel(service: service),
          const SizedBox(height: 8),
          SegmentedList(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.updateVersionInfo),
                subtitle: Text(l10n.aboutVersion(appVersion, appBuild)),
                // 与关于页的「构建信息」是同一个弹窗
                onTap: () => showBuildInfoDialog(context),
              ),
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(l10n.updateChangelog),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => openExternalUrl(Uri.parse('$projectUrl/releases')),
              ),
            ],
          ),
          // 列表组 2 只在支持检测更新的平台显示：iOS 没有安装包产物，
          // 通道与自动检查对它没有意义（状态卡片里另有说明）。
          if (service.supported) ...[
            const SizedBox(height: 8),
            SegmentedList(
              children: [
                ListTile(
                  leading: const Icon(Icons.build_outlined),
                  title: Text(l10n.updateChannel),
                  subtitle: Text(
                    _channelName(l10n, app.settings.updateChannel),
                  ),
                  onTap: () => _pickChannel(context, app),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.cached_outlined),
                  title: Text(l10n.updateAutoCheck),
                  value: app.settings.updateAutoCheck,
                  onChanged: (value) => app.setUpdateAutoCheck(value),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _channelName(AppLocalizations l10n, String channel) =>
    channel == 'beta' ? l10n.updateChannelBeta : l10n.updateChannelStable;

/// MD3E 单选弹窗（与设置页的选择弹窗同一套样式）：正式版 / 测试版。
Future<void> _pickChannel(BuildContext context, AppController app) async {
  final l10n = context.l10n;
  final current = app.settings.updateChannel;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.updateChannel),
      // M3 对话框内容边距 24dp；列表组自带 0 外边距，组沿正好落在 24dp 上
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DialogListGroup(
              children: [
                for (final (value, label) in [
                  ('stable', l10n.updateChannelStable),
                  ('beta', l10n.updateChannelBeta),
                ])
                  M3ePickTile(
                    label: label,
                    selected: current == value,
                    singleSelect: true,
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      app.setUpdateChannel(value);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 更新状态区：图标框 / 状态文本 / 动作按钮，垂直居中排列。
///
/// **参考 M3 规范**：状态标题是这一段的主信息，用强调排版（M3E：强调排版
/// 标记层级，不是整份替换）；动作都算主操作，统一用 filled 按钮；内容块
/// 不强制套容器，靠留白与下方列表分组。
/// **本应用的设计决定（非 M3 规范）**：「检测到新版本」用三级容器色把注意力
/// 引到这个状态上，失败用错误容器色；图标框 / 状态文本 / 动作按钮
/// **垂直居中**排列——文本独占一整行宽度，英文等更长的文案不会和按钮挤在
/// 一起；不套卡片容器，直接坐在页面背景上（与关于页的版本块同一处理）。
class _UpdateStatusPanel extends StatelessWidget {
  const _UpdateStatusPanel({required this.service});

  final UpdateService service;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = service.status;
    final unsupported = !service.supported;

    final String title;
    final String? subtitle;
    final IconData icon;
    if (unsupported) {
      title = l10n.updateUnsupported;
      subtitle = null;
      icon = Icons.update;
    } else {
      title = switch (status) {
        UpdateStatus.checking => l10n.updateCheckingTitle,
        UpdateStatus.upToDate => l10n.updateUpToDateTitle,
        UpdateStatus.available => l10n.updateFoundTitle,
        UpdateStatus.failed => l10n.updateFailed,
        UpdateStatus.idle => l10n.updateNotChecked,
      };
      icon = switch (status) {
        UpdateStatus.upToDate => Icons.check_circle,
        UpdateStatus.available => Icons.system_update,
        UpdateStatus.failed => Icons.error_outline,
        UpdateStatus.checking || UpdateStatus.idle => Icons.update,
      };
      // 副标题只在有信息量的状态显示（检测中由标题与圆环表达）；
      // 「未检测更新」时如果从未检测过，连「上次检测于」都没有
      subtitle = switch (status) {
        UpdateStatus.checking => null,
        UpdateStatus.available => service.remoteVersion,
        UpdateStatus.failed => l10n.updateReachFailed(
          service.failureCode ?? 'UNKNOWN',
        ),
        UpdateStatus.upToDate || UpdateStatus.idle =>
          service.lastCheckAt == null
              ? null
              : l10n.updateLastCheckAt(
                  formatRelativeTime(l10n, service.lastCheckAt!),
                ),
      };
    }

    final (Color boxColor, Color boxForeground) = unsupported
        ? (scheme.surfaceContainerHighest, scheme.onSurfaceVariant)
        : switch (status) {
            UpdateStatus.available => (
              scheme.tertiaryContainer,
              scheme.onTertiaryContainer,
            ),
            UpdateStatus.failed => (
              scheme.errorContainer,
              scheme.onErrorContainer,
            ),
            _ => (scheme.secondaryContainer, scheme.onSecondaryContainer),
          };

    final Widget? button;
    if (unsupported) {
      button = null;
    } else if (status == UpdateStatus.checking) {
      button = FilledButton(
        onPressed: null,
        child: Text(l10n.updateCheckingShort),
      );
    } else {
      button = FilledButton(
        // 比默认（40dp）高一档，和放大后的图标框 / 文本成套
        style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
        onPressed: status == UpdateStatus.available
            ? () => showUpdateDialog(context, service)
            : () => _checkManually(context, service),
        child: Text(switch (status) {
          UpdateStatus.available => l10n.updateAction,
          UpdateStatus.idle => l10n.updateCheck,
          _ => l10n.updateRecheck,
        }),
      );
    }

    return Padding(
      // 不套卡片：直接坐在页面背景上，左右留白只影响长文案的换行宽度，
      // 上下与关于页的版本块保持同一档（16dp）
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusIconBox(
            color: boxColor,
            foreground: boxForeground,
            child: status == UpdateStatus.checking
                // 检测中：圆环立即替换图标（M3：内置在组件里的等待用
                // 加载指示器；少动效时它是静态形态）
                ? M3eLoadingIndicator(
                    size: 36,
                    color: boxForeground,
                    semanticsLabel: l10n.updateCheckingTitle,
                  )
                : Icon(icon, size: 36, color: boxForeground),
          ),
          const SizedBox(height: 16),
          // 状态文本变化时让读屏播报（与「我的」页标题同一机制）
          Semantics(
            liveRegion: true,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.m3eEmphasizedTheme.titleLarge,
            ),
          ),
          // 副标题槽：出现 / 消失时高度与透明度一起做动画，按钮与整段
          // 高度跟着它逐帧流动（检测中隐藏副标题时不会瞬间跳一下）
          _SubtitleSlot(subtitle: subtitle),
          if (button != null) ...[const SizedBox(height: 20), button],
        ],
      ),
    );
  }

  /// 手动检测：失败时补一条提示条——有效期内失败并不改变卡片状态
  ///（按需求「检测更新失败」只在失效后显示），光看卡片会以为没反应。
  Future<void> _checkManually(
    BuildContext context,
    UpdateService service,
  ) async {
    final l10n = context.l10n;
    final ok = await service.check();
    if (!ok && context.mounted) {
      showAppToast(context, l10n.updateFailed);
    }
  }
}

/// 卡片里的副标题槽：内容出现 / 消失时「高度 + 透明度」一起动画。
///
/// 检测中会隐藏副标题，直接把子树换掉会让下面的按钮和整段高度瞬间上移；
/// 这里让槽位常驻：文字淡出、高度收到 0，外层的 Column / 卡片随之平滑地
/// 重新布局（少动效时直接到位，不做动画）。
class _SubtitleSlot extends StatefulWidget {
  const _SubtitleSlot({required this.subtitle});

  /// 当前要显示的副标题；null = 收起。
  final String? subtitle;

  @override
  State<_SubtitleSlot> createState() => _SubtitleSlotState();
}

class _SubtitleSlotState extends State<_SubtitleSlot>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 220);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
    value: widget.subtitle == null ? 0 : 1,
  );

  /// 正在显示（或正在淡出）的文案：收起动画期间保留上一份，
  /// 这样文字能跟着动画一起淡出，而不是先消失、留一块空白慢慢收。
  String? _shown;

  @override
  void initState() {
    super.initState();
    _shown = widget.subtitle;
    _controller.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(_SubtitleSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.subtitle == oldWidget.subtitle) return;
    if (widget.subtitle != null) {
      setState(() => _shown = widget.subtitle);
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  /// 收起动画走完：把旧文案从树里拿掉（零高度 + 全透明仍占着一个节点）。
  void _onStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.dismissed && _shown != null) {
      setState(() => _shown = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 少动效：时长归零，出现 / 收起都直接到位
    _controller.duration = reduceMotionOf(context) ? Duration.zero : _duration;
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return SizeTransition(
      sizeFactor: _controller,
      // 沿高度收起 / 展开时贴着顶部（轴向上 -1 的位置）
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _controller,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            shown,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 卡片左侧的图标框：MD3E 装饰形状外框（4 边饼干）+ 图标 / 加载圆环。
///
/// **参考 M3 规范**：形状取自 M3 形状库的 `Cookie4Sided`；容器色用与状态
/// 配对的容器角色、内容用配对的 on 角色；加载指示器放在别的组件里时，
/// 颜色要与该组件的图标一致（M3 的对比度要求），所以圆环用图标色。
/// **本应用的设计决定（非 M3 规范）**：外框 64dp / 内容 36dp（卡片改成
/// 垂直排列后图标框承担视觉焦点，跟着放大一档）。
class _StatusIconBox extends StatelessWidget {
  const _StatusIconBox({
    required this.child,
    required this.color,
    required this.foreground,
  });

  final Widget child;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: M3EClipper(Shapes.c4SidedCookie),
      child: Container(
        width: 64,
        height: 64,
        color: color,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// 更新弹窗：标题「检测到新版本 {版本}」、正文为更新日志、动作「取消 / 更新」。
///
/// **参考 M3 规范**：基本弹窗最多两个动作（详情这类第三动作不推荐），所以
/// 「详情」是正文末尾的内联链接（M3：链接用 primary 色 + 下划线）；
/// 长正文用可滚动内容，标题与按钮固定。
///
/// 更新页的「更新」按钮与全局自动提醒（update_prompt.dart 的
/// UpdatePromptHost）共用这个弹窗。
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateService service,
) async {
  final release = service.latestRelease;
  if (release == null) return;
  final l10n = context.l10n;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        scrollable: true,
        title: Text(l10n.updateDialogTitle(release.version)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in changelogLines(release.body))
              line.isEmpty
                  ? const SizedBox(height: 8)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(line, style: theme.textTheme.bodyMedium),
                    ),
            const SizedBox(height: 8),
            _LinkText(
              label: l10n.updateViewDetails,
              onTap: () => openExternalUrl(Uri.parse(release.htmlUrl)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            // 下载地址要按设备 ABI 算（Android 上走一次原生通道），
            // 放在点「更新」之后解析：弹窗立即打开，不卡在异步上
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final url = await service.downloadUrl();
              if (url.isEmpty) return;
              await openExternalUrl(Uri.parse(url));
            },
            child: Text(l10n.updateAction),
          ),
        ],
      );
    },
  );
}

/// 弹窗正文里的内联链接（primary 色 + 下划线）。
class _LinkText extends StatelessWidget {
  const _LinkText({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      link: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: scheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
