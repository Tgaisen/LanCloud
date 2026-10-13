import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/api/lanzou_client.dart';
import '../core/data/account_store.dart';
import '../l10n/l10n.dart';
import 'about_page.dart';
import 'app_icons.dart';
import 'common.dart';
import 'login_page.dart';
import 'm3e.dart';
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
        builder: (_) =>
            WebPage(title: title, url: url, cookie: app.activeAccount?.cookie),
      ),
    );
  }

  /// 点顶栏空白处回到列表顶部（与网盘页一致）。
  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
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
      backgroundColor: transparentPageBackground(context)
          ? Colors.transparent
          : null,
      body: Stack(
        children: [
          // 小屏：正文区整体让开左右挖孔 / 侧边导航栏；顶栏（浮层）保持原样
          BodySideInset(
            child: ScrollTint(
              hideDistance: headerHeight,
              readBarsHidden: () => app.topBarHide.value,
              onBarsHidden: app.settings.hideTopBar
                  ? app.setTopBarHideFromScroll
                  : null,
              // 列表快速滑动条（可拖拽）
              child: FastScrollbar(
                controller: _scroll,
                padding: EdgeInsets.only(
                  top: headerHeight,
                  bottom: shellBottomBarInset(context),
                ),
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    // 顶栏不占布局，这里留出等高占位
                    SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
                    SliverPadding(
                      // 顶部留白与左右一致
                      // 底部留白与首页 / 网盘 / 收藏 / 传输保持一致
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                      // 整块布局：避免懒布局估算导致滚动条滑块抖动（见 SliverColumn）
                      sliver: SliverColumn(
                        children: [
                          SegmentedList(
                            children: [
                              ListTile(
                                leading: CircleAvatar(
                                  child: Text(_avatarInitial(account, uid)),
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        account == null
                                            ? l10n.notLoggedIn
                                            : account.nickname.isEmpty
                                            ? l10n.accountUid(uid)
                                            : account.nickname,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // 网页版个人中心截取的用户等级；没取到按「普」
                                    if (account != null) ...[
                                      const SizedBox(width: 8),
                                      _LevelChip(level: account.levelLabel),
                                    ],
                                  ],
                                ),
                                subtitle: Text(l10n.uidLabel(uid)),
                                trailing: FilledButton.tonal(
                                  onPressed: () =>
                                      _showAccountSwitcher(context),
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
                                  LanzouClient.mydiskUrl,
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
                                leading: const Icon(
                                  Icons.restore_from_trash_outlined,
                                ),
                                title: Text(l10n.recycleBin),
                                trailing: const Icon(Icons.open_in_new),
                                onTap: () => _openWeb(
                                  context,
                                  '${LanzouClient.mydiskUrl}?item=recycle',
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
                        ],
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
          ),
          // 顶栏浮层：与底栏共用收起进度
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: TopBarOverlay(
              height: headerHeight,
              background: topBarBackgroundColor(context, scheme),
              // 点顶栏空白处回到列表顶部（按钮自行响应，不会误触）
              builder: (context) => GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _scrollToTop,
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                  leading: standalone ? const AppBarBackButton() : null,
                  title: Text(l10n.tabProfile),
                ),
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
    final l10n = context.l10n;
    await showAppSheet<void>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.switchAccount,
              style: context.m3eEmphasizedTheme.titleLarge,
            ),
          ),
          // 组 1：账号列表 + 添加账号
          SheetListGroup(
            children: [
              for (final account in app.accounts.accounts)
                M3ePickTile(
                  label: account.nickname.isEmpty
                      ? l10n.accountUid(account.uid)
                      : account.nickname,
                  subtitle: l10n.uidLabel(account.uid),
                  selected: account.uid == app.activeUid,
                  singleSelect: true,
                  onTap: () async {
                    Navigator.of(context).pop();
                    await app.switchAccount(account.uid);
                  },
                ),
              M3ePickTile.action(
                label: l10n.addAccount,
                leading: const Icon(Icons.add),
                onTap: () async {
                  Navigator.of(context).pop();
                  await showLoginSheet(context);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 组 2：退出登录单独一组
          SheetListGroup(
            margin: SheetListGroup.endMargin,
            children: [
              M3ePickTile.action(
                label: l10n.logout,
                leading: const Icon(Icons.logout),
                onTap: () {
                  final uid = app.activeUid;
                  Navigator.of(context).pop();
                  if (uid != null) _removeAccount(context, uid);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _removeAccount(BuildContext context, String uid) async {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    var clearData = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.removeAccountTitle),
          // M3 对话框内容边距 24dp；列表组外边距 0，组沿落在 24dp 上
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.removeAccountMessage(uid)),
              const SizedBox(height: 16),
              // 复选行放进列表组（与选择弹窗同一套样式）
              DialogListGroup(
                children: [
                  M3ePickTile(
                    label: l10n.clearUsageData,
                    subtitle: l10n.clearUsageDataSubtitle,
                    selected: clearData,
                    onTap: () => setDialogState(() => clearData = !clearData),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.remove),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await app.removeAccount(uid, clearData: clearData);
  }
}

/// 昵称右侧的用户等级小卡片（例如普通用户的「普」）。
class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level});

  final String level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        level,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSecondaryContainer,
          height: 1.3,
        ),
      ),
    );
  }
}
