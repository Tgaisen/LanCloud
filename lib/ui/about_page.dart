import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/app_info.dart';
import '../core/device_info.dart';
import '../core/external_link.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'legal_dialog.dart';
import 'licenses_page.dart';

/// 关于页：版本、协议与隐私、开源许可、项目主页、提交 Issue / 相关信息。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
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
        title: Text(l10n.about),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          // 整块布局：避免懒布局估算导致滚动条滑块抖动（见 SliverColumn）
          sliver: SliverToBoxAdapter(child: AboutContent()),
        ),
      ],
    );
  }
}

/// 关于页正文：版本块 + 各分组列表。
/// 独立页（小屏 push）与「我的」右侧详情窗格共用同一份内容。
class AboutContent extends StatelessWidget {
  const AboutContent({super.key, this.onOpenLicenses});

  /// 「开源许可」的点击行为；为空时按独立页 push 许可页。
  final VoidCallback? onOpenLicenses;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/images/logo/app_icon.png',
                  width: 72,
                  height: 72,
                  excludeFromSemantics: true,
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.appName, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                l10n.aboutVersion(appVersion, appBuild),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // 构建信息已搬到「我的 - 更新」页（版本信息条目），这里不再单放
        SegmentedList(
          children: [
            ListTile(
              leading: const Icon(Icons.contract),
              title: Text(l10n.aboutTerms),
              onTap: () => showLegalDialog(context, LegalDoc.terms),
            ),
            ListTile(
              leading: const Icon(Icons.shield_person),
              title: Text(l10n.aboutPrivacy),
              onTap: () => showLegalDialog(context, LegalDoc.privacy),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedList(
          children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(l10n.aboutLicenses),
              trailing: const Icon(Icons.chevron_right),
              // 用应用自己的许可页：顶栏风格一致，也没有
              // Flutter 默认那块「应用名 + 版本 + powered by Flutter」页头
              onTap:
                  onOpenLicenses ??
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LicensesPage(),
                    ),
                  ),
            ),
            ListTile(
              leading: const Icon(Icons.public),
              title: Text(l10n.aboutProjectHome),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => openExternalUrl(Uri.parse(projectUrl)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 反馈相关：提交 Issue + 一键复制设备 / 构建信息
        SegmentedList(
          children: [
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: Text(l10n.aboutSubmitIssue),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => openExternalUrl(Uri.parse('$projectUrl/issues')),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.relatedInfo),
              onTap: () => showRelatedInfoDialog(context),
            ),
          ],
        ),
      ],
    );
  }
}

/// 构建信息弹窗：构建时间与提交号（打包时注入，原版 MD3 弹窗样式）。
Future<void> showBuildInfoDialog(BuildContext context) {
  final l10n = context.l10n;
  final hasCommit = gitCommit.isNotEmpty;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.aboutBuildInfo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BuildInfoRow(label: l10n.buildTime, value: buildTime),
          const SizedBox(height: 12),
          _BuildInfoRow(label: l10n.commitHash, value: gitCommit),
        ],
      ),
      actions: [
        if (hasCommit)
          TextButton(
            onPressed: () =>
                openExternalUrl(Uri.parse('$projectUrl/commit/$gitCommit')),
            child: Text(l10n.details),
          ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.confirm),
        ),
      ],
    ),
  );
}

class _BuildInfoRow extends StatelessWidget {
  const _BuildInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value.isEmpty ? '—' : value,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// 反馈用的「相关信息」弹窗：应用构建信息 + 设备 / 系统信息，一键复制。
///
/// **本应用的设计决定（非 M3 规范）**：文本刻意用英文标签（issue 里开发者
/// 和用户都能看懂），缺项显示「—」；复制内容与屏幕上的完全一致。
Future<void> showRelatedInfoDialog(BuildContext context) async {
  final l10n = context.l10n;
  final info = await DeviceInfo.load();
  if (!context.mounted) return;
  final text = _relatedInfoText(info);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // 行数较多：标题与按钮固定、正文滚动（M3）
      scrollable: true,
      title: Text(l10n.relatedInfo),
      content: SelectableText(
        text,
        style: Theme.of(dialogContext).textTheme.bodyMedium
            ?.copyWith(height: 1.6),
      ),
      actions: [
        TextButton(
          // 复制后弹轻提示，弹窗保持打开：核对完再点确定
          onPressed: () => copyText(dialogContext, text, asToast: true),
          child: Text(l10n.copy),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.confirm),
        ),
      ],
    ),
  );
}

String _relatedInfoText(DeviceInfo info) {
  String value(String text) => text.trim().isEmpty ? '—' : text.trim();
  final preRelease = appVersion.contains('-');
  return [
    'App version: $appVersion',
    'Build: $appBuild (${preRelease ? 'pre-release' : 'release'})',
    // Android 上系统里的实际安装码（拆分包按 ABI 加过偏移），
    // 反馈安装 / 升级问题时以这个为准
    if (info.versionCode != null) 'Version code: ${info.versionCode}',
    'Build time: ${value(buildTime)}',
    'Commit: ${value(gitCommit)}',
    'Device: ${value(info.device)}',
    'System: ${value(info.system)}',
    if (info.systemBuild.trim().isNotEmpty)
      'System build: ${info.systemBuild.trim()}',
    'Architecture: ${value(info.architectures)}',
  ].join('\n');
}
