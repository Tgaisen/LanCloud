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
import '../core/backup/webdav_store.dart';
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
        // M3 对话框内容边距 24dp；列表组外边距 0，组沿落在 24dp 上
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${l10n.restoreConfirmMessage}\n\n$label'),
            if (hasFavorites) ...[
              const SizedBox(height: 16),
              // 复选行放进列表组（与选择弹窗同一套样式）
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

/// 备份与恢复（独立页）：本地 JSON 文件 + WebDAV 云端。
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  /// 页面列表；传给 TopBarOverlayScaffold 后点顶栏空白即可回到顶部。
  final ScrollController _scroll = ScrollController();

  /// 顶栏那条线是否显示：只在 WebDAV 的网络操作上开（见 [BackupContent]）。
  final ValueNotifier<bool> _progress = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _scroll.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<bool>(
      valueListenable: _progress,
      builder: (context, busy, _) => TopBarOverlayScaffold(
        controller: _scroll,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
          leading: const AppBarBackButton(),
          title: Text(l10n.backupAndRestore),
          bottom: busy ? kBackupProgressBar : null,
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            // 整块布局：避免懒布局估算导致滚动条滑块抖动（见 SliverColumn）
            sliver: SliverToBoxAdapter(
              child: BackupContent(progress: _progress),
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶栏底部那条 2dp 进度线（只在 WebDAV 网络操作时显示）。
/// 独立页放在 [AppBar.bottom]；「我的」右窗格里由「我的」顶栏复用。
const PreferredSize kBackupProgressBar = PreferredSize(
  preferredSize: Size.fromHeight(2),
  child: M3eLinearProgressIndicator(height: 2),
);

/// 备份与恢复正文：本地备份 + WebDAV。
/// 独立页（push）与「我的」右窗格共用；[progress] 由宿主显示成顶栏进度线。
class BackupContent extends StatefulWidget {
  const BackupContent({super.key, required this.progress});

  /// WebDAV 网络操作进行中时为 true。
  final ValueNotifier<bool> progress;

  @override
  State<BackupContent> createState() => _BackupContentState();
}

class _BackupContentState extends State<BackupContent> {
  late final BackupService _service;
  bool _busy = false;

  @override
  void dispose() {
    // 离开（切窗格 / 关页面）时别再让顶栏留着进度线
    widget.progress.value = false;
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
    setState(() => _busy = true);
    widget.progress.value = showProgress;
    try {
      await body();
    } on BackupException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.progress.value = false;
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
          // 每个分项一个 MD3E 列表组（组内 2dp 间隔 + 连接式圆角）；
          // 选中项用次级色底 + 对勾（与其它选择弹窗同一套样式）
          Widget group(String name, List<BackupSection> sections) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 弹窗里列表组外边距为 0：标题也无缩进，与外沿对齐
              M3eSectionHeader(name, horizontalInset: 0),
              // 列表组比弹窗底（surfaceContainerHigh）再高一档容器色
              DialogListGroup(
                children: [
                  for (final section in sections)
                    M3ePickTile(
                      label: _sectionName(l10n, section),
                      selected: selected.contains(section),
                      onTap: () => toggle(section, !selected.contains(section)),
                    ),
                ],
              ),
            ],
          );

          return AlertDialog(
            title: Text(title),
            // M3 对话框内容边距 24dp；列表组自带 0 外边距，组沿落在 24dp 上
            contentPadding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  group(l10n.backupGroupGeneral, const [
                    BackupSection.settings,
                    BackupSection.favorites,
                  ]),
                  group(l10n.backupGroupAccount, const [
                    BackupSection.quick,
                    BackupSection.recents,
                  ]),
                  group(l10n.backupGroupSensitive, const [
                    BackupSection.cookies,
                    BackupSection.webdavAccount,
                  ]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
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
        if (sections.contains(section)) _sectionName(l10n, section),
    ].join(' · ');
  }

  /// 备份分项的名称（摘要与「备份内容」弹窗共用）。
  String _sectionName(AppLocalizations l10n, BackupSection section) =>
      switch (section) {
        BackupSection.settings => l10n.backupSectionSettings,
        BackupSection.favorites => l10n.backupSectionFavorites,
        BackupSection.quick => l10n.backupSectionQuick,
        BackupSection.recents => l10n.backupSectionRecents,
        BackupSection.cookies => l10n.backupSectionCookies,
        BackupSection.webdavAccount => l10n.webdavAccount,
      };

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
        path: store.path,
      ),
    );
    if (result == null) return;
    await _run(() async {
      await store.saveServer(
        url: result[0],
        username: result[1],
        password: result[2],
        path: result[3],
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
      child: SheetListGroup(
        margin: SheetListGroup.endMargin,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        M3eSectionHeader(l10n.localBackup),
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
        M3eSectionHeader(l10n.webdavSection),
        SegmentedList(
          children: [
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(l10n.webdavAccount),
              subtitle: Text(store.url.isEmpty ? l10n.webdavNotSet : store.url),
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
    required this.path,
  });

  final String url;
  final String username;
  final String password;

  /// 备份 / 恢复目录（服务器地址下的路径）。
  final String path;

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
  late final TextEditingController _path = TextEditingController(
    text: widget.path,
  );

  String? _urlError;
  String? _userError;
  String? _pwdError;
  String? _pathError;

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pwd.dispose();
    _path.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = context.l10n;
    final url = _url.text.trim();
    final user = _user.text.trim();
    final pwd = _pwd.text;
    final path = _path.text.trim();
    // 四项都必填：缺哪个标哪个；地址再单独查一次格式
    setState(() {
      _urlError = url.isEmpty
          ? l10n.pleaseEnterWebdavServer
          : (WebdavClient.isValidUrl(url) ? null : l10n.webdavUrlFormatError);
      _userError = user.isEmpty ? l10n.pleaseEnterUsername : null;
      _pwdError = pwd.isEmpty ? l10n.pleaseEnterPassword : null;
      _pathError = path.isEmpty ? l10n.pleaseEnterWebdavPath : null;
    });
    if (_urlError != null ||
        _userError != null ||
        _pwdError != null ||
        _pathError != null) {
      return;
    }
    Navigator.of(context).pop([url, user, pwd, path]);
  }

  /// 重置 = 清空并移除配置（地址为空即未配置状态），路径回到默认值，
  /// 关弹窗交给调用方落盘。
  void _reset() {
    Navigator.of(context)
        .pop(const <String>['', '', '', WebdavStore.defaultPath]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // 四个输入框的配置弹窗：套上「不被输入法压扁 + 上移聚焦」外壳
    return formDialogPan(
      context,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        // 键盘弹出时弹窗被压缩，内容/按钮区会拿到无界高度（debug 下报
        // "RenderFlex children have non-zero flex but incoming height
        // constraints are unbounded"）；交给 AlertDialog 自己滚动即可。
        scrollable: true,
        title: Text(l10n.webdavAccount),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                onChanged: (_) {
                  if (_urlError != null) setState(() => _urlError = null);
                },
                decoration: errorState(
                  context,
                  InputDecoration(
                    labelText: l10n.webdavServer,
                    hintText: l10n.webdavServerHint,
                  ),
                  _urlError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _user,
                onChanged: (_) {
                  if (_userError != null) setState(() => _userError = null);
                },
                decoration: errorState(
                  context,
                  InputDecoration(labelText: l10n.webdavUsername),
                  _userError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pwd,
                obscureText: true,
                onChanged: (_) {
                  if (_pwdError != null) setState(() => _pwdError = null);
                },
                decoration: errorState(
                  context,
                  InputDecoration(labelText: l10n.webdavPassword),
                  _pwdError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _path,
                keyboardType: TextInputType.url,
                onChanged: (_) {
                  if (_pathError != null) setState(() => _pathError = null);
                },
                decoration: errorState(
                  context,
                  InputDecoration(
                    labelText: l10n.webdavPath,
                    hintText: l10n.webdavPathHint,
                  ),
                  _pathError,
                ),
              ),
            ],
          ),
        ),
        actions: [
          // 中立：清空所有项并关弹窗 = 移除配置（保存不再接受空值，见 _save）
          TextButton(onPressed: _reset, child: Text(l10n.reset)),
          FilledButton(onPressed: _save, child: Text(l10n.save)),
        ],
      ),
    );
  }
}
