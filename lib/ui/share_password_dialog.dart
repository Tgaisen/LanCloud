import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/api/lanzou_client.dart';
import '../core/api/models.dart';
import '../core/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';

/// 密码弹窗的结果：解析出的对象 + 这次用的提取码。
typedef PasswordResult<T> = ({T value, String pwd});

/// 「此文件夹需要密码」：子文件夹 / 收藏的文件夹提取码不对时，输入后重新解析。
Future<PasswordResult<FolderShareDetail>?> showFolderPasswordDialog(
  BuildContext context, {
  required String url,
}) {
  final client = context.read<AppController>().publicClient;
  return showDialog<PasswordResult<FolderShareDetail>>(
    context: context,
    builder: (_) => _SharePasswordDialog<FolderShareDetail>(
      title: context.l10n.folderNeedsPassword,
      resolve: (pwd) => client.resolveFolderShare(url, pwd: pwd),
    ),
  );
}

/// 「此文件需要密码」：分享文件的提取码不对（例如上传者改过）时，
/// 输入后重新解析；解析成功返回文件信息与这次用的提取码。
Future<PasswordResult<DirectFile>?> showFilePasswordDialog(
  BuildContext context, {
  required String url,
}) {
  final client = context.read<AppController>().publicClient;
  return showDialog<PasswordResult<DirectFile>>(
    context: context,
    builder: (_) => _SharePasswordDialog<DirectFile>(
      title: context.l10n.fileNeedsPassword,
      resolve: (pwd) =>
          client.resolveFileShare(url, pwd: pwd, withDescription: true),
    ),
  );
}

/// 与首页「打开链接」同一套骨架（[formDialog] + 输入框内联报错 +
/// 取消 / 确定）；文件、文件夹共用，只是标题与解析方法不同。
class _SharePasswordDialog<T> extends StatefulWidget {
  const _SharePasswordDialog({required this.title, required this.resolve});

  final String title;
  final Future<T> Function(String pwd) resolve;

  @override
  State<_SharePasswordDialog<T>> createState() =>
      _SharePasswordDialogState<T>();
}

class _SharePasswordDialogState<T> extends State<_SharePasswordDialog<T>> {
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
    try {
      final value = await widget.resolve(pwd);
      if (!mounted) return;
      Navigator.of(context).pop((value: value, pwd: pwd));
    } on WrongPasswordException catch (e) {
      // 「提取码错误」标在输入框上，与「打开链接」弹窗一致
      if (mounted) {
        setState(() {
          _error = context.l10n.lanzouError(e);
          _loading = false;
        });
      }
    } on LanzouException catch (e) {
      if (mounted) {
        setState(() {
          _error = context.l10n.lanzouError(e);
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
      title: Text(widget.title),
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
