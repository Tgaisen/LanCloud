import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/api/lanzou_client.dart';
import '../core/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'web_login_page.dart';

/// 登录页：与首次启动欢迎页同款布局，底部两个入口（网页登录 / Cookie 登录）。
/// Cookie 输入与获取步骤放在「Cookie 登录」弹窗里。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.firstRun = false});

  final bool firstRun;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 在 Cookie 登录弹窗里校验并保存账号。
  Future<void> _submit(
    void Function(VoidCallback) refresh,
    BuildContext dialogContext,
  ) async {
    void update(VoidCallback fn) {
      refresh(fn);
      if (mounted) setState(() {});
    }

    final cookie = _controller.text.trim();
    if (cookie.isEmpty) {
      update(() => _error = context.l10n.pleasePasteCookie);
      return;
    }
    update(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppController>().addAccountFromCookie(cookie);
      if (!mounted) return;
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      if (!widget.firstRun) Navigator.of(context).pop();
    } on CookieFormatException {
      update(() => _error = context.l10n.cookieMissingYlogin);
    } on CookieInvalidException {
      update(() => _error = context.l10n.cookieInvalid);
    } on LanzouException catch (e) {
      update(() => _error = e.message);
    } catch (e) {
      update(() => _error = '$e');
    } finally {
      update(() => _busy = false);
    }
  }

  Future<void> _webLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const WebLoginPage()),
    );
    if (!mounted || ok != true) return;
    if (!widget.firstRun) Navigator.of(context).pop();
  }

  Future<void> _cookieLogin() async {
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: Text(l10n.cookieLogin),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.howToGetCookie,
                    style: Theme.of(dialogContext).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.cookieSteps,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    maxLines: 6,
                    minLines: 3,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l10n.lanzouCookie,
                      hintText: l10n.cookieHint,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    l10n.cookiePrivacy,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed:
                  _busy ? null : () => _submit(setDialogState, dialogContext),
              child: Text(_busy ? l10n.verifying : l10n.saveAndLogin),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: widget.firstRun
          ? null
          : AppBar(
              title: Text(l10n.addAccount),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 72,
                    height: 72,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.login,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: _LoginAction(
                      icon: Icons.public,
                      label: l10n.webLogin,
                      onPressed: _busy ? null : _webLogin,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _LoginAction(
                      icon: Icons.password,
                      label: l10n.cookieLogin,
                      onPressed: _busy ? null : _cookieLogin,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 登录页底部入口按钮：与欢迎页一致的中性胶囊底。
class _LoginAction extends StatelessWidget {
  const _LoginAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
