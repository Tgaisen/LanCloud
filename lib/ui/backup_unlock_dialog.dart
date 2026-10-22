import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/backup/backup_service.dart';
import '../core/backup/webdav_client.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'm3e.dart';

/// 解锁后的明文，以及本次实际使用、可用于缓存到 WebDAV 配置的口令。
class UnlockedBackup {
  const UnlockedBackup({required this.content, required this.passphrase});

  final String content;
  final String passphrase;
}

/// 读取到加密备份时要求输入口令。
///
/// 解密失败时弹窗保持打开并原地显示通用错误，用户可以重新输入。
Future<UnlockedBackup?> showBackupUnlockDialog(
  BuildContext context, {
  required String content,
  String initialPassphrase = '',
}) {
  if (!BackupService.isEncrypted(content)) {
    return Future.value(UnlockedBackup(content: content, passphrase: ''));
  }
  return showDialog<UnlockedBackup>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BackupUnlockDialog(
      content: content,
      initialPassphrase: initialPassphrase,
    ),
  );
}

class _BackupUnlockDialog extends StatefulWidget {
  const _BackupUnlockDialog({
    required this.content,
    required this.initialPassphrase,
  });

  final String content;
  final String initialPassphrase;

  @override
  State<_BackupUnlockDialog> createState() => _BackupUnlockDialogState();
}

class _BackupUnlockDialogState extends State<_BackupUnlockDialog> {
  late final TextEditingController _passphrase = TextEditingController(
    text: widget.initialPassphrase,
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy) return;
    final l10n = context.l10n;
    if (_passphrase.text.trim().isEmpty) {
      setState(() => _error = l10n.backupPassphraseRequired);
      return;
    }
    if (_passphrase.text.length < 8) {
      setState(() => _error = l10n.backupPassphraseTooShort);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plaintext = await BackupService.decryptIfNeeded(
        widget.content,
        passphrase: _passphrase.text,
      );
      if (mounted) {
        Navigator.of(
          context,
        ).pop(UnlockedBackup(content: plaintext, passphrase: _passphrase.text));
      }
    } on BackupException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.backupPassphraseWrong;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.backupPassphraseWrong;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return formDialogPan(
      context,
      child: AlertDialog(
        title: Text(l10n.backupUnlockTitle),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.backupUnlockMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('backup-unlock-passphrase'),
                controller: _passphrase,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _unlock(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: errorState(
                  context,
                  InputDecoration(labelText: l10n.backupPassphrase),
                  _error,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: _busy ? null : _unlock,
            child: _busy
                ? const M3eLoadingIndicator(size: 18)
                : Text(l10n.backupUnlockAction),
          ),
        ],
      ),
    );
  }
}
