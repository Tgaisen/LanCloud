import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/api/lanzou_client.dart';
import '../core/api/models.dart';
import '../core/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'share_file_sheet.dart';
import 'share_folder_page.dart';

/// 打开分享链接：以底部弹窗形式呈现。
Future<void> openShareSheet(
  BuildContext context, {
  String? initialLink,
  String? initialPwd,
}) {
  // 复用统一弹窗外壳：滚到顶部后继续下拉可带动弹窗收起。
  // 上限取整屏，保证弹出键盘时表单仍能完整显示（与改造前一致）。
  return showAppSheet<void>(
    context,
    maxHeightRatio: 1,
    child: ShareSheet(initialLink: initialLink, initialPwd: initialPwd),
  );
}

class ShareSheet extends StatefulWidget {
  const ShareSheet({super.key, this.initialLink, this.initialPwd});

  final String? initialLink;
  final String? initialPwd;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  late final TextEditingController _linkController =
      TextEditingController(text: widget.initialLink ?? '');
  late final TextEditingController _pwdController =
      TextEditingController(text: widget.initialPwd ?? '');
  bool _loading = false;
  String? _error;
  String? _pwdError;
  DirectFile? _file;

  @override
  void initState() {
    super.initState();
    if (widget.initialLink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _parse());
    }
  }

  @override
  void dispose() {
    _linkController.dispose();
    _pwdController.dispose();
    super.dispose();
  }

  bool get _looksLikeFolder {
    final link = _linkController.text.trim();
    return RegExp(r'lanzou[a-z]*\.com/(s/)?b[a-zA-Z0-9]{7,}').hasMatch(link);
  }

  Future<void> _parse() async {
    final link = _linkController.text.trim();
    final pwd = _pwdController.text.trim();
    if (link.isEmpty) {
      setState(() => _error = context.l10n.pleasePasteShareLink);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _pwdError = null;
      _file = null;
    });
    final client = context.read<AppController>().publicClient;
    final navigator = Navigator.of(context);
    try {
      if (_looksLikeFolder) {
        final folder = await client.resolveFolderShare(link, pwd: pwd);
        if (!mounted) return;
        await _saveRecent('shareFolder', folder.name, link, pwd);
        if (!mounted) return;
        navigator.pop();
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => ShareFolderPage(
              folder: folder,
              link: link,
              pwd: pwd,
            ),
          ),
        );
      } else {
        try {
          final file = await client.resolveFileShare(link, pwd: pwd);
          if (!mounted) return;
          setState(() => _file = file);
          await _saveRecent('shareFile', file.name, link, pwd);
          if (!mounted) return;
          // 识别为文件后直接打开属性弹窗，免去用户再点一次卡片。
          _openFileInfo(file, link, pwd);
        } on LanzouException {
          final folder = await client.resolveFolderShare(link, pwd: pwd);
          if (!mounted) return;
          await _saveRecent('shareFolder', folder.name, link, pwd);
          if (!mounted) return;
          navigator.pop();
          await navigator.push(
            MaterialPageRoute(
              builder: (_) => ShareFolderPage(
                folder: folder,
                link: link,
                pwd: pwd,
              ),
            ),
          );
        }
      }
    } on NeedPasswordException catch (e) {
      setState(() {
        _error = null;
        _pwdError = e.message;
      });
    } on LanzouException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = context.l10n.resolveFailed('$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveRecent(
    String kind,
    String name,
    String link,
    String pwd,
  ) async {
    final app = context.read<AppController>();
    await app.db.addRecent(
      account: app.activeUid ?? '',
      kind: kind,
      name: name,
      ref: link,
      pwd: pwd,
    );
  }

  /// 打开分享文件属性弹窗（解析成功自动弹出、点击文件卡片共用）。
  ///
  /// 先关掉「打开链接」弹窗，避免两层弹窗叠在一起；弹窗关闭后原 context
  /// 失效，所以用 Navigator 自己的 context 作为宿主。
  void _openFileInfo(DirectFile file, String link, String pwd) {
    final navigator = Navigator.of(context);
    final hostContext = navigator.context;
    if (navigator.canPop()) navigator.pop();
    showAppSheet<void>(
      hostContext,
      child: ShareFileInfoSheet(
        name: file.name,
        url: link,
        pwd: pwd,
        size: file.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.openShare,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _linkController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l10n.shareLink,
                  hintText: l10n.shareLinkHint,
                  prefixIcon: const Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pwdController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l10n.passwordOptional,
                  prefixIcon: const Icon(Icons.password),
                  errorText: _pwdError,
                  suffixIcon: _pwdError == null
                      ? null
                      : Icon(
                          Icons.cancel,
                          color: Theme.of(context).colorScheme.error,
                        ),
                ),
                onChanged: (_) {
                  if (_pwdError != null) {
                    setState(() => _pwdError = null);
                  }
                },
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loading ? null : _parse,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_loading ? l10n.resolving : l10n.resolve),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(_error!),
                  ),
                ),
              ],
              if (_file != null) ...[
                const SizedBox(height: 16),
                _FileResultCard(
                  file: _file!,
                  onTap: () => _openFileInfo(
                    _file!,
                    _linkController.text.trim(),
                    _pwdController.text.trim(),
                  ),
                ),
              ],
            ],
        ),
    );
  }
}

class _FileResultCard extends StatelessWidget {
  const _FileResultCard({
    required this.file,
    required this.onTap,
  });

  final DirectFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(iconForFile(file.name), size: 30),
        title: Text(
          file.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: file.size.isEmpty
            ? null
            : Text(l10n.sizeLabel(prettyLzSize(file.size))),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
