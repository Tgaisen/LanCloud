import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/backup/backup_service.dart';
import '../core/backup/webdav_client.dart';
import '../core/system_share.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'scroll_tint.dart';

/// 备份与恢复：本地 JSON 文件 + WebDAV 云端。
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  late final BackupService _service;
  bool _busy = false;

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

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
    } on BackupException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -------------------------------------------------------------- 本地备份

  Future<void> _backupToFile() => _run(() async {
        final l10n = context.l10n;
        final file = await _service.saveLocal(
          includeCookies: _service.webdav.includeCookies,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.backupSaved(file.path)),
            action: SnackBarAction(
              label: l10n.cookieExport,
              onPressed: () => SystemShare.shareFile(
                file.path,
                subject: '${l10n.appName} ${l10n.backupAndRestore}',
              ),
            ),
          ),
        );
      });

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
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.restore_from_trash_outlined),
        title: Text(l10n.restoreConfirmTitle),
        content: Text('${l10n.restoreConfirmMessage}\n\n$label'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await _service.restoreFromString(content);
      if (mounted) _snack(context.l10n.restoreDone);
    });
  }

  // ---------------------------------------------------------------- WebDAV

  Future<void> _editServer() async {
    final l10n = context.l10n;
    final store = _service.webdav;
    final url = await _promptText(
      title: l10n.webdavServer,
      hint: l10n.webdavServerHint,
      value: store.url,
    );
    if (url == null) return;
    final user = await _promptText(
      title: l10n.webdavUsername,
      value: store.username,
    );
    if (user == null) return;
    final password = await _promptText(
      title: l10n.webdavPassword,
      value: store.password,
      obscure: true,
    );
    if (password == null) return;
    await _run(() async {
      await store.saveServer(url: url, username: user, password: password);
      if (mounted) setState(() {});
    });
  }

  Future<String?> _promptText({
    required String title,
    String hint = '',
    String value = '',
    bool obscure = false,
  }) async {
    final controller = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (text) => Navigator.of(dialogContext).pop(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(context.l10n.confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _testConnection() => _run(() async {
        await _service.testConnection();
        if (mounted) _snack(context.l10n.webdavTestOk);
      });

  Future<void> _uploadNow() => _run(() async {
        final name = await _service.uploadNow();
        if (mounted) {
          setState(() {});
          _snack(context.l10n.webdavUploadDone(name));
        }
      });

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
      });

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final l10n = context.l10n;
    final store = _service.webdav;
    final scheme = Theme.of(context).colorScheme;
    return ScrollTint(
      child: Builder(
        builder: (context) => Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: app.settings.hideTopBar,
                snap: false,
                pinned: !app.settings.hideTopBar,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                backgroundColor: Color.lerp(
                  scheme.surface,
                  scheme.surfaceContainerHighest,
                  ScrollTint.of(context),
                ),
                scrolledUnderElevation: 0,
                title: Text(l10n.backupAndRestore),
                bottom: _busy
                    ? const PreferredSize(
                        preferredSize: Size.fromHeight(2),
                        child: LinearProgressIndicator(minHeight: 2),
                      )
                    : null,
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
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
                          leading: const Icon(Icons.restore_from_trash_outlined),
                          title: Text(l10n.restoreFromFile),
                          subtitle: Text(l10n.restoreFromFileSubtitle),
                          onTap: _restoreFromFile,
                        ),
                        SwitchListTile(
                          secondary: const Icon(Icons.password),
                          title: Text(l10n.includeCookies),
                          subtitle: Text(l10n.includeCookiesSubtitle),
                          value: store.includeCookies,
                          onChanged: (value) async {
                            await store.setIncludeCookies(value);
                            if (mounted) setState(() {});
                          },
                        ),
                      ],
                    ),
                    _section(context, l10n.webdavSection),
                    SegmentedList(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.dns_outlined),
                          title: Text(l10n.webdavServer),
                          subtitle: Text(
                            store.url.isEmpty ? l10n.webdavNotSet : store.url,
                          ),
                          onTap: _editServer,
                        ),
                        ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(l10n.webdavUsername),
                          subtitle: Text(
                            store.username.isEmpty
                                ? l10n.webdavNotSet
                                : store.username,
                          ),
                          onTap: _editServer,
                        ),
                        ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: Text(l10n.webdavPassword),
                          subtitle: Text(
                            store.password.isEmpty
                                ? l10n.webdavNotSet
                                : '••••••',
                          ),
                          onTap: _editServer,
                        ),
                      ],
                    ),
                    _section(context, l10n.webdavBackup),
                    SegmentedList(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.link_outlined),
                          title: Text(l10n.webdavTest),
                          enabled: store.configured,
                          onTap: _testConnection,
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
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: scheme.error),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
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
                      option == 'weekly'
                          ? l10n.webdavWeekly
                          : l10n.webdavDaily,
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
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
}
