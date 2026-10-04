import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/api/lanzou_client.dart';
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
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.tabIndex});

  /// 外壳中的 page 视图下标；作为独立路由打开时为 null。
  final int? tabIndex;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with AutomaticKeepAliveClientMixin {
  /// 切到别的视图再切回来时保留本页状态（含列表滚动位置）。
  /// 「我的」在底栏最边上，PageView 只会保活相邻页，不声明就每次都会重建。
  @override
  bool get wantKeepAlive => true;

  /// 列表滚动位置：切到别的视图再切回来时保留（和首页 / 网盘等页面一致）。
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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
    super.build(context); // AutomaticKeepAliveClientMixin 要求
    final app = context.watch<AppController>();
    final account = app.activeAccount;
    final uid = app.activeUid ?? '';
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final headerHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final standalone = !(ModalRoute.of(context)?.isFirst ?? true);

    return Scaffold(
      // 大屏外壳里的页面：背景交给外壳的圆角卡片
      backgroundColor:
          transparentPageBackground(context) ? Colors.transparent : null,
      body: Stack(
        children: [
          // 小屏：正文区整体让开左右挖孔 / 侧边导航栏；顶栏（浮层）保持原样
          BodySideInset(
            child: ScrollTint(
              hideDistance: headerHeight,
              readBarsHidden: () => app.topBarHide.value,
              onBarsHidden:
                  app.settings.hideTopBar ? app.setTopBarHideFromScroll : null,
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  // 顶栏不占布局，这里留出等高占位
                  SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
                  SliverPadding(
                    // 顶部留白与左右一致
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
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
                            // 个人中心：用设置里的网盘接口域名拼地址
                            ListTile(
                              leading: const Icon(Icons.user_attributes),
                              title: Text(l10n.userCenter),
                              trailing: const Icon(Icons.open_in_new),
                              onTap: () => _openWeb(
                                context,
                                '${LanzouClient.apiBase}'
                                '/mydisk.php?item=profile&action=mypower',
                                l10n.userCenter,
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
                        // 悬浮底栏时给胶囊让位；普通底栏 / 大屏不需要
                        SizedBox(height: floatingNavTailInset(context)),
                      ]),
                    ),
                  ),
                  // 底栏盖在正文上方（extendBody）时，补足列表末尾留白
                  SliverToBoxAdapter(
                    child: SizedBox(height: shellBottomBarInset(context)),
                  ),
                ],
              ),
            ),
          ),
          // 顶栏浮层：与底栏共用收起进度
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: TopBarOverlay(
              height: headerHeight,
              background: topBarBackgroundColor(context, scheme),
              builder: (context) => AppBar(
                backgroundColor: Colors.transparent,
                scrolledUnderElevation: 0,
                leading: standalone ? const AppBarBackButton() : null,
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
