import 'package:flutter/material.dart' hide Icons;
import 'package:url_launcher/url_launcher.dart';

import '../core/app_info.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'legal_dialog.dart';

/// 关于页：版本、协议与隐私、开源许可、项目主页、提交 Issue 与免责声明。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TopBarOverlayScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: const AppBarBackButton(),
        title: Text(l10n.about),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/app_icon.png',
                        width: 72,
                        height: 72,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(l10n.appName, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      l10n.aboutVersion(appVersion, appBuild),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              // 构建信息 / 获取更新：放在最前，和版本号挨着
              SegmentedList(
                children: [
                  ListTile(
                    leading: const Icon(Icons.update),
                    title: Text(l10n.aboutCheckUpdate),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => launchUrl(
                      Uri.parse('$projectUrl/releases'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.build_outlined),
                    title: Text(l10n.aboutBuildInfo),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showBuildInfoDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SegmentedList(
                children: [
                  ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: Text(l10n.aboutTerms),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showLegalDialog(context, LegalDoc.terms),
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(l10n.aboutPrivacy),
                    trailing: const Icon(Icons.chevron_right),
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
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: l10n.appName,
                      applicationVersion:
                          '$appVersion (${appBuild.toString()})',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.public),
                    title: Text(l10n.aboutProjectHome),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => launchUrl(
                      Uri.parse(projectUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(l10n.aboutSubmitIssue),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => launchUrl(
                      Uri.parse('$projectUrl/issues'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
              ),
            ]),
          ),
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
            onPressed: () => launchUrl(
              Uri.parse('$projectUrl/commit/$gitCommit'),
              mode: LaunchMode.externalApplication,
            ),
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
