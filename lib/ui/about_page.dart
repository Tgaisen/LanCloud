import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_controller.dart';
import '../core/app_info.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'legal_page.dart';
import 'scroll_tint.dart';

/// 关于页：版本、协议与隐私、开源许可、项目主页与免责声明。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ScrollTint(
      child: Builder(
        builder: (context) => Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: app.settings.hideTopBar,
                snap: false,
                pinned: !app.settings.hideTopBar,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                backgroundColor: Color.lerp(
                  scheme.surface,
                  scheme.surfaceContainer,
                  ScrollTint.of(context),
                ),
                scrolledUnderElevation: 0,
                title: Text(l10n.about),
              ),
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
                          Text(
                            l10n.appName,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.aboutVersion(appVersion, appBuild),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.outline),
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
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const LegalPage(doc: LegalDoc.terms),
                            ),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: Text(l10n.aboutPrivacy),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const LegalPage(doc: LegalDoc.privacy),
                            ),
                          ),
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
                          subtitle: const Text(projectUrl),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => launchUrl(
                            Uri.parse(projectUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.aboutDisclaimerTitle,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(color: scheme.primary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.aboutDisclaimer,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.outline, height: 1.6),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.aboutCopyright,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.outline),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
