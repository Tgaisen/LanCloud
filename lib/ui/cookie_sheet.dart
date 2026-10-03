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
      await showCookieDialog(context, account);
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

/// Cookie 展示弹窗（MD3E 默认风格）：标题 + UID + 可滑动的等宽内容 + 操作按钮。
/// Cookie 很长，内容区单独滚动，小屏也不会显示不全。
Future<void> showCookieDialog(BuildContext context, Account account) {
  final l10n = context.l10n;
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(l10n.cookieSheetTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  // 普通 Text：SelectableText 会吃掉竖向拖动手势导致滚不动
                  child: Text(
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
          ],
        ),
      ),
      actions: [
        // 消极 / 中立 / 积极：关闭、复制、导出
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.close),
        ),
        FilledButton.tonal(
          onPressed: () => copyText(context, account.cookie),
          child: Text(l10n.copy),
        ),
        FilledButton(
          onPressed: () => _exportCookie(context, account),
          child: Text(l10n.cookieExport),
        ),
      ],
    ),
  );
}

Future<void> _exportCookie(BuildContext context, Account account) async {
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
