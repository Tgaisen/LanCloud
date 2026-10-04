import 'package:flutter/material.dart' hide Icons;
import 'package:url_launcher/url_launcher.dart';

import '../core/app_info.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'legal_dialog.dart';

/// 关于页：版本、协议与隐私、开源许可、项目主页与免责声明。
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
                ],
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
