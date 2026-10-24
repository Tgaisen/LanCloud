import 'dart:async';
import 'dart:convert';

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
import 'backup_options_page.dart';
import 'common.dart';
import 'm3e.dart';
import 'restore_dialogs.dart';

export 'restore_dialogs.dart';

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
          M3eReadingSliverPadding(
            padding: kM3eSectionPagePadding,
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

/// 顶栏底部那条 4dp 进度线（只在 WebDAV 网络操作时显示）。
/// 粗细与 WebView 页的进度条一致（M3eLinearProgressIndicator 默认 4dp）。
/// 独立页放在 [AppBar.bottom]；「我的」右窗格里由「我的」顶栏复用。
const PreferredSize kBackupProgressBar = PreferredSize(
  preferredSize: Size.fromHeight(4),
  child: M3eLinearProgressIndicator(height: 4),
);

/// 备份与恢复正文：本地备份 + WebDAV。
/// 独立页（push）与「我的」右窗格共用；[progress] 由宿主显示成顶栏进度线。
class BackupContent extends StatefulWidget {
  const BackupContent({
    super.key,
    required this.progress,
    this.backupOptionsOpener,
  });

  /// WebDAV 网络操作进行中时为 true。
  final ValueNotifier<bool> progress;

  /// 大屏右窗格由宿主接管“备份选项”导航；为空时打开独立页面。
  final BackupOptionsPageOpener? backupOptionsOpener;

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

  /// 跑一个可能失败的操作：统一处理忙碌标记与错误提示（失败返回 null）。
  ///
  /// [showProgress] 只在 WebDAV 这类要等网络的操作上开：本地备份 / 恢复花在
  /// 系统弹窗和本地写盘上，顶栏那条线既不是上传百分比也没参考价值。
  ///
  /// 进度线只覆盖这次操作本身：操作之后才弹的窗（选择恢复版本 / 确认恢复）
  /// 要放在 `_run` 外面，否则线会一直亮在弹窗后面。
  Future<T?> _run<T>(
    Future<T> Function() body, {
    bool showProgress = false,
  }) async {
    if (_busy) return null;
    setState(() => _busy = true);
    widget.progress.value = showProgress;
    try {
      return await body();
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
    return null;
  }

  // -------------------------------------------------------------- 本地备份

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

  /// 生成文件期间显示与「解析中」相同的 MD3E 等待弹窗。
  Future<T?> _withGeneratingDialog<T>(Future<T> Function() action) async {
    final navigator = Navigator.of(context);
    unawaited(showLoadingDialog(context, context.l10n.generatingBackup));
    await WidgetsBinding.instance.endOfFrame;
    try {
      return await action();
    } on BackupException catch (error) {
      if (mounted) _snack(error.message);
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (navigator.mounted) navigator.pop();
    }
    return null;
  }

  Future<BackupOptionsResult?> _showBackupOptions({
    required Set<BackupSection> initialSections,
    required String confirmLabel,
    String? title,
    String initialPassphrase = '',
    Future<bool> Function()? verifySensitive,
  }) {
    final opener = widget.backupOptionsOpener ?? showBackupOptionsPage;
    return opener(
      context,
      initialSections: initialSections,
      confirmLabel: confirmLabel,
      title: title,
      initialPassphrase: initialPassphrase,
      verifySensitive: verifySensitive,
    );
  }

  /// 立即备份：全屏“备份选项” → 生成等待 → 系统保存文件。
  Future<void> _backupToFile() async {
    final l10n = context.l10n;
    final options = await _showBackupOptions(
      initialSections: const <BackupSection>{},
      confirmLabel: l10n.continueLabel,
      title: l10n.backupPageTitle,
      verifySensitive: _ensureSensitiveVerified,
    );
    if (options == null || options.sections.isEmpty || !mounted) return;
    final file = await _withGeneratingDialog(
      () => _service.exportFile(
        sections: options.sections,
        passphrase: options.encrypted ? options.passphrase : null,
      ),
    );
    if (file == null || !mounted) return;
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
    if (!mounted || saved == null) return;
    _snack(l10n.backupSaved(saved));
  }

  Future<void> _restoreFromFile() => _run(() async {
    final l10n = context.l10n;
    final file = await FilePicker.pickFile(
      dialogTitle: l10n.chooseBackupFile,
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return;
    final content = utf8.decode(await file.readAsBytes());
    if (!mounted) return;
    await _confirmAndRestore(content);
  });

  Future<void> _confirmAndRestore(String content) async {
    final restored = await confirmAndRestore(context, _service, content);
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
      if (result[0].isEmpty) {
        await store.reset();
        if (mounted) setState(() {});
        return;
      }
      await store.saveServer(
        url: result[0],
        username: result[1],
        password: result[2],
        // 备份密码在“备份选项”里独立维护；改连接信息时不能误清缓存。
        backupPassphrase: store.backupPassphrase,
        path: result[3],
      );
      if (mounted) setState(() {});
    });
  }

  Future<void> _testConnection() => _run(() async {
    await _service.testConnection();
    if (mounted) _snack(context.l10n.webdavTestOk);
  }, showProgress: true);

  /// WebDAV 的“备份选项”：加密方式与备份分项一起保存。
  Future<void> _editBackupOptions() async {
    final l10n = context.l10n;
    final store = _service.webdav;
    final options = await _showBackupOptions(
      initialSections: store.backupSections,
      initialPassphrase: store.backupPassphrase,
      confirmLabel: l10n.save,
      verifySensitive: _ensureSensitiveVerified,
    );
    if (options == null || !mounted) return;
    await _run(() async {
      await store.setBackupOptions(
        sections: options.sections,
        backupPassphrase: options.encrypted ? options.passphrase : '',
      );
      if (mounted) setState(() {});
    });
  }

  Future<void> _uploadNow() async {
    if (_busy) return;
    if (!mounted) return;

    final navigator = Navigator.of(context);
    var generatingDialogOpen = true;
    setState(() => _busy = true);
    unawaited(showLoadingDialog(context, context.l10n.generatingBackup));
    await WidgetsBinding.instance.endOfFrame;
    try {
      final name = await _service.uploadNow(
        onGenerated: () {
          if (generatingDialogOpen && navigator.mounted) {
            generatingDialogOpen = false;
            navigator.pop();
          }
          // 生成阶段由弹窗表示；关闭后网络上传阶段再由顶栏进度线接管。
          if (mounted) widget.progress.value = true;
        },
      );
      if (mounted) {
        setState(() {});
        _snack(context.l10n.webdavUploadDone(name));
      }
    } on BackupException catch (error) {
      if (mounted) _snack(error.message);
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (generatingDialogOpen && navigator.mounted) navigator.pop();
      if (mounted) {
        widget.progress.value = false;
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restoreFromCloud() async {
    final l10n = context.l10n;
    // 拉列表是网络操作：进度线只亮到列表回来为止
    final entries = await _run(_service.remoteBackups, showProgress: true);
    if (!mounted) return;
    if (entries == null) return;
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.selectRestoreVersion,
              style: context.m3eEmphasizedTheme.titleLarge,
            ),
          ),
          SheetListGroup(
            margin: SheetListGroup.endMargin,
            children: [
              for (var i = 0; i < entries.length; i++)
                ListTile(
                  leading: Icon(
                    entries[i].name == BackupService.latestName
                        ? Icons.cached_outlined
                        : Icons.cloud_outlined,
                  ),
                  title: Text(entries[i].name),
                  subtitle: Text(
                    _restoreEntrySubtitle(l10n, entries[i], latest: i == 0),
                  ),
                  onTap: () => Navigator.of(context).pop(entries[i]),
                ),
            ],
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final content = await _run(
      () => _service.webdavDownload(picked.name),
      showProgress: true,
    );
    if (content == null || !mounted) return;
    await _confirmAndRestore(content);
  }

  /// 恢复列表的副标题：时间用与更新页一致的分层相对格式，
  /// 最新的一条在末尾带上「· 最新版本」。
  String _restoreEntrySubtitle(
    AppLocalizations l10n,
    WebdavEntry entry, {
    required bool latest,
  }) {
    final parts = <String>[
      if (entry.modified != null) formatRelativeTime(l10n, entry.modified!),
      if (entry.size > 0) formatBytes(entry.size),
      if (latest) l10n.restoreLatestTag,
    ];
    return parts.join(' · ');
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final store = _service.webdav;
    final scheme = Theme.of(context).colorScheme;
    final sensitiveSections = store.backupSections.any(
      (section) => section.sensitive,
    );
    final encryptionReady = !sensitiveSections || store.hasBackupPassphrase;
    final canUpload =
        store.configured &&
        store.backupSections.isNotEmpty &&
        encryptionReady &&
        !_busy;
    final canAutoBackup =
        store.configured &&
        store.backupSections.isNotEmpty &&
        encryptionReady &&
        !_busy;
    final backupStatus = !store.configured
        ? l10n.webdavNotConfigured
        : store.backupSections.isEmpty
        ? l10n.webdavBackupContentNotSelected
        : l10n.lastBackupAt(
            store.lastBackupAt == 0
                ? l10n.neverBackedUp
                : _backupDayLabel(context, store.lastBackupAt),
          );
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
              trailing: const Icon(Icons.chevron_right),
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
              subtitle: Text(
                store.needsConfiguration
                    ? l10n.webdavAccountIncomplete
                    : store.url.isEmpty
                    ? l10n.webdavNotSet
                    : store.url,
              ),
              onTap: _editServer,
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: Text(l10n.webdavTest),
              enabled: store.configured,
              onTap: _testConnection,
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text(l10n.backupOptions),
              trailing: const Icon(Icons.chevron_right),
              onTap: _editBackupOptions,
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: Text(l10n.webdavUpload),
              enabled: canUpload,
              onTap: _uploadNow,
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download),
              title: Text(l10n.webdavRestore),
              enabled: store.configured && !_busy,
              onTap: _restoreFromCloud,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.cached_outlined),
              title: Text(l10n.webdavAutoBackup),
              subtitle: Text(l10n.webdavAutoBackupSubtitle),
              value: store.autoBackup,
              onChanged: canAutoBackup
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
              Text(backupStatus, style: Theme.of(context).textTheme.bodySmall),
              if (store.configured &&
                  store.backupSections.isNotEmpty &&
                  store.lastBackupError.isNotEmpty)
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
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.webdavInterval),
        // M3 对话框内容边距 24dp；列表组自带 0 外边距，组沿落在 24dp 上
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 与其它单选弹窗同一套样式：列表组 + radio 指示
              DialogListGroup(
                children: [
                  for (final option in const ['daily', 'weekly'])
                    M3ePickTile(
                      label: option == 'weekly'
                          ? l10n.webdavWeekly
                          : l10n.webdavDaily,
                      selected: option == current,
                      singleSelect: true,
                      onTap: () => Navigator.of(dialogContext).pop(option),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (value == null) return;
    await _service.webdav.setInterval(value);
    if (mounted) setState(() {});
  }
}

/// 「上次备份」的日期：今天 / 昨天 / yyyy-MM-dd（与更新页的分层思路一致）。
String _backupDayLabel(BuildContext context, int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(date.year, date.month, date.day)).inDays;
  final l10n = context.l10n;
  if (days == 0) return l10n.dayToday;
  if (days == 1) return l10n.dayYesterday;
  return formatDateShort(millis);
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
  late final bool _allowPasswordReveal;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    // 只有首次填写（没有预填密码）时允许查看输入内容；已保存的密码不再提供明文入口。
    _allowPasswordReveal = widget.password.isEmpty;
  }

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
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) {
                  if (_pwdError != null) setState(() => _pwdError = null);
                },
                decoration: errorState(
                  context,
                  InputDecoration(
                    labelText: l10n.webdavPassword,
                    suffixIcon: _allowPasswordReveal
                        ? IconButton(
                            tooltip: _showPassword
                                ? l10n.hidePassword
                                : l10n.showPassword,
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          )
                        : null,
                  ),
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
