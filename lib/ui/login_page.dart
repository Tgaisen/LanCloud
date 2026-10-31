import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/lanzou_client.dart';
import '../core/account_login.dart';
import '../core/account_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';
import 'restore_page.dart';
import 'system_ui.dart';
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
  const LoginEntries({super.key, this.onSheet = false, this.onRestore});

  /// 在底部弹窗里（弹窗底色 surfaceContainerLow，列表组要高一档才不糊在一起）。
  final bool onSheet;

  /// 未登录的首次启动页传入；添加账号弹窗不提供恢复入口。
  final VoidCallback? onRestore;

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
    final loginChildren = <Widget>[
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
    if (onSheet) {
      // 弹窗自身已有“登录”标题，列表组直接作为内容最后一块。
      return SheetListGroup(
        margin: SheetListGroup.endMargin,
        children: loginChildren,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        M3eSectionHeader(l10n.login),
        SegmentedList(children: loginChildren),
        if (onRestore != null) ...[
          M3eSectionHeader(l10n.restoreGroupTitle),
          SegmentedList(
            children: [
              ListTile(
                leading: const Icon(Icons.settings_backup_restore),
                title: Text(l10n.restoreExistingBackup),
                trailing: const Icon(Icons.chevron_right),
                onTap: onRestore,
              ),
            ],
          ),
        ],
      ],
    );
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

class _CookieLoginDialog extends ConsumerStatefulWidget {
  const _CookieLoginDialog();

  @override
  ConsumerState<_CookieLoginDialog> createState() => _CookieLoginDialogState();
}

class _CookieLoginDialogState extends ConsumerState<_CookieLoginDialog> {
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
      await ref.read(accountLoginProvider).addAccountFromCookie(cookie);
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

/// 无账号时的兜底页面（已同意协议但未登录）。
class LoginPage extends ConsumerWidget {
  const LoginPage({
    super.key,
    this.firstRun = false,
    this.credentialsResetNotice = false,
  });

  final bool firstRun;

  /// 安全存储跨大版本后不可迁移时，明确说明为什么回到了登录页。
  final bool credentialsResetNotice;

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.of(context).push<RestorePageResult>(
      MaterialPageRoute(builder: (_) => const RestorePage()),
    );
    if (!context.mounted) return;
    // 完整恢复会由 RootShell 自动切到主界面；仅恢复数据时仍停留在这里。
    if (result == RestorePageResult.restored &&
        ref.read(accountStateProvider).store.activeUid == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.restoreDataDone)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final safeInsets = systemUiSafeInsets(context);
    Widget brand({required bool wide}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        // 欢迎页已经展示过应用 Logo；这里用 MD3E 形状图标框直接表达
        // “开始使用”的动作，不再重复品牌图。
        const M3eShapedIcon(
          icon: Icons.login,
          size: 88,
          iconSize: 44,
          shape: Shapes.c4SidedCookie,
        ),
        const SizedBox(height: 20),
        Text(
          l10n.startUsingTitle,
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: context.m3eEmphasizedTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.startUsingSubtitle,
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.55,
          ),
        ),
      ],
    );

    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (credentialsResetNotice) ...[
          Semantics(
            liveRegion: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.secureStorageResetTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.secureStorageResetMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        LoginEntries(onRestore: firstRun ? () => _restore(context, ref) : null),
      ],
    );

    Widget responsiveBody({EdgeInsets systemInsets = EdgeInsets.zero}) =>
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            final pagePadding = constraints.maxWidth < 600 ? 16.0 : 24.0;
            final contentHeight = math.max(
              0.0,
              constraints.maxHeight - systemInsets.vertical,
            );
            return SingleChildScrollView(
              child: Padding(
                padding: systemInsets,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: contentHeight),
                  child: Padding(
                    padding: EdgeInsets.all(pagePadding),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(flex: 5, child: brand(wide: true)),
                                  const SizedBox(width: 48),
                                  SizedBox(width: 480, child: actions),
                                ],
                              )
                            : ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 480,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    brand(wide: false),
                                    const SizedBox(height: 32),
                                    actions,
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );

    // 首次启动（欢迎页同意后）没有顶栏；其余场景与其它页面一致：
    // 顶栏上滑随手指渐隐，底色不渐隐。
    final Widget page;
    if (firstRun) {
      page = Scaffold(body: responsiveBody(systemInsets: safeInsets));
    } else {
      page = TopBarOverlayScaffold(
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
            child: SafeArea(top: false, child: responsiveBody()),
          ),
        ],
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiOverlayStyleFor(theme.brightness),
      child: page,
    );
  }
}
