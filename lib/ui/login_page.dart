import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/api/lanzou_client.dart';
import '../core/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';
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
              style: context.m3eEmphasizedTheme.titleLarge,
            ),
          ),
          const LoginEntries(onSheet: true),
        ],
      ),
    );
  }
}

/// 登录方式入口：网页登录、Cookie 登录。弹窗与兜底页面共用。
class LoginEntries extends StatelessWidget {
  const LoginEntries({super.key, this.onSheet = false});

  /// 在底部弹窗里（弹窗底色 surfaceContainerLow，列表组要高一档才不糊在一起）。
  final bool onSheet;

  Future<void> _webLogin(BuildContext context) async {
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const WebLoginPage()));
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
    final children = <Widget>[
      ListTile(
        leading: const Icon(Icons.public),
        title: Text(l10n.webLogin),
        subtitle: Text(l10n.webLoginRecommended),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _webLogin(context),
      ),
      ListTile(
        leading: const Icon(Icons.badge_outlined),
        title: Text(l10n.cookieLogin),
        onTap: () => _cookieLogin(context),
      ),
    ];
    // 弹窗里用弹窗预设（容器色高一档、左右 16dp 与标题对齐，作为弹窗内容的
    // 最后一块用窗体底部边距）；页面里保持默认
    return onSheet
        ? SheetListGroup(margin: SheetListGroup.endMargin, children: children)
        : SegmentedList(children: children);
  }
}

/// Cookie 登录弹窗：获取步骤 + 粘贴框 + 校验登录；返回 true 表示登录成功。
Future<bool> showCookieLoginDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _CookieLoginDialog(),
  );
  return ok == true;
}

class _CookieLoginDialog extends StatefulWidget {
  const _CookieLoginDialog();

  @override
  State<_CookieLoginDialog> createState() => _CookieLoginDialogState();
}

class _CookieLoginDialogState extends State<_CookieLoginDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final cookie = _controller.text.trim();
    if (cookie.isEmpty) {
      setState(() => _error = l10n.pleasePasteCookie);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppController>().addAccountFromCookie(cookie);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on CookieFormatException {
      _showError(l10n.cookieMissingYlogin);
    } on CookieInvalidException {
      _showError(l10n.cookieInvalid);
    } on LanzouException catch (e) {
      _showError(l10n.lanzouError(e));
    } catch (e) {
      _showError('$e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return formDialogPan(
      context,
      child: AlertDialog(
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
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.cookieSteps,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  maxLines: 6,
                  minLines: 3,
                  decoration: errorState(
                    context,
                    InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l10n.lanzouCookie,
                      hintText: l10n.cookieHint,
                    ),
                    _error,
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.cookiePrivacy,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? l10n.verifying : l10n.saveAndLogin),
          ),
        ],
      ),
    );
  }
}

/// 无账号时的兜底页面（已同意协议但未登录）：内容与登录弹窗一致。
class LoginPage extends StatelessWidget {
  const LoginPage({super.key, this.firstRun = false});

  final bool firstRun;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final form = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          // 装饰图：应用名就在下面，读屏不用再念一遍图片
          child: Image.asset(
            'assets/images/logo/app_icon.png',
            width: 72,
            height: 72,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(height: 20),
        Text(l10n.login, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 24),
        const LoginEntries(),
      ],
    );
    // 首次启动（欢迎页同意后）没有顶栏；其余场景与其它页面一致：
    // 顶栏上滑随手指渐隐，底色不渐隐。
    if (firstRun) {
      return Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              // 内容至少铺满一屏：滚动视图本身占满高度，iOS 回弹时
              // 不会在一个缩水的高度里被上下截断
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: form),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return TopBarOverlayScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(l10n.addAccount),
        leading: const AppBarBackButton(),
      ),
      // 内容自带 SafeArea 让开导航栏，末尾不用再补一段留白
      bottomSafeInset: false,
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: SafeArea(
            top: false,
            child: Center(
              child: Padding(padding: const EdgeInsets.all(24), child: form),
            ),
          ),
        ),
      ],
    );
  }
}
