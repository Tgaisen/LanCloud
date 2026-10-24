import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/backup/backup_sections.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';

/// “备份选项”页面结果。
class BackupOptionsResult {
  const BackupOptionsResult({required this.sections, required this.passphrase});

  final Set<BackupSection> sections;

  /// 空串表示明确选择不加密。
  final String passphrase;

  bool get encrypted => passphrase.isNotEmpty;
}

/// 独立页面或大屏详情窗格的“备份选项”打开方式。
typedef BackupOptionsPageOpener = Future<BackupOptionsResult?> Function(
  BuildContext context, {
  required Set<BackupSection> initialSections,
  required String confirmLabel,
  String? title,
  String initialPassphrase,
  Future<bool> Function()? verifySensitive,
});

/// 嵌入式“备份选项”把确认状态同步给宿主顶栏。
class BackupOptionsController extends ChangeNotifier {
  bool _canConfirm = false;
  VoidCallback? _confirm;

  bool get canConfirm => _canConfirm;

  void confirm() => _confirm?.call();

  void _update({required bool canConfirm, required VoidCallback confirm}) {
    final changed = _canConfirm != canConfirm;
    _canConfirm = canConfirm;
    _confirm = confirm;
    if (changed) notifyListeners();
  }

  void _detach(VoidCallback confirm) {
    if (_confirm != confirm) return;
    _confirm = null;
  }
}

const _minimumPassphraseLength = 8;

/// 打开独立“备份选项”页；返回 null 表示用户返回取消。
Future<BackupOptionsResult?> showBackupOptionsPage(
  BuildContext context, {
  required Set<BackupSection> initialSections,
  required String confirmLabel,
  String? title,
  String initialPassphrase = '',
  Future<bool> Function()? verifySensitive,
}) {
  return Navigator.of(context).push<BackupOptionsResult>(
    MaterialPageRoute<BackupOptionsResult>(
      builder: (_) => BackupOptionsPage(
        initialSections: initialSections,
        confirmLabel: confirmLabel,
        title: title,
        initialPassphrase: initialPassphrase,
        verifySensitive: verifySensitive,
      ),
    ),
  );
}

/// 本地导出与 WebDAV 共用的“备份选项”独立页面。
///
/// 页面使用 [TopBarOverlayScaffold]，因此顶栏滚动收起、状态栏与导航栏
/// 沉浸行为和其它应用页面一致，不再由弹窗自行模拟。
class BackupOptionsPage extends StatefulWidget {
  const BackupOptionsPage({
    super.key,
    required this.initialSections,
    required this.confirmLabel,
    this.title,
    this.initialPassphrase = '',
    this.verifySensitive,
    this.embedded = false,
    this.controller,
    this.onResult,
  });

  final Set<BackupSection> initialSections;
  final String confirmLabel;
  final String? title;
  final String initialPassphrase;
  final Future<bool> Function()? verifySensitive;
  final bool embedded;
  final BackupOptionsController? controller;
  final ValueChanged<BackupOptionsResult>? onResult;

  @override
  State<BackupOptionsPage> createState() => _BackupOptionsPageState();
}

class _BackupOptionsPageState extends State<BackupOptionsPage> {
  final ScrollController _scroll = ScrollController();
  late final Set<BackupSection> _sections = {...widget.initialSections};
  late final TextEditingController _passphrase = TextEditingController(
    text: widget.initialPassphrase,
  );
  late bool _encrypt;
  String? _passphraseError;
  late final bool _allowPassphraseReveal;
  bool _showPassphrase = false;

  bool get _hasSensitive => _sections.any((section) => section.sensitive);

  @override
  void initState() {
    super.initState();
    // 已保存的备份密码不再提供明文查看；仅首次设置时允许显示输入内容。
    _allowPassphraseReveal = widget.initialPassphrase.isEmpty;
    _encrypt =
        widget.initialPassphrase.isNotEmpty ||
        widget.initialSections.any((section) => section.sensitive);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncController();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _passphrase.dispose();
    widget.controller?._detach(_submit);
    super.dispose();
  }

  void _syncController() {
    widget.controller?._update(
      canConfirm: _sections.isNotEmpty,
      confirm: _submit,
    );
  }

  Future<void> _toggleSection(BackupSection section) async {
    final adding = !_sections.contains(section);
    if (adding && section.sensitive && widget.verifySensitive != null) {
      final verified = await widget.verifySensitive!();
      if (!verified || !mounted) return;
    }
    setState(() {
      if (adding) {
        _sections.add(section);
        if (section.sensitive) _encrypt = true;
      } else {
        _sections.remove(section);
      }
      _passphraseError = null;
    });
    _syncController();
  }

  void _finish(BackupOptionsResult result) {
    final onResult = widget.onResult;
    if (onResult != null) {
      onResult(result);
      return;
    }
    Navigator.of(context).pop(result);
  }

  void _submit() {
    if (_sections.isEmpty) return;
    if (_encrypt) {
      final passphrase = _passphrase.text;
      if (passphrase.trim().isEmpty) {
        setState(
          () => _passphraseError = context.l10n.backupPassphraseRequired,
        );
        return;
      }
      if (passphrase.length < _minimumPassphraseLength) {
        setState(
          () => _passphraseError = context.l10n.backupPassphraseTooShort,
        );
        return;
      }
      _finish(
        BackupOptionsResult(sections: {..._sections}, passphrase: passphrase),
      );
      return;
    }
    _finish(BackupOptionsResult(sections: {..._sections}, passphrase: ''));
  }

  String _sectionName(AppLocalizations l10n, BackupSection section) =>
      switch (section) {
        BackupSection.settings => l10n.backupSectionSettings,
        BackupSection.favorites => l10n.backupSectionFavorites,
        BackupSection.quick => l10n.backupSectionQuick,
        BackupSection.recents => l10n.backupSectionRecents,
        BackupSection.cookies => l10n.backupSectionCookies,
        BackupSection.webdavAccount => l10n.webdavAccount,
      };

  String? _sectionHint(AppLocalizations l10n, BackupSection section) =>
      switch (section) {
        BackupSection.quick => l10n.backupSectionQuickHint,
        BackupSection.recents => l10n.backupSectionRecentsHint,
        BackupSection.cookies => l10n.backupSectionCookiesHint,
        BackupSection.webdavAccount => l10n.backupSectionWebdavHint,
        _ => null,
      };

  Widget _content(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hint = _hasSensitive
        ? l10n.backupEncryptionRequired
        : l10n.backupProtectionIntro;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        M3eSectionHeader(l10n.backupProtectionTitle),
        SegmentedList(
          children: [
            M3eSwitchTile(
              label: l10n.backupUseEncryption,
              subtitle: l10n.backupPassphraseReminder,
              value: _encrypt,
              enabled: !_hasSensitive,
              onChanged: (value) => setState(() {
                _encrypt = value;
                _passphraseError = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextField(
            key: const ValueKey('backup-options-passphrase'),
            controller: _passphrase,
            enabled: _encrypt,
            obscureText: !_showPassphrase,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: _encrypt ? (_) => _submit() : null,
            onChanged: (_) {
              if (_passphraseError != null) {
                setState(() => _passphraseError = null);
              }
            },
            decoration: errorState(
              context,
              InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.backupPassphrase,
                hintText: l10n.backupPassphraseHint,
                suffixIcon: _allowPassphraseReveal && _encrypt
                    ? IconButton(
                        tooltip: _showPassphrase
                            ? l10n.hidePassword
                            : l10n.showPassword,
                        onPressed: () =>
                            setState(() => _showPassphrase = !_showPassphrase),
                        icon: Icon(
                          _showPassphrase
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      )
                    : null,
              ),
              _passphraseError,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            _encrypt ? hint : l10n.backupEncryptionOff,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _encrypt ? scheme.onSurfaceVariant : scheme.error,
            ),
          ),
        ),
        M3eSectionHeader(l10n.backupContent),
        SegmentedList(
          children: [
            for (final section in BackupSection.values)
              M3ePickTile(
                label: _sectionName(l10n, section),
                subtitle: _sectionHint(l10n, section),
                selected: _sections.contains(section),
                onTap: () => _toggleSection(section),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (widget.embedded) {
      // 右窗格已经是受控的内容区域，再套页面级 maxWidth 会与其它详情页产生
      // 可感知的左右留白差。独立整页仍保留下方的 680dp 阅读宽度限制。
      return _content(context);
    }
    return TopBarOverlayScaffold(
      controller: _scroll,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: const AppBarBackButton(),
        title: Text(widget.title ?? l10n.backupOptions),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _sections.isEmpty ? null : _submit,
              child: Text(widget.confirmLabel),
            ),
          ),
        ],
      ),
      slivers: [
        M3eReadingSliverPadding(
          padding: kM3eSectionPagePadding.copyWith(bottom: 32),
          sliver: SliverToBoxAdapter(child: _content(context)),
        ),
      ],
    );
  }
}
