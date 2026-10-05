import 'package:flutter/material.dart' hide Icons;

import '../l10n/l10n.dart';

enum LegalDoc { terms, privacy }

/// 用户协议 / 隐私政策：文本弹窗（不单独开页面）。
Future<void> showLegalDialog(BuildContext context, LegalDoc doc) {
  final l10n = context.l10n;
  final theme = Theme.of(context);
  final title = doc == LegalDoc.terms ? l10n.aboutTerms : l10n.aboutPrivacy;
  // 免责声明并入用户协议
  final body = doc == LegalDoc.terms
      ? '${l10n.termsBody}\n\n${l10n.termsDisclaimer}'
      : l10n.privacyBody;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // 让标题 + 正文整体可滚动，长文本在弹窗内可以滑到底
      scrollable: true,
      title: Text(title),
      // 用普通 Text：SelectableText 会吃掉竖向拖动手势，导致弹窗滚不动
      content: Text(
        body,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.close),
        ),
      ],
    ),
  );
}
