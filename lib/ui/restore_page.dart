import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/lanzou_client.dart';
import '../core/backup/backup_service.dart';
import '../core/backup/backup_service_provider.dart';
import '../core/backup/webdav_client.dart';
import '../core/backup/webdav_store.dart';
import '../core/cookie_auth.dart';
import '../core/navigation_appearance_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'backup_unlock_dialog.dart';
import 'backup_preview_view.dart';
import 'common.dart';
import 'm3e.dart';
import 'reduce_motion.dart';
import 'scroll_tint.dart';
import 'system_ui.dart';

/// 恢复页返回给登录页的结果；普通返回不会带结果。
enum RestorePageResult { restored }

enum _RestoreStage { source, credentials, versions, preview }

enum _RestoreSource { local, cloud }

/// 未登录状态下可用的恢复向导。
///
/// 向导只读取和检查备份，用户确认后才调用 [BackupService.restoreFromString]。
/// 如果 Cookie 失效、蓝奏云不可达或备份本来就不含 Cookie，仍可只恢复数据。
class RestorePage extends ConsumerStatefulWidget {
  const RestorePage({super.key});

  @override
  ConsumerState<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends ConsumerState<RestorePage> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _path = TextEditingController(
    text: WebdavStore.defaultPath,
  );

  late final BackupService _service;
  final ValueNotifier<double> _topBarHide = ValueNotifier(0);
  _RestoreStage _stage = _RestoreStage.source;
  _RestoreSource? _source;
  List<WebdavEntry> _remoteEntries = const [];
  BackupPreview? _preview;
  BackupAccountPreview? _candidate;
  LoginStateValidation? _loginStatus;
  String _content = '';
  String _label = '';
  String _backupPassphrase = '';
  String? _error;
  bool _busy = false;
  bool _showProgress = false;
  bool _showPassword = false;
  bool _sensitiveAuthorized = false;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _service = ref.read(backupServiceProvider);
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _path.dispose();
    _topBarHide.dispose();
    super.dispose();
  }

  void _goBack() {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _topBarHide.value = 0;
    switch (_stage) {
      case _RestoreStage.source:
        Navigator.of(context).pop();
        return;
      case _RestoreStage.credentials:
        setState(() {
          _forward = false;
          _stage = _RestoreStage.source;
          _error = null;
        });
        return;
      case _RestoreStage.versions:
        setState(() {
          _forward = false;
          _stage = _RestoreStage.credentials;
          _error = null;
        });
        return;
      case _RestoreStage.preview:
        setState(() {
          _forward = false;
          _stage = _source == _RestoreSource.cloud
              ? _RestoreStage.versions
              : _RestoreStage.source;
          _error = null;
        });
        return;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _showProgress = true;
      _error = null;
    });
    try {
      await action();
    } on BackupException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FormatException {
      if (mounted) setState(() => _error = context.l10n.restoreFileInvalid);
    } on FileSystemException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _showProgress = false;
        });
      }
    }
  }

  Future<void> _pickLocalFile() async {
    PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        dialogTitle: context.l10n.chooseBackupFile,
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
      return;
    }
    final selectedFile = file;
    if (selectedFile == null || !mounted) return;
    // 系统文件选择器本身不显示页面内进度；用户选中文件后才进入读取阶段。
    await _run(() async {
      final content = utf8.decode(await selectedFile.readAsBytes());
      _source = _RestoreSource.local;
      await _inspectAndPreview(content, selectedFile.name);
    });
  }

  Future<bool> _confirmInsecureConnection(String url) async {
    final scheme = Uri.tryParse(url)?.scheme.toLowerCase();
    if (scheme != 'http') return true;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.restoreInsecureTitle),
        content: Text(l10n.restoreInsecureMessage),
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
    return confirmed == true;
  }

  Future<void> _connectCloud() async {
    final l10n = context.l10n;
    final url = _url.text.trim();
    final username = _username.text.trim();
    final password = _password.text;
    final path = _path.text.trim();
    String? validationError;
    if (url.isEmpty) {
      validationError = l10n.pleaseEnterWebdavServer;
    } else if (!WebdavClient.isValidUrl(url)) {
      validationError = l10n.webdavUrlFormatError;
    } else if (username.isEmpty) {
      validationError = l10n.pleaseEnterUsername;
    } else if (password.isEmpty) {
      validationError = l10n.pleaseEnterPassword;
    }
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    if (!await _confirmInsecureConnection(url) || !mounted) return;
    await _run(() async {
      final entries = await _service.remoteBackupsWithConnection(
        url: url,
        username: username,
        password: password,
        path: path.isEmpty ? WebdavStore.defaultPath : path,
      );
      if (!mounted) return;
      if (entries.isEmpty) {
        setState(() => _error = l10n.webdavNoBackups);
        return;
      }
      _source = _RestoreSource.cloud;
      _topBarHide.value = 0;
      setState(() {
        _forward = true;
        _remoteEntries = entries;
        _stage = _RestoreStage.versions;
      });
    });
  }

  Future<void> _selectRemote(WebdavEntry entry) async {
    await _run(() async {
      final content = await _service.webdavDownloadWithConnection(
        entry.name,
        url: _url.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
        path: _path.text.trim().isEmpty
            ? WebdavStore.defaultPath
            : _path.text.trim(),
      );
      await _inspectAndPreview(content, entry.name);
    });
  }

  Future<void> _inspectAndPreview(String content, String label) async {
    var plaintext = content;
    _backupPassphrase = '';
    if (BackupService.isEncrypted(content)) {
      // 解密弹窗自身显示验证进度；顶栏进度只在弹窗关闭后的检查阶段出现。
      setState(() => _showProgress = false);
      final unlocked = await showBackupUnlockDialog(context, content: content);
      if (unlocked == null || !mounted) return;
      plaintext = unlocked.content;
      _backupPassphrase = unlocked.passphrase;
      setState(() => _showProgress = true);
    }
    final preview = BackupService.inspect(plaintext);
    var sensitiveAuthorized = false;
    String? authorizationError;
    if (preview.hasSensitiveData && mounted) {
      final l10n = context.l10n;
      final result = await CookieAuth.instance.verify(
        l10n.restoreSensitiveAuthReason,
        messages: authMessagesFor(l10n),
      );
      if (!mounted) return;
      switch (result) {
        case CookieAuthResult.ok:
          sensitiveAuthorized = true;
        case CookieAuthResult.canceled:
          return;
        case CookieAuthResult.unavailable:
          authorizationError = l10n.cookieAuthUnavailable;
        case CookieAuthResult.failed:
          authorizationError = l10n.cookieAuthFailed;
      }
    }
    final candidate = sensitiveAuthorized ? preview.suggestedAccount : null;
    LoginStateValidation? status;
    if (candidate != null && mounted) {
      final client = LanzouClient(uid: candidate.uid)
        ..setCookieHeader(candidate.cookie);
      status = await client.validateLoginState();
    }
    if (!mounted) return;
    _topBarHide.value = 0;
    setState(() {
      _content = plaintext;
      _label = label;
      _preview = preview;
      _candidate = candidate;
      _loginStatus = status;
      _sensitiveAuthorized = sensitiveAuthorized;
      _error = authorizationError;
      _forward = true;
      _stage = _RestoreStage.preview;
    });
  }

  Future<void> _recheckLogin() async {
    final candidate = _candidate;
    if (candidate == null) return;
    await _run(() async {
      final client = LanzouClient(uid: candidate.uid)
        ..setCookieHeader(candidate.cookie);
      final status = await client.validateLoginState();
      if (mounted) setState(() => _loginStatus = status);
    });
  }

  Future<void> _restore({required bool includeAccounts}) async {
    if (_preview == null || _content.isEmpty) return;
    if (includeAccounts &&
        _preview!.hasSensitiveData &&
        !_sensitiveAuthorized) {
      final l10n = context.l10n;
      final result = await CookieAuth.instance.verify(
        l10n.restoreSensitiveAuthReason,
        messages: authMessagesFor(l10n),
      );
      if (!mounted) return;
      switch (result) {
        case CookieAuthResult.ok:
          _sensitiveAuthorized = true;
        case CookieAuthResult.canceled:
          return;
        case CookieAuthResult.unavailable:
          setState(() => _error = l10n.cookieAuthUnavailable);
          return;
        case CookieAuthResult.failed:
          setState(() => _error = l10n.cookieAuthFailed);
          return;
      }
    }
    await _run(() async {
      await _service.restoreFromString(
        _content,
        mergeFavorites: true,
        restoreAccounts: includeAccounts,
      );
      // 云端恢复使用的临时连接在成功后转为持久配置；若备份本身恢复了
      // WebDAV 账号，则保留备份中的完整配置，避免被恢复页输入覆盖。
      final restoredWebdavCredentials =
          includeAccounts && (_preview?.hasWebdavCredentials ?? false);
      if (_source == _RestoreSource.cloud && !restoredWebdavCredentials) {
        await _service.webdav.saveServer(
          url: _url.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
          backupPassphrase: _backupPassphrase,
          path: _path.text.trim().isEmpty
              ? WebdavStore.defaultPath
              : _path.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop(RestorePageResult.restored);
    });
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(navigationAppearanceSettingsStateProvider);
    return ListenableBuilder(
      listenable: appearance.revision,
      builder: (context, _) => _buildPage(context, appearance.hideTopBar),
    );
  }

  Widget _buildPage(BuildContext context, bool hideTopBar) {
    final l10n = context.l10n;
    final safeInsets = systemUiSafeInsets(context);
    final large = isLargeLayout(context);
    // 大屏时 Md3eBodyCard 已经让开窗口边缘与系统导航栏，内容内不再重复加。
    final contentInsets = large ? EdgeInsets.zero : safeInsets;
    final title = switch (_stage) {
      _RestoreStage.source => l10n.restoreExistingBackup,
      _RestoreStage.credentials => l10n.webdavAccount,
      _RestoreStage.versions => l10n.restoreChooseCopy,
      _RestoreStage.preview => l10n.restorePreviewTitle,
    };
    return PopScope(
      canPop: !_busy && _stage == _RestoreStage.source,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _goBack();
      },
      child: ScrollTint(
        hideDistance: safeInsets.top + kToolbarHeight + 4,
        readBarsHidden: () => _topBarHide.value,
        onBarsHidden: hideTopBar
            ? (value) => _topBarHide.value = value
            : null,
        child: Builder(
          builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            final appBar = AppBar(
              backgroundColor: Colors.transparent,
              scrolledUnderElevation: 0,
              title: Text(title),
              leading: AppBarBackButton(onPressed: _busy ? () {} : _goBack),
              bottom: _showProgress
                  ? const PreferredSize(
                      preferredSize: Size.fromHeight(4),
                      child: M3eLinearProgressIndicator(height: 4),
                    )
                  : null,
            );
            final topInset = safeInsets.top + appBar.preferredSize.height;
            return Scaffold(
              backgroundColor: large
                  ? Theme.of(context).colorScheme.surfaceContainer
                  : null,
              body: Stack(
                children: [
                  Md3eBodyCard(
                    topBarHeight: topInset,
                    hide: _topBarHide,
                    // 大屏：navigation area 用 surfaceContainer，正文进入统一的
                    // 16dp 圆角 surface 卡片；小屏原样铺满。
                    child: AnimatedSwitcher(
                      duration: reduceMotionOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      // 每个步骤都占满同一个视口。旧内容和新内容在固定尺寸的
                      // Stack 中沿 X 轴交接，不会因为高度不同先掉到下面。
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        fit: StackFit.expand,
                        children: [...previousChildren, ?currentChild],
                      ),
                      transitionBuilder: (child, animation) {
                        final incoming = child.key == ValueKey(_stage);
                        const distance = 0.06;
                        final slide = Offset(
                          _forward ? distance : -distance,
                          0,
                        );
                        return SlideTransition(
                          position: Tween<Offset>(
                            begin: incoming ? slide : -slide,
                            end: Offset.zero,
                          ).animate(animation),
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(_stage),
                        child: _buildStageViewport(
                          context,
                          topInset,
                          contentInsets,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: TopBarOverlay(
                      height: topInset,
                      progress: _topBarHide,
                      // 顶栏背景随滚动从 surface 渐变到 surfaceContainer；
                      // 内容再随收起进度一起滑出。
                      background: topBarBackgroundColor(context, scheme),
                      builder: (context) => appBar,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStageViewport(
    BuildContext context,
    double topInset,
    EdgeInsets safeInsets,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          safeInsets.left + (constraints.maxWidth < 600 ? 16 : 24),
          topInset + 16,
          safeInsets.right + (constraints.maxWidth < 600 ? 16 : 24),
          safeInsets.bottom + 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _buildStage(context),
          ),
        ),
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          _ErrorBanner(message: _error!),
          const SizedBox(height: 16),
        ],
        switch (_stage) {
          _RestoreStage.source => _buildSource(context),
          _RestoreStage.credentials => _buildCredentials(context),
          _RestoreStage.versions => _buildVersions(context),
          _RestoreStage.preview => _buildPreview(context),
        },
      ],
    );
  }

  Widget _buildSource(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.restoreIntro,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: 20),
        SegmentedList(
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text(l10n.restoreLocalSource),
              subtitle: Text(l10n.restoreLocalSourceSubtitle),
              onTap: _busy ? null : _pickLocalFile,
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(l10n.restoreCloudSource),
              subtitle: Text(l10n.restoreCloudSourceSubtitle),
              onTap: _busy
                  ? null
                  : () => setState(() {
                      _topBarHide.value = 0;
                      _forward = true;
                      _stage = _RestoreStage.credentials;
                      _error = null;
                    }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCredentials(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.webdavRestoreIntro,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _url,
          autocorrect: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: l10n.webdavServer,
            hintText: l10n.webdavServerHint,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _username,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: l10n.webdavUsername,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: !_showPassword,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: l10n.webdavPassword,
            suffixIcon: IconButton(
              tooltip: _showPassword ? l10n.hidePassword : l10n.showPassword,
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _path,
          autocorrect: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_busy) _connectCloud();
          },
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: l10n.webdavPath,
            hintText: l10n.webdavPathHint,
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _connectCloud,
                child: Text(l10n.restoreConnect),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVersions(BuildContext context) {
    final l10n = context.l10n;
    return SegmentedList(
      children: [
        for (var i = 0; i < _remoteEntries.length; i++)
          ListTile(
            leading: Icon(
              _remoteEntries[i].name == BackupService.latestName
                  ? Icons.cached_outlined
                  : Icons.cloud_outlined,
            ),
            title: Text(_remoteEntries[i].name),
            subtitle: Text(
              _restoreEntrySubtitle(l10n, _remoteEntries[i], latest: i == 0),
            ),
            onTap: _busy ? null : () => _selectRemote(_remoteEntries[i]),
          ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    final l10n = context.l10n;
    final preview = _preview!;
    final canLogin = _loginStatus == LoginStateValidation.valid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BackupPreviewDetails(
          preview: preview,
          fileName: _label,
          candidate: _candidate,
          loginStatus: _loginStatus,
          onRecheckLogin: _busy ? null : _recheckLogin,
        ),
        const SizedBox(height: 20),
        if (canLogin) ...[
          FilledButton(
            onPressed: _busy ? null : () => _restore(includeAccounts: true),
            child: Text(l10n.restoreAndLogin),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _restore(includeAccounts: false),
            child: Text(l10n.restoreOnlyData),
          ),
        ] else
          FilledButton(
            onPressed: _busy ? null : () => _restore(includeAccounts: false),
            child: Text(
              _candidate == null ? l10n.restoreData : l10n.restoreOnlyData,
            ),
          ),
      ],
    );
  }

  String _restoreEntrySubtitle(
    AppLocalizations l10n,
    WebdavEntry entry, {
    required bool latest,
  }) {
    return [
      if (entry.modified != null) formatRelativeTime(l10n, entry.modified!),
      if (entry.size > 0) formatBytes(entry.size),
      if (latest) l10n.restoreLatestTag,
    ].join(' · ');
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
