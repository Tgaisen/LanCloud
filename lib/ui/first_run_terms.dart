import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter/services.dart';

import '../core/agreements.dart';
import '../l10n/l10n.dart';
import 'legal_dialog.dart';
import 'login_page.dart';
import 'system_ui.dart';

/// 首次启动（或条款更新后）的同意页：同意后才能进入主界面。
class FirstRunTerms extends StatelessWidget {
  const FirstRunTerms({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 沉浸式系统栏：欢迎页在第一帧就显示，导航栏没有主界面那一层
      // 兜底，这里要自己给全（透明导航栏 + 图标明暗随主题）
      value: systemUiOverlayStyleFor(theme.brightness),
      child: Scaffold(
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
                      'assets/images/logo/app_icon.png',
                      width: 72,
                      height: 72,
                      excludeFromSemantics: true,
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
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => _openLegal(context, LegalDoc.terms),
                      style: TextButton.styleFrom(
                        backgroundColor: scheme.surfaceContainerLow,
                        foregroundColor: scheme.onSurfaceVariant,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: Text(l10n.aboutTerms),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => _openLegal(context, LegalDoc.privacy),
                      style: TextButton.styleFrom(
                        backgroundColor: scheme.surfaceContainerLow,
                        foregroundColor: scheme.onSurfaceVariant,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: Text(l10n.aboutPrivacy),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    await Agreements.accept();
                    if (!context.mounted) return;
                    // 同意后弹出登录弹窗；关掉弹窗则留在欢迎页
                    final ok = await showLoginSheet(context);
                    if (!ok) return;
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
      ),
    );
  }

  void _openLegal(BuildContext context, LegalDoc doc) {
    showLegalDialog(context, doc);
  }
}
