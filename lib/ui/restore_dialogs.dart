import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/backup/backup_service.dart';
import '../core/cookie_auth.dart';
import '../l10n/l10n.dart';
import 'backup_unlock_dialog.dart';
import 'backup_preview_view.dart';
import 'common.dart';
import 'm3e.dart';

/// 恢复前确认弹窗的结果：null 表示取消。
class RestoreDecision {
  const RestoreDecision({
    required this.keepFavorites,
    required this.restoreAccounts,
  });

  /// 勾选「保留原收藏夹内容」：增量合并并按 ref 去重。
  final bool keepFavorites;

  /// 是否同时恢复账号和 Cookie。
  final bool restoreAccounts;
}

/// 「保留原收藏夹内容」只在双方都有收藏时才有意义。
bool shouldShowKeepFavorites({
  required BackupPreview preview,
  required int existingFavorites,
}) => preview.hasFavorites && existingFavorites > 0;

/// 恢复前确认弹窗：展示备份副本摘要；仅在备份含收藏夹且本机已有收藏时
/// 显示「保留原收藏夹内容」。
Future<RestoreDecision?> showRestoreConfirmDialog(
  BuildContext context, {
  required BackupPreview preview,
  required bool showKeepFavorites,
  bool restoreAccounts = true,
}) {
  final l10n = context.l10n;
  var keepFavorites = showKeepFavorites;
  return showDialog<RestoreDecision>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(l10n.restoreConfirmTitle),
        // M3 对话框内容边距 24dp；列表组外边距 0，组沿落在 24dp 上
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BackupPreviewDetails(
                preview: preview,
                plainText: true,
                infoText: preview.hasCookies
                    ? l10n.restoreContainsCredentials
                    : l10n.restoreNoCredentials,
                listMargin: EdgeInsets.zero,
              ),
              if (showKeepFavorites) ...[
                const SizedBox(height: 16),
                // 仅当备份含收藏夹且本机已有收藏时提供合并选项。
                DialogListGroup(
                  children: [
                    M3ePickTile(
                      label: l10n.restoreKeepFavorites,
                      subtitle: l10n.restoreKeepFavoritesHint,
                      selected: keepFavorites,
                      onTap: () =>
                          setDialogState(() => keepFavorites = !keepFavorites),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              RestoreDecision(
                keepFavorites: keepFavorites,
                restoreAccounts: restoreAccounts,
              ),
            ),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    ),
  );
}

/// 「确认 → 恢复」流程：从文件恢复、登录前恢复与从云端恢复共用。
///
/// 调用方负责忙碌状态与错误提示。这里不能自己再包一层调用方的 `_run`，
/// 否则可能被忙碌保护重入并吞掉恢复。
Future<bool> confirmAndRestore(
  BuildContext context,
  BackupService service,
  String content, {
  bool restoreAccounts = true,
}) async {
  final unlocked = await showBackupUnlockDialog(context, content: content);
  if (unlocked == null || !context.mounted) return false;
  final plaintext = unlocked.content;
  final preview = BackupService.inspect(plaintext);
  var existingFavorites = 1;
  try {
    existingFavorites = (await service.dependencies.db.favorites()).length;
  } catch (_) {
    // 读取失败时保留合并选项，优先避免覆盖现有收藏。
  }
  if (!context.mounted) return false;
  final decision = await showRestoreConfirmDialog(
    context,
    preview: preview,
    showKeepFavorites: shouldShowKeepFavorites(
      preview: preview,
      existingFavorites: existingFavorites,
    ),
    restoreAccounts: restoreAccounts,
  );
  if (decision == null) return false;
  if (!context.mounted) return false;
  if (decision.restoreAccounts && preview.hasSensitiveData) {
    final l10n = context.l10n;
    final result = await CookieAuth.instance.verify(
      l10n.restoreSensitiveAuthReason,
      messages: authMessagesFor(l10n),
    );
    if (!context.mounted) return false;
    switch (result) {
      case CookieAuthResult.ok:
        break;
      case CookieAuthResult.canceled:
        return false;
      case CookieAuthResult.unavailable:
        showAppToast(context, l10n.cookieAuthUnavailable);
        return false;
      case CookieAuthResult.failed:
        showAppToast(context, l10n.cookieAuthFailed);
        return false;
    }
  }
  await service.restoreFromString(
    plaintext,
    mergeFavorites: decision.keepFavorites,
    restoreAccounts: decision.restoreAccounts,
  );
  return true;
}
