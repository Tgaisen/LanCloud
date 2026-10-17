import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/api/lanzou_client.dart';
import '../core/api/models.dart';
import '../core/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';

/// 「此文件夹需要密码」：子文件夹是独立分享、带自己的提取码时，输入后重新解析。
///
/// 与首页「打开链接」弹窗同一套骨架（[formDialog] + 输入框内联报错 +
/// 取消 / 确定）；解析成功返回文件夹与这次用的提取码，浏览页要用它继续
/// 解析里面的文件。
Future<({FolderShareDetail folder, String pwd})?> showFolderPasswordDialog(
  BuildContext context, {
  required String url,
}) {
  return showDialog<({FolderShareDetail folder, String pwd})>(
    context: context,
    builder: (_) => FolderPasswordDialog(url: url),
  );
}

class FolderPasswordDialog extends StatefulWidget {
  const FolderPasswordDialog({super.key, required this.url});

  /// 子文件夹的分享链接。
  final String url;

  @override
  State<FolderPasswordDialog> createState() => _FolderPasswordDialogState();
}

class _FolderPasswordDialogState extends State<FolderPasswordDialog> {
  final TextEditingController _pwd = TextEditingController();
  bool _loading = false;

  /// 提取码输入框的 error state（空 / 提取码错误 / 其它解析失败）
  String? _error;

  @override
  void dispose() {
    _pwd.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final pwd = _pwd.text.trim();
    if (pwd.isEmpty) {
      setState(() => _error = context.l10n.passwordRequired);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = context.read<AppController>().publicClient;
    try {
      final folder = await client.resolveFolderShare(widget.url, pwd: pwd);
      if (!mounted) return;
      Navigator.of(context).pop((folder: folder, pwd: pwd));
    } on WrongPasswordException catch (e) {
      // 「提取码错误」标在输入框上，与「打开链接」弹窗一致
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } on LanzouException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = context.l10n.resolveFailed('$e');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return formDialog(
      context,
      title: Text(l10n.folderNeedsPassword),
      content: TextField(
        controller: _pwd,
        autofocus: true,
        decoration: errorState(
          context,
          InputDecoration(
            border: const OutlineInputBorder(),
            labelText: l10n.passwordFieldLabel,
            hintText: l10n.pwdHint,
            prefixIcon: const Icon(Icons.password),
          ),
          _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: Text(_loading ? l10n.resolving : l10n.confirm),
        ),
      ],
    );
  }
}
