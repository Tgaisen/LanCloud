import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/api/lanzou_client.dart';
import '../core/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'web_login_page.dart';

/// 打开登录弹窗（MD3E 底部弹窗）；返回 true 表示登录成功。
Future<bool> showLoginSheet(BuildContext context) async {
  final ok = await showAppSheet<bool>(context, child: const LoginSheet());
  return ok == true;
}

/// 登录入口弹窗：网页登录 / Cookie 登录（不含 logo）。
class LoginSheet extends StatelessWidget {
  const LoginSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.login,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const LoginEntries(),
        ],
      ),
    );
  }
}

/// 登录方式入口：网页登录、Cookie 登录。弹窗与兜底页面共用。
class LoginEntries extends StatelessWidget {
  const LoginEntries({super.key});

  Future<void> _webLogin(BuildContext context) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const WebLoginPage()),
    );
    if (!context.mounted || ok != true) return;
    // 弹窗场景：登录成功后关闭弹窗；页面场景：外壳会自动切到主界面
    if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
  }

  Future<void> _cookieLogin(BuildContext context) async {
    final ok = await showCookieLoginDialog(context);
    if (!context.mounted || !ok) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SegmentedList(
      children: [
        ListTile(
          leading: const Icon(Icons.public),
          title: Text(l10n.webLogin),
          subtitle: Text(l10n.webLoginRecommended),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _webLogin(context),
        ),
        ListTile(
          leading: const Icon(Icons.password),
          title: Text(l10n.cookieLogin),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _cookieLogin(context),
        ),
      ],
    );
  }
}

/// Cookie 登录弹窗：获取步骤 + 粘贴框 + 校验登录；返回 true 表示登录成功。
Future<bool> showCookieLoginDialog(BuildContext context) async {
  final l10n = context.l10n;
  final controller = TextEditingController();
  var busy = false;
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
                  controller: controller,
                  maxLines: 6,
                  minLines: 3,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l10n.lanzouCookie,
                    hintText: l10n.cookieHint,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
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
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final cookie = controller.text.trim();
                    if (cookie.isEmpty) {
                      setDialogState(() => error = l10n.pleasePasteCookie);
                      return;
                    }
                    setDialogState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await context
                          .read<AppController>()
                          .addAccountFromCookie(cookie);
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(true);
                      }
                    } on CookieFormatException {
                      setDialogState(() => error = l10n.cookieMissingYlogin);
                    } on CookieInvalidException {
                      setDialogState(() => error = l10n.cookieInvalid);
                    } on LanzouException catch (e) {
                      setDialogState(() => error = e.message);
                    } catch (e) {
                      setDialogState(() => error = '$e');
                    } finally {
                      if (dialogContext.mounted) {
                        setDialogState(() => busy = false);
                      }
                    }
                  },
            child: Text(busy ? l10n.verifying : l10n.saveAndLogin),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return ok == true;
}

/// 无账号时的兜底页面（已同意协议但未登录）：内容与登录弹窗一致。
class LoginPage extends StatelessWidget {
  const LoginPage({super.key, this.firstRun = false});

  final bool firstRun;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: firstRun
          ? null
          : AppBar(
              title: Text(l10n.addAccount),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 72,
                    height: 72,
                  ),
                ),
                const SizedBox(height: 20),
                Text(l10n.login, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 24),
                const LoginEntries(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
