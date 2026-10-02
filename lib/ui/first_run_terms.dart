import 'package:flutter/material.dart' hide Icons;
import 'package:flutter/services.dart';

import '../core/agreements.dart';
import '../l10n/l10n.dart';
import 'legal_dialog.dart';

/// 首次启动（或条款更新后）的同意页：同意后才能进入主界面。
class FirstRunTerms extends StatelessWidget {
  const FirstRunTerms({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 72,
                    height: 72,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.firstRunWelcome,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.firstRunMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.outline, height: 1.6),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => _openLegal(context, LegalDoc.terms),
                    child: Text(l10n.aboutTerms),
                  ),
                  TextButton(
                    onPressed: () => _openLegal(context, LegalDoc.privacy),
                    child: Text(l10n.aboutPrivacy),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  await Agreements.accept();
                  onAccepted();
                },
                child: Text(l10n.agreeAndContinue),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => SystemNavigator.pop(),
                child: Text(l10n.disagreeAndExit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openLegal(BuildContext context, LegalDoc doc) {
    showLegalDialog(context, doc);
  }
}
