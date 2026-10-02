import 'package:flutter/material.dart' hide Icons;

import '../core/cookie_auth.dart';
import '../core/data/account_store.dart';
import '../core/system_share.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';

/// 「显示 Cookie」流程：风险提示 → 生物识别 / 锁屏验证 → 展示与导出。
Future<void> showCookieFlow(BuildContext context, Account account) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.warning_outlined),
      title: Text(l10n.cookieRiskTitle),
      content: Text(l10n.cookieRiskMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.continueLabel),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final result = await CookieAuth.instance.verify(l10n.cookieAuthReason);
  if (!context.mounted) return;
  switch (result) {
    case CookieAuthResult.ok:
      await showAppSheet<void>(context, child: CookieSheet(account: account));
    case CookieAuthResult.canceled:
      break;
    case CookieAuthResult.unavailable:
      await _showTip(context, Icons.lock_outline, l10n.cookieAuthUnavailable);
    case CookieAuthResult.failed:
      await _showTip(context, Icons.error_outline, l10n.cookieAuthFailed);
  }
}

Future<void> _showTip(BuildContext context, IconData icon, String message) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(icon),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    ),
  );
}

/// Cookie 展示弹窗：等宽字体、可选中，提供复制与导出。
class CookieSheet extends StatelessWidget {
  const CookieSheet({super.key, required this.account});

  final Account account;

  Future<void> _export(BuildContext context) async {
    final ok = await SystemShare.shareText(
      account.cookie,
      subject: '${context.l10n.appName} · UID ${account.uid}',
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.cookieExportFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.key_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.cookieSheetTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.uidLabel(account.uid),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  account.cookie,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => copyText(context, account.cookie),
                  icon: const Icon(Icons.copy),
                  label: Text(l10n.copy),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _export(context),
                  icon: const Icon(Icons.share_outlined),
                  label: Text(l10n.cookieExport),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
