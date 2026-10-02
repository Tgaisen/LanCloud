import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'scroll_tint.dart';

enum LegalDoc { terms, privacy }

/// 用户协议 / 隐私政策全文页。
class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final l10n = context.l10n;
    final title = doc == LegalDoc.terms ? l10n.aboutTerms : l10n.aboutPrivacy;
    final body =
        doc == LegalDoc.terms ? l10n.termsBody : l10n.privacyBody;
    return ScrollTint(
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Scaffold(
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
                  title: Text(title),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  sliver: SliverToBoxAdapter(
                    child: SelectableText(
                      body,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.7),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
