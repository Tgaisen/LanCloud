import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/data/account_store.dart';
import '../l10n/l10n.dart';
import 'about_page.dart';
import 'app_icons.dart';
import 'common.dart';
import 'login_page.dart';
import 'scroll_tint.dart';
import 'settings_page.dart';
import 'web_page.dart';

/// 「我的」视图：账号卡片 + 网页版/回收站 + 设置/关于。
/// 既作为底栏视图，也可作为独立路由打开。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.tabIndex});

  /// 外壳中的 page 视图下标；作为独立路由打开时为 null。
  final int? tabIndex;

  void _openWeb(BuildContext context, String url, String title) {
    final app = context.read<AppController>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebPage(
          title: title,
          url: url,
          cookie: app.activeAccount?.cookie,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final account = app.activeAccount;
    final uid = app.activeUid ?? '';
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final headerHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final standalone = !(ModalRoute.of(context)?.isFirst ?? true);

    return Scaffold(
      body: Stack(
        children: [
          ScrollTint(
            hideDistance: headerHeight,
            readBarsHidden: () => app.topBarHide.value,
            onBarsHidden:
                app.settings.hideTopBar ? app.setTopBarHideFromScroll : null,
            child: CustomScrollView(
              slivers: [
                // 顶栏不占布局，这里留出等高占位
                SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      SegmentedList(
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              child: Text(_avatarInitial(account, uid)),
                            ),
                            title: Text(
                              account == null
                                  ? l10n.notLoggedIn
                                  : account.nickname.isEmpty
                                      ? l10n.accountUid(uid)
                                      : account.nickname,
                            ),
                            subtitle: Text(l10n.uidLabel(uid)),
                            trailing: FilledButton.tonal(
                              onPressed: () => _showAccountSwitcher(context),
                              child: Text(l10n.manage),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SegmentedList(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.public),
                            title: Text(l10n.webManagement),
                            trailing: const Icon(Icons.open_in_new),
                            onTap: () => _openWeb(
                              context,
                              'https://pc.woozooo.com/mydisk.php',
                              l10n.webManagement,
                            ),
                          ),
                          ListTile(
                            leading:
                                const Icon(Icons.restore_from_trash_outlined),
                            title: Text(l10n.recycleBin),
                            trailing: const Icon(Icons.open_in_new),
                            onTap: () => _openWeb(
                              context,
                              'https://pc.woozooo.com/mydisk.php?item=recycle',
                              l10n.recycleBin,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SegmentedList(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.settings_outlined),
                            title: Text(l10n.settings),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SettingsPage(),
                              ),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.info_outline),
                            title: Text(l10n.about),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AboutPage(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 96),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          // 顶栏浮层：与底栏共用收起进度
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: TopBarOverlay(
              height: headerHeight,
              background: Color.lerp(
                scheme.surface,
                scheme.surfaceContainer,
                ScrollTint.of(context),
              )!,
              builder: (context) => AppBar(
                backgroundColor: Colors.transparent,
                scrolledUnderElevation: 0,
                leading: standalone
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(context).pop(),
                      )
                    : null,
                title: Text(l10n.tabProfile),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _avatarInitial(Account? account, String uid) {
    final name = account == null
        ? ''
        : account.nickname.isNotEmpty
            ? account.nickname
            : uid;
    if (name.isEmpty) return '?';
    return name.substring(0, 1);
  }

  Future<void> _showAccountSwitcher(BuildContext context) async {
    final app = context.read<AppController>();
    await showAppSheet<void>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final account in app.accounts.accounts)
            ListTile(
              leading: Icon(
                account.uid == app.activeUid
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(
                account.nickname.isEmpty
                    ? context.l10n.accountUid(account.uid)
                    : account.nickname,
              ),
              subtitle: Text(context.l10n.uidLabel(account.uid)),
              onTap: () async {
                Navigator.of(context).pop();
                await app.switchAccount(account.uid);
              },
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(context.l10n.addAccount),
            onTap: () async {
              Navigator.of(context).pop();
              await showLoginSheet(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(context.l10n.logout),
            onTap: () {
              final uid = app.activeUid;
              Navigator.of(context).pop();
              if (uid != null) _removeAccount(context, uid);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _removeAccount(BuildContext context, String uid) async {
    final app = context.read<AppController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.removeAccountTitle),
        content: Text(context.l10n.removeAccountMessage(uid)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.remove),
          ),
        ],
      ),
    );
    if (ok == true) await app.removeAccount(uid);
  }
}
