import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/api/lanzou_client.dart';
import '../core/backup/backup_sections.dart';
import '../core/backup/backup_service.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';

/// 备份副本摘要：时间、内容、账号与登录态提示。
///
/// 恢复向导和设置页的「确认恢复」弹窗共用这份结构，避免两处信息层级漂移。
class BackupPreviewDetails extends StatelessWidget {
  const BackupPreviewDetails({
    super.key,
    required this.preview,
    this.fileName,
    this.candidate,
    this.loginStatus,
    this.infoText,
    this.onRecheckLogin,
    this.listMargin = const EdgeInsets.all(4),
    this.plainText = false,
    this.now,
  });

  final BackupPreview preview;

  /// 文件名仅在恢复向导需要辨认来源时传入；弹窗里不重复显示。
  final String? fileName;
  final BackupAccountPreview? candidate;
  final LoginStateValidation? loginStatus;

  /// 未执行在线验证时显示的摘要提示。
  final String? infoText;
  final VoidCallback? onRecheckLogin;
  final EdgeInsetsGeometry listMargin;

  /// 弹窗里使用类似「构建信息」的标签 / 值纯文本布局。
  final bool plainText;

  /// 测试注入的当前时间；正式运行时使用系统当前时间。
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final statusText = loginStatus == null
        ? infoText
        : switch (loginStatus!) {
            LoginStateValidation.valid => l10n.restoreLoginReady,
            LoginStateValidation.invalid => l10n.restoreLoginInvalid,
            LoginStateValidation.networkError => l10n.restoreLoginNetwork,
            LoginStateValidation.serverError => l10n.restoreLoginServer,
          };
    final statusIcon = loginStatus == null
        ? Icons.info_outline
        : switch (loginStatus!) {
            LoginStateValidation.valid => Icons.check_circle,
            LoginStateValidation.invalid => Icons.error_outline,
            LoginStateValidation.networkError => Icons.wifi_off,
            LoginStateValidation.serverError => Icons.cloud_off,
          };
    final details = plainText ? _buildPlainText(context) : _buildList(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        details,
        if (statusText != null) ...[
          const SizedBox(height: 16),
          InfoHintCard(
            icon: statusIcon,
            text: statusText,
            margin: plainText
                ? EdgeInsets.zero
                : EdgeInsets.only(left: 4, right: 4),
            trailing:
                loginStatus != null &&
                    loginStatus != LoginStateValidation.valid &&
                    candidate != null &&
                    onRecheckLogin != null
                ? TextButton(
                    onPressed: onRecheckLogin,
                    child: Text(l10n.restoreCheckAgain),
                  )
                : null,
          ),
        ],
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    final l10n = context.l10n;
    final createdAt = preview.createdAt;
    return SegmentedList(
      margin: listMargin,
      children: [
        if (createdAt != null)
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(
              l10n.restoreCreatedAt(
                formatRelativeTime(l10n, createdAt, now: now),
              ),
            ),
            subtitle: fileName == null ? null : Text(fileName!),
          ),
        ListTile(
          leading: const Icon(Icons.checklist),
          title: Text(l10n.restoreIncludedContent),
          subtitle: Text(_sectionSummary(l10n, preview.sections)),
        ),
        if (preview.accounts.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: Text(l10n.restoreAccountCount(preview.accounts.length)),
            subtitle: candidate == null
                ? null
                : Text(l10n.restoreUsingAccount(candidate!.displayName)),
          ),
      ],
    );
  }

  Widget _buildPlainText(BuildContext context) {
    final l10n = context.l10n;
    final createdAt = preview.createdAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PreviewTextRow(
          label: l10n.restoreCreatedAtLabel,
          value: createdAt == null
              ? '—'
              : formatRelativeTime(l10n, createdAt, now: now),
        ),
        const SizedBox(height: 12),
        _PreviewTextRow(
          label: l10n.restoreIncludedContentLabel,
          value: _sectionSummary(l10n, preview.sections),
        ),
        const SizedBox(height: 12),
        _PreviewTextRow(
          label: l10n.restoreAccountLabel,
          value: l10n.restoreAccountCountValue(preview.accounts.length),
          detail: candidate == null
              ? null
              : l10n.restoreUsingAccount(candidate!.displayName),
        ),
      ],
    );
  }

  String _sectionSummary(AppLocalizations l10n, Set<BackupSection> sections) {
    if (sections.isEmpty) return l10n.backupSectionEmpty;
    return [
      for (final section in BackupSection.values)
        if (sections.contains(section))
          switch (section) {
            BackupSection.settings => l10n.backupSectionSettings,
            BackupSection.favorites => l10n.backupSectionFavorites,
            BackupSection.quick => l10n.backupSectionQuick,
            BackupSection.recents => l10n.backupSectionRecents,
            BackupSection.cookies => l10n.backupSectionCookies,
            BackupSection.webdavAccount => l10n.webdavAccount,
          },
    ].join(' · ');
  }
}

class _PreviewTextRow extends StatelessWidget {
  const _PreviewTextRow({
    required this.label,
    required this.value,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(value, style: theme.textTheme.bodyMedium),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(
            detail!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
