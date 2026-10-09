import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/backup/backup_sections.dart';
import '../core/backup/backup_service.dart';
import '../core/backup/webdav_client.dart';
import '../core/cookie_auth.dart';
import '../core/system_file_saver.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';

/// 恢复前确认弹窗的结果：nil 表示取消。
class RestoreDecision {
  const RestoreDecision({required this.keepFavorites});

  /// 勾选「保留原收藏夹内容」：增量合并并按 ref 去重。
  final bool keepFavorites;
}

/// 恢复前确认弹窗：无图标的默认文本标题；备份里含收藏夹时多一个
/// 「保留原收藏夹内容」复选（默认勾选）。
Future<RestoreDecision?> showRestoreConfirmDialog(
  BuildContext context, {
  required String label,
  required bool hasFavorites,
}) {
  final l10n = context.l10n;
  var keepFavorites = true;
  return showDialog<RestoreDecision>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(l10n.restoreConfirmTitle),
        // 内容不加左右内边距：复选行自己铺满弹窗宽度，
        // 点按波纹/悬停高亮和「默认启动页」弹窗一样是整个宽度
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text('${l10n.restoreConfirmMessage}\n\n$label'),
            ),
            if (hasFavorites) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                // 文字与弹窗内其它内容左对齐，但墨水区域是整行
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                controlAffinity: ListTileControlAffinity.leading,
                value: keepFavorites,
                onChanged: (value) =>
                    setDialogState(() => keepFavorites = value ?? true),
                title: Text(l10n.restoreKeepFavorites),
                subtitle: Text(l10n.restoreKeepFavoritesHint),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext)
                    .pop(RestoreDecision(keepFavorites: keepFavorites)),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    ),
  );
}

/// 「确认 → 恢复」流程：从文件恢复与从云端恢复共用。
///
/// 调用方负责忙碌状态与错误提示：这里**不能**再自己包一层 `_run`，
/// 调用方已经在 `_run` 里了，重入会被忙碌保护直接吞掉——历史 bug 就是
/// 因此"弹窗确认后什么都没发生"。
Future<bool> confirmAndRestore(
  BuildContext context,
  BackupService service,
  String content,
  String label,
) async {
  final decision = await showRestoreConfirmDialog(
    context,
    label: label,
    hasFavorites: BackupService.containsFavorites(content),
  );
  if (decision == null) return false;
  await service.restoreFromString(
    content,
    mergeFavorites: decision.keepFavorites,
  );
  return true;
}

/// 备份与恢复：本地 JSON 文件 + WebDAV 云端。
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  late final BackupService _service;
  bool _busy = false;

  /// 顶栏那条线是否显示：只在 WebDAV 的网络操作上开（见 [_run]）。
  bool _progress = false;

  /// 页面列表；传给 TopBarOverlayScaffold 后点顶栏空白即可回到顶部。
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _service = BackupService.of(context.read<AppController>());
    _service.init().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// 跑一个可能失败的操作：统一处理忙碌标记与错误提示。
  ///
  /// [showProgress] 只在 WebDAV 这类要等网络的操作上开：本地备份 / 恢复花在
  /// 系统弹窗和本地写盘上，顶栏那条线既不是上传百分比也没参考价值。
  Future<void> _run(
    Future<void> Function() body, {
    bool showProgress = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = showProgress;
    });
    try {
      await body();
    } on BackupException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = false;
        });
      }
    }
  }

  // -------------------------------------------------------------- 本地备份

  /// 「备份内容」弹窗：三个分组 + 复选，默认都不勾。
  ///
  /// 敏感项（Cookie / WebDav 账号）勾选前先做身份验证；本次运行验证通过过
  /// 就不再重复验证。返回 null 表示取消，返回空集合表示一项都没选。
  Future<Set<BackupSection>?> _pickBackupContent({
    required Set<BackupSection> initial,
    required String title,
  }) {
    final l10n = context.l10n;
    final selected = <BackupSection>{...initial};
    return showDialog<Set<BackupSection>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> toggle(BackupSection section, bool value) async {
            if (!value) {
              setDialogState(() => selected.remove(section));
              return;
            }
            if (section.sensitive && !await _ensureSensitiveVerified()) return;
            if (!mounted || !dialogContext.mounted) return;
            setDialogState(() => selected.add(section));
          }

          final theme = Theme.of(dialogContext);
          Widget group(String name) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Text(
              name,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          );
          Widget item(BackupSection section, IconData icon, String label) =>
              CheckboxListTile(
                secondary: Icon(icon),
                title: Text(label),
                value: selected.contains(section),
                onChanged: (value) => toggle(section, value ?? false),
              );

          return AlertDialog(
            title: Text(title),
            // 左右不留内边距：选项整行显示，波纹不会被截断
            contentPadding: const EdgeInsets.only(top: 4, bottom: 4),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  group(l10n.backupGroupGeneral),
                  item(
                    BackupSection.settings,
                    Icons.settings_outlined,
                    l10n.backupSectionSettings,
                  ),
                  item(
                    BackupSection.favorites,
                    Icons.star_border,
                    l10n.backupSectionFavorites,
                  ),
                  group(l10n.backupGroupAccount),
                  item(
                    BackupSection.quick,
                    Icons.push_pin_outlined,
                    l10n.backupSectionQuick,
                  ),
                  item(
                    BackupSection.recents,
                    Icons.history,
                    l10n.backupSectionRecents,
                  ),
                  group(l10n.backupGroupSensitive),
                  item(
                    BackupSection.cookies,
                    Icons.password,
                    l10n.backupSectionCookies,
                  ),
                  item(
                    BackupSection.webdavAccount,
                    Icons.dns_outlined,
                    l10n.webdavAccount,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      l10n.backupContentHint,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                // 一项都没选就没有可导出的内容
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.of(dialogContext).pop({...selected}),
                child: Text(l10n.confirm),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 敏感内容需要身份验证：本次运行验证通过一次后不再重复验证。
  /// 返回 true 表示可以继续。
  Future<bool> _ensureSensitiveVerified() async {
    if (_service.sensitiveVerified) return true;
    final l10n = context.l10n;
    final result = await CookieAuth.instance.verify(
      l10n.cookieAuthReason,
      messages: authMessagesFor(l10n),
    );
    if (!mounted) return false;
    switch (result) {
      case CookieAuthResult.ok:
        _service.sensitiveVerified = true;
        return true;
      case CookieAuthResult.canceled:
        return false;
      case CookieAuthResult.unavailable:
        _snack(l10n.cookieAuthUnavailable);
        return false;
      case CookieAuthResult.failed:
        _snack(l10n.cookieAuthFailed);
        return false;
    }
  }

  /// 勾选内容的文字摘要：设置项 · 收藏夹，空集合显示「未选择」。
  String _sectionsLabel(Set<BackupSection> sections) {
    final l10n = context.l10n;
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

  /// 立即备份：每次都在弹窗里重新勾选要写进本次备份的内容。
  Future<void> _backupToFile() async {
    final l10n = context.l10n;
    final sections = await _pickBackupContent(
      initial: const <BackupSection>{},
      title: l10n.backupContent,
    );
    if (sections == null || sections.isEmpty || !mounted) return;
    await _run(() async {
      final file = await _service.exportFile(sections: sections);
      final String? saved;
      try {
        saved = await SystemFileSaver.save(
          sourcePath: file.path,
          fileName: p.basename(file.path),
          mime: 'application/json',
        );
      } catch (_) {
        if (mounted) _snack(l10n.cookieExportFailed);
        return;
      }
      if (!mounted || saved == null) return; // 用户取消保存
      _snack(l10n.backupSaved(saved));
    });
  }

  Future<void> _restoreFromFile() => _run(() async {
    final l10n = context.l10n;
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: l10n.chooseBackupFile,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes;
    final content = bytes != null
        ? utf8.decode(bytes)
        : await File(file.path!).readAsString();
    if (!mounted) return;
    await _confirmAndRestore(content, file.name);
  });

  Future<void> _confirmAndRestore(String content, String label) async {
    final restored = await confirmAndRestore(context, _service, content, label);
    if (restored && mounted) _snack(context.l10n.restoreDone);
  }

  // ---------------------------------------------------------------- WebDAV

  Future<void> _editServer() async {
    final store = _service.webdav;
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => WebdavAccountDialog(
        url: store.url,
        username: store.username,
        password: store.password,
      ),
    );
    if (result == null) return;
    await _run(() async {
      await store.saveServer(
        url: result[0],
        username: result[1],
        password: result[2],
      );
      if (mounted) setState(() {});
    });
  }

  Future<void> _testConnection() => _run(() async {
    await _service.testConnection();
    if (mounted) _snack(context.l10n.webdavTestOk);
  }, showProgress: true);

  /// WebDAV 的「备份内容」：勾选结果保存下来，只影响云端上传。
  Future<void> _editBackupSections() async {
    final l10n = context.l10n;
    final picked = await _pickBackupContent(
      initial: _service.webdav.backupSections,
      title: l10n.backupContent,
    );
    if (picked == null || !mounted) return;
    await _service.webdav.setBackupSections(picked);
    if (mounted) setState(() {});
  }

  Future<void> _uploadNow() => _run(() async {
    // 备份内容含敏感项（Cookie / WebDav 账号）时，本次运行至少验证过一次身份
    if (_service.webdav.backupSections.any((s) => s.sensitive) &&
        !await _ensureSensitiveVerified()) {
      return;
    }
    if (!mounted) return;
    final name = await _service.uploadNow();
    if (mounted) {
      setState(() {});
      _snack(context.l10n.webdavUploadDone(name));
    }
  }, showProgress: true);

  Future<void> _restoreFromCloud() => _run(() async {
    final l10n = context.l10n;
    final entries = await _service.remoteBackups();
    if (!mounted) return;
    if (entries.isEmpty) {
      _snack(l10n.webdavNoBackups);
      return;
    }
    final picked = await showAppSheet<WebdavEntry>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in entries)
            ListTile(
              leading: Icon(
                entry.name == BackupService.latestName
                    ? Icons.cached_outlined
                    : Icons.cloud_outlined,
              ),
              title: Text(entry.name),
              subtitle: Text(
                '${entry.modified == null ? '' : formatDateShort(entry.modified!.millisecondsSinceEpoch)}'
                '${entry.size > 0 ? ' · ${formatBytes(entry.size)}' : ''}',
              ),
              onTap: () => Navigator.of(context).pop(entry),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final content = await _service.webdavDownload(picked.name);
    if (!mounted) return;
    await _confirmAndRestore(content, picked.name);
  }, showProgress: true);

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final store = _service.webdav;
    final scheme = Theme.of(context).colorScheme;
    return TopBarOverlayScaffold(
      controller: _scroll,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: const AppBarBackButton(),
        title: Text(l10n.backupAndRestore),
        bottom: _progress
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: M3eLinearProgressIndicator(height: 2),
              )
            : null,
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          // 整块布局：避免懒布局估算导致滚动条滑块抖动（见 SliverColumn）
          sliver: SliverColumn(
            children: [
              _section(context, l10n.localBackup),
              SegmentedList(
                children: [
                  ListTile(
                    leading: const Icon(Icons.upload_file_outlined),
                    title: Text(l10n.backupNow),
                    subtitle: Text(l10n.backupNowSubtitle),
                    onTap: _backupToFile,
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_backup_restore),
                    title: Text(l10n.restoreFromFile),
                    subtitle: Text(l10n.restoreFromFileSubtitle),
                    onTap: _restoreFromFile,
                  ),
                ],
              ),
              _section(context, l10n.webdavSection),
              SegmentedList(
                children: [
                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: Text(l10n.webdavAccount),
                    subtitle: Text(
                      store.url.isEmpty ? l10n.webdavNotSet : store.url,
                    ),
                    onTap: _editServer,
                  ),
                  ListTile(
                    leading: const Icon(Icons.link_outlined),
                    title: Text(l10n.webdavTest),
                    enabled: store.configured,
                    onTap: _testConnection,
                  ),
                  // WebDAV 的备份内容会保存下来，只影响云端上传
                  ListTile(
                    leading: const Icon(Icons.checklist),
                    title: Text(l10n.backupContent),
                    subtitle: Text(_sectionsLabel(store.backupSections)),
                    onTap: _editBackupSections,
                  ),
                  ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: Text(l10n.webdavUpload),
                    enabled: store.configured && !_busy,
                    onTap: _uploadNow,
                  ),
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: Text(l10n.webdavRestore),
                    enabled: store.configured && !_busy,
                    onTap: _restoreFromCloud,
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.cached_outlined),
                    title: Text(l10n.webdavAutoBackup),
                    subtitle: Text(l10n.webdavAutoBackupSubtitle),
                    value: store.autoBackup,
                    onChanged: store.configured
                        ? (value) async {
                            await store.setAutoBackup(value);
                            if (mounted) setState(() {});
                          }
                        : null,
                  ),
                  if (store.autoBackup)
                    ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: Text(l10n.webdavInterval),
                      subtitle: Text(
                        store.interval == 'weekly'
                            ? l10n.webdavWeekly
                            : l10n.webdavDaily,
                      ),
                      onTap: _pickInterval,
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.lastBackupAt(
                        store.lastBackupAt == 0
                            ? l10n.neverBackedUp
                            : formatDateShort(store.lastBackupAt),
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (store.lastBackupError.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          l10n.backupFailed(store.lastBackupError),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickInterval() async {
    final l10n = context.l10n;
    final current = _service.webdav.interval;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.webdavInterval),
        children: [
          for (final option in const ['daily', 'weekly'])
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(option),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      option == 'weekly' ? l10n.webdavWeekly : l10n.webdavDaily,
                    ),
                  ),
                  if (option == current)
                    Icon(
                      Icons.check,
                      color: Theme.of(dialogContext).colorScheme.primary,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (value == null) return;
    await _service.webdav.setInterval(value);
    if (mounted) setState(() {});
  }

  Widget _section(BuildContext context, String name) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
    child: Text(
      name,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// WebDAV 账号编辑弹窗：自己持有输入控制器，并在弹窗销毁时释放。
///
/// 不能像以前那样在 `showDialog` 返回后立刻 dispose：弹窗退场动画期间输入框
/// 仍会重建，会触发 "A TextEditingController was used after being disposed"。
class WebdavAccountDialog extends StatefulWidget {
  const WebdavAccountDialog({
    super.key,
    required this.url,
    required this.username,
    required this.password,
  });

  final String url;
  final String username;
  final String password;

  @override
  State<WebdavAccountDialog> createState() => _WebdavAccountDialogState();
}

class _WebdavAccountDialogState extends State<WebdavAccountDialog> {
  late final TextEditingController _url = TextEditingController(
    text: widget.url,
  );
  late final TextEditingController _user = TextEditingController(
    text: widget.username,
  );
  late final TextEditingController _pwd = TextEditingController(
    text: widget.password,
  );

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pwd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      // 键盘弹出时弹窗被压缩，内容/按钮区会拿到无界高度（debug 下报
      // "RenderFlex children have non-zero flex but incoming height
      // constraints are unbounded"）；交给 AlertDialog 自己滚动即可。
      scrollable: true,
      title: Text(l10n.webdavSection),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.webdavServer,
                hintText: l10n.webdavServerHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              decoration: InputDecoration(labelText: l10n.webdavUsername),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pwd,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.webdavPassword),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        // 中立：清空三项，保存后即恢复到未配置状态
        TextButton(
          onPressed: () => setState(() {
            _url.clear();
            _user.clear();
            _pwd.clear();
          }),
          child: Text(l10n.reset),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop([_url.text, _user.text, _pwd.text]),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
