import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/lanzou_client.dart';
import '../core/api/lanzou_client_registry.dart';
import '../core/api/models.dart';
import '../core/account_state.dart';
import '../core/data/app_db_provider.dart';
import '../core/lanzou_link.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';
import 'share_file_sheet.dart';
import 'share_folder_page.dart';

/// 打开分享链接：普通弹窗（取消 / 解析），与「修改文件夹信息」弹窗一致。
///
/// 解析成功后关闭弹窗：文件直接打开文件属性弹窗，文件夹进入浏览页；
/// 需要密码或解析失败时弹窗保留，在弹窗内提示。
Future<void> openShareSheet(
  BuildContext context, {
  String? initialLink,
  String? initialPwd,
  bool addFavoriteOnResolve = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ShareLinkDialog(
      initialLink: initialLink,
      initialPwd: initialPwd,
      addFavoriteOnResolve: addFavoriteOnResolve,
    ),
  );
}

class ShareLinkDialog extends ConsumerStatefulWidget {
  const ShareLinkDialog({
    super.key,
    this.initialLink,
    this.initialPwd,
    this.addFavoriteOnResolve = false,
  });

  final String? initialLink;
  final String? initialPwd;

  /// 解析成功后不打开，而是直接加入收藏（收藏页「添加收藏」用）。
  final bool addFavoriteOnResolve;

  @override
  ConsumerState<ShareLinkDialog> createState() => _ShareLinkDialogState();
}

class _ShareLinkDialogState extends ConsumerState<ShareLinkDialog> {
  late final TextEditingController _linkController = TextEditingController(
    text: widget.initialLink ?? '',
  );
  late final TextEditingController _pwdController = TextEditingController(
    text: widget.initialPwd ?? '',
  );
  bool _loading = false;

  /// 分享链接输入框的 error state（空 / 格式不对 / 解析失败）
  String? _linkError;

  /// 提取码输入框的 error state（需要提取码 / 提取码错误）
  String? _pwdError;

  @override
  void initState() {
    super.initState();
    if (widget.initialLink != null) {
      // 带链接进来（分享 / 二维码 / 最近使用）：直接解析，不用再点一次。
      WidgetsBinding.instance.addPostFrameCallback((_) => _parse());
    }
  }

  @override
  void dispose() {
    _linkController.dispose();
    _pwdController.dispose();
    super.dispose();
  }

  bool _looksLikeFolder(String link) =>
      RegExp(r'lanzou[a-z]*\.com/(s/)?b[a-zA-Z0-9]{7,}').hasMatch(link);

  Future<void> _parse() async {
    final raw = _linkController.text.trim();
    if (raw.isEmpty) {
      setState(() => _linkError = context.l10n.pleasePasteShareLink);
      return;
    }
    // 只看「像不像一条网址」——蓝奏云有自定义域名的分享链接，
    // 不能只认 lanzou 域名；取不出一条网址才原地标「格式错误」
    final link = LanzouLink.urlFrom(raw);
    if (link == null) {
      setState(() => _linkError = context.l10n.shareLinkFormatError);
      return;
    }
    // 输入里自带提取码（「… 密码: abcd」）时顺手填进提取码框
    if (_pwdController.text.trim().isEmpty) {
      final parsedPwd = LanzouLink.extractPwd(raw);
      if (parsedPwd != null) _pwdController.text = parsedPwd;
    }
    final pwd = _pwdController.text.trim();
    setState(() {
      _loading = true;
      _linkError = null;
      _pwdError = null;
    });
    final client = ref.read(lanzouClientRegistryProvider).publicClient;
    final navigator = Navigator.of(context);
    try {
      if (_looksLikeFolder(link)) {
        final folder = await client.resolveFolderShare(link, pwd: pwd);
        if (!mounted) return;
        await _saveRecent('shareFolder', folder.name, link, pwd);
        if (!mounted) return;
        if (widget.addFavoriteOnResolve) {
          await _addFavorite(
            kind: 'shareFolder',
            name: folder.name,
            link: link,
            pwd: pwd,
            sharer: folder.sharer,
          );
          return;
        }
        navigator.pop();
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ShareFolderPage(folder: folder, link: link, pwd: pwd),
          ),
        );
      } else {
        try {
          final file = await client.resolveFileShare(link, pwd: pwd);
          if (!mounted) return;
          await _saveRecent('shareFile', file.name, link, pwd);
          if (!mounted) return;
          if (widget.addFavoriteOnResolve) {
            await _addFavorite(
              kind: 'shareFile',
              name: file.name,
              link: link,
              pwd: pwd,
              size: file.size,
            );
            return;
          }
          _openFileInfo(file, link, pwd);
        } on NeedPasswordException {
          // 需要提取码 / 提取码错误要原样抛给弹窗标在输入框上，
          // 不能落进下面的"按文件夹再试一次"
          rethrow;
        } on WrongPasswordException {
          rethrow;
        } on LanzouException {
          final folder = await client.resolveFolderShare(link, pwd: pwd);
          if (!mounted) return;
          await _saveRecent('shareFolder', folder.name, link, pwd);
          if (!mounted) return;
          if (widget.addFavoriteOnResolve) {
            await _addFavorite(
              kind: 'shareFolder',
              name: folder.name,
              link: link,
              pwd: pwd,
              sharer: folder.sharer,
            );
            return;
          }
          navigator.pop();
          await navigator.push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ShareFolderPage(folder: folder, link: link, pwd: pwd),
            ),
          );
        }
      }
    } on NeedPasswordException catch (e) {
      setState(() {
        _linkError = null;
        _pwdError = context.l10n.lanzouError(e);
      });
    } on WrongPasswordException catch (e) {
      // 与「该分享需要提取码」相同的样式：标在提取码输入框上
      setState(() {
        _linkError = null;
        _pwdError = context.l10n.lanzouError(e);
      });
    } on LanzouException catch (e) {
      setState(() => _linkError = context.l10n.lanzouError(e));
    } catch (e) {
      setState(() => _linkError = context.l10n.resolveFailed('$e'));
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
    final account = ref.read(accountStateProvider).store.activeUid ?? '';
    final db = ref.read(appDbProvider);
    await db.addRecent(
      account: account,
      kind: kind,
      name: name,
      ref: link,
      pwd: pwd,
    );
  }

  /// 收藏模式：写入收藏、关闭弹窗并提示。
  Future<void> _addFavorite({
    required String kind,
    required String name,
    required String link,
    required String pwd,
    String sharer = '',
    String size = '',
  }) async {
    final l10n = context.l10n;
    final db = ref.read(appDbProvider);
    final navigator = Navigator.of(context);
    // 弹窗关闭后原 context 失效，关弹窗与提示改用 Navigator 自己的宿主
    final messenger = ScaffoldMessenger.of(navigator.context);
    await db.addFavorite(
      kind: kind,
      name: name,
      ref: link,
      pwd: pwd,
      sharer: sharer,
      size: size,
    );
    if (!mounted) return;
    if (navigator.canPop()) navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(l10n.addedToFavorites)));
  }

  /// 解析出文件：关掉弹窗，再打开文件属性弹窗。
  ///
  /// 弹窗关闭后原 context 失效，用 Navigator 自己的 context 作为新弹窗宿主。
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
        sharer: file.sharer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return formDialog(
      context,
      title: Text(l10n.openShare),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _linkController,
            // 手动打开时直接聚焦链接框；带链接进来会立即解析，不弹键盘。
            autofocus: widget.initialLink == null,
            onChanged: (_) {
              if (_linkError != null) setState(() => _linkError = null);
            },
            decoration: errorState(
              context,
              InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.shareLink,
                hintText: l10n.shareLinkHint,
                prefixIcon: const Icon(Icons.link),
              ),
              _linkError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pwdController,
            decoration: errorState(
              context,
              InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.passwordOptional,
                prefixIcon: const Icon(Icons.password),
              ),
              _pwdError,
            ),
            onChanged: (_) {
              if (_pwdError != null) {
                setState(() => _pwdError = null);
              }
            },
            onSubmitted: (_) {
              if (!_loading) _parse();
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _loading ? null : _parse,
          child: _loading
              ? const M3eCircularProgressIndicator(size: 18, strokeWidth: 2)
              : Text(l10n.resolve),
        ),
      ],
    );
  }
}
