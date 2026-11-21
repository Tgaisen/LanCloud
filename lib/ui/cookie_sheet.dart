import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cookie_auth.dart';
import '../core/data/account_store.dart';
import '../core/platform_capabilities.dart';
import '../core/system_share.dart';
import '../l10n/l10n.dart';
import 'common.dart';

/// 「显示 Cookie」流程：风险提示 → 生物识别 / 锁屏验证 → 展示与导出。
Future<void> showCookieFlow(BuildContext context, Account account) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
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
  final result = await CookieAuth.instance.verify(
    l10n.cookieAuthReason,
    messages: authMessagesFor(l10n),
  );
  if (!context.mounted) return;
  switch (result) {
    case CookieAuthResult.ok:
      await showCookieDialog(context, account);
    case CookieAuthResult.canceled:
      break;
    case CookieAuthResult.unavailable:
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.cookieAuthUnavailable)));
    case CookieAuthResult.failed:
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.cookieAuthFailed)));
  }
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
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
        // 原版风格（同 WebDAV 配置弹窗）：消极 / 中立无背景，积极用填充按钮
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.close),
        ),
        TextButton(
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
  final l10n = context.l10n;
  final capabilities = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(platformCapabilitiesProvider);
  final gateway = systemShareGatewayFor(capabilities);
  final ok = await gateway.shareText(
    account.cookie,
    subject: '${l10n.currentAppDisplayName} · UID ${account.uid}',
  );
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.cookieExportFailed)));
    return;
  }
  // 只有实际选中桌面剪贴板降级时才提示，不再根据平台形态另行猜测。
  if (gateway is DesktopSystemShareGateway) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.copiedToClipboard)));
  }
}
