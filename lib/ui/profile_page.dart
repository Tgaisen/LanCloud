import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter/services.dart';

import '../core/account_state.dart';
import '../core/account_session.dart';
import '../core/api/lanzou_client.dart';
import '../core/backup/backup_sections.dart';
import '../core/navigation_appearance_settings_state.dart';
import '../core/navigation_state.dart';
import '../core/update/update_service.dart';
import '../l10n/l10n.dart';
import 'about_page.dart';
import 'app_icons.dart';
import 'backup_page.dart';
import 'backup_options_page.dart';
import 'common.dart';
import 'login_page.dart';
import 'licenses_page.dart';
import 'm3e.dart';
import 'reduce_motion.dart';
import 'scroll_tint.dart';
import 'settings_page.dart';
import 'update_page.dart';
import 'web_page.dart';

enum _ProfileDeepPage { backupOptions, licenseDetail }

/// 「我的」视图：账号卡片 + 网页版/回收站 + 设置/关于。
/// 既作为底栏视图，也可作为独立路由打开。
class ProfilePage extends riverpod.ConsumerStatefulWidget {
  const ProfilePage({super.key, this.tabIndex});

  /// 外壳中的 page 视图下标；作为独立路由打开时为 null。
  final int? tabIndex;

  @override
  riverpod.ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends riverpod.ConsumerState<ProfilePage>
    with AutomaticKeepAliveClientMixin {
  /// 切到别的视图再切回来时保留本页状态（含列表滚动位置）。
  /// 「我的」在底栏最边上，PageView 只会保活相邻页，不声明就每次都会重建。
  @override
  bool get wantKeepAlive => true;

  /// 列表滚动位置：切到别的视图再切回来时保留（和首页 / 网盘等页面一致）。
  final ScrollController _scroll = ScrollController();

  /// 两栏时左窗格宽度的下限 / 上限；实际宽度按最长条目实测，见
  /// [_listPaneWidthFor]。
  static const double _listPaneWidthMin = 180;
  static const double _listPaneWidthMax = 320;

  /// 右窗格前进 / 后退动画的位移量（占窗格宽度的比例）。
  /// 6% ≈ 原生 shared-axis 的 30dp 量级。
  static const double _paneSlide = 0.06;

  /// 当前选中的详情（默认「账号」，与 M3「父-子」列表-详情一致）。
  _ProfileDetail _detail = _ProfileDetail.account;

  /// 右窗格当前打开的二级页（高级覆盖项 / 备份与恢复 / 开源许可）；
  /// null = 停在类别层。列表-详情的第三层。
  ProfileSubPage? _subPage;

  /// 右窗格第三层详情：备份选项 / 许可详情。
  _ProfileDeepPage? _deepPage;
  String? _deepTitle;

  Completer<BackupOptionsResult?>? _backupOptionsCompleter;
  BackupOptionsController? _backupOptionsController;
  Set<BackupSection> _backupInitialSections = const <BackupSection>{};
  String _backupInitialPassphrase = '';
  Future<bool> Function()? _backupVerifySensitive;
  String _backupConfirmLabel = '';

  LicensePackageGroup? _licensePackage;

  /// 右窗格切换方向：新选中项在列表里更靠下（index 更大）= 前进。
  /// 用来决定 forward/backward 动画从哪一侧滑入。
  bool _forward = true;

  /// 两栏顶栏上的搜索状态：搜索针对当前设置类别，结果在右窗格。
  bool _searching = false;
  final TextEditingController _search = TextEditingController();

  /// 备份与恢复（窗格内）的网络操作进度：显示成顶栏底下那条线。
  final ValueNotifier<bool> _subPageProgress = ValueNotifier<bool>(false);

  /// 右窗格内容的焦点节点：切类别 / 进二级页 / 从二级页返回后，把键盘焦点
  /// 移进右窗格（见 [_focusDetailPane]）。
  /// skipTraversal：它只是落点，不占一个 Tab 位置——Tab 从这里直接进入
  /// 右窗格里的第一个可聚焦控件。
  late final FocusNode _paneFocus = FocusNode(
    debugLabel: 'profile-detail-pane',
  );

  /// 两栏时每个详情窗格各自的滚动控制器：切走再切回时滚动位置不丢。
  /// 键 = (类别, 二级页)：三级内容各自记住自己的滚动位置。
  final Map<Object, ScrollController> _paneScrolls = {};

  /// 当前右窗格内容的滚动控制器键（类别 + 二级页）。
  Object get _paneKey => (_detail, _subPage, _deepPage, _licensePackage?.name);

  /// 右窗格内容的排序值：类别按枚举顺序、二级页比所在类别深一层。
  /// 用来判断前后方向（新值更大 = 前进）。
  int get _paneOrder =>
      _detail.index * 3 +
      (_deepPage != null
          ? 2
          : _subPage != null
          ? 1
          : 0);

  ScrollController _paneScroll(Object key) =>
      _paneScrolls.putIfAbsent(key, () => ScrollController());

  /// 外壳导航状态：用于注册返回处理器。
  late final NavigationState _navigation;

  @override
  void initState() {
    super.initState();
    _navigation = ref.read(navigationStateProvider);
    _subPageProgress.addListener(_onSubPageProgress);
  }

  void _onSubPageProgress() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _subPageProgress.removeListener(_onSubPageProgress);
    _subPageProgress.dispose();
    final backupCompleter = _backupOptionsCompleter;
    if (backupCompleter != null && !backupCompleter.isCompleted) {
      backupCompleter.complete(null);
    }
    _backupOptionsController?.dispose();
    _paneFocus.dispose();
    // 别把已经失效的回调留在外壳上
    if (_navigation.onProfileBack == _handleProfileBack) {
      _navigation.onProfileBack = null;
    }
    for (final controller in _paneScrolls.values) {
      controller.dispose();
    }
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _openWeb(BuildContext context, String url, String title) {
    final account = ref.read(accountStateProvider).store.active;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            WebPage(title: title, url: url, cookie: account?.cookie),
      ),
    );
  }

  /// 点顶栏空白处回到当前窗格顶部（与网盘页一致）。
  void _scrollToTop(ScrollController controller) {
    if (!controller.hasClients) return;
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _select(_ProfileDetail detail) {
    if (_detail == detail) return;
    _discardDeepPage();
    final forward = detail.index * 3 > _paneOrder;
    setState(() {
      _detail = detail;
      // 换类别 = 回到类别层（关掉可能开着的二级页）
      _subPage = null;
      _forward = forward;
      // 切换窗格内容时收掉搜索：搜索只服务于「当前设置类别」
      _searching = false;
      _search.clear();
    });
    _publishProfileBack();
    _showTopBar();
    _focusDetailPane();
  }

  /// 打开设置二级页（高级覆盖项 / 备份与恢复），内容进右窗格。
  void _openSubPage(ProfileSubPage sub) {
    _discardDeepPage();
    setState(() {
      _subPage = sub;
      _forward = true; // 更深一层 = 前进
      _searching = false;
      _search.clear();
    });
    _publishProfileBack();
    _showTopBar();
    _focusDetailPane();
  }

  void _closeSubPage() {
    if (_deepPage != null) {
      _closeDeepPage();
      return;
    }
    if (_subPage == null) return;
    setState(() {
      _subPage = null;
      _forward = false; // 回到上一层 = 后退
    });
    _publishProfileBack();
    _showTopBar();
    _focusDetailPane();
  }

  void _discardDeepPage() {
    final completer = _backupOptionsCompleter;
    final controller = _backupOptionsController;
    if (_deepPage == null && completer == null && controller == null) return;
    _clearDeepPageFields();
    _disposePaneController(controller);
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
  }

  void _clearDeepPageFields() {
    _deepPage = null;
    _deepTitle = null;
    _backupOptionsCompleter = null;
    _backupOptionsController = null;
    _backupInitialSections = const <BackupSection>{};
    _backupInitialPassphrase = '';
    _backupVerifySensitive = null;
    _backupConfirmLabel = '';
    _licensePackage = null;
  }

  void _disposePaneController(BackupOptionsController? controller) {
    if (controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  void _closeDeepPage() {
    if (_deepPage == null) return;
    final completer = _backupOptionsCompleter;
    final controller = _backupOptionsController;
    setState(() {
      _clearDeepPageFields();
      _forward = false;
    });
    _disposePaneController(controller);
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
    _publishProfileBack();
    _showTopBar();
    _focusDetailPane();
  }

  Future<BackupOptionsResult?> _openBackupOptionsInPane(
    BuildContext context, {
    required Set<BackupSection> initialSections,
    required String confirmLabel,
    String? title,
    String initialPassphrase = '',
    Future<bool> Function()? verifySensitive,
  }) {
    _discardDeepPage();
    final completer = Completer<BackupOptionsResult?>();
    final controller = BackupOptionsController();
    setState(() {
      _deepPage = _ProfileDeepPage.backupOptions;
      _deepTitle = title ?? context.l10n.backupOptions;
      _backupOptionsCompleter = completer;
      _backupOptionsController = controller;
      _backupInitialSections = {...initialSections};
      _backupInitialPassphrase = initialPassphrase;
      _backupVerifySensitive = verifySensitive;
      _backupConfirmLabel = confirmLabel;
      _licensePackage = null;
      _forward = true;
    });
    _publishProfileBack();
    _showTopBar();
    _focusDetailPane();
    return completer.future;
  }

  void _completeBackupOptions(BackupOptionsResult result) {
    final completer = _backupOptionsCompleter;
    final controller = _backupOptionsController;
    if (completer == null) return;
    setState(() {
      _clearDeepPageFields();
      _forward = false;
    });
    _disposePaneController(controller);
    if (!completer.isCompleted) completer.complete(result);
    _publishProfileBack();
    _showTopBar();
    _focusDetailPane();
  }

  void _openLicensePackage(LicensePackageGroup package) {
    setState(() {
      _deepPage = _ProfileDeepPage.licenseDetail;
      _deepTitle = package.name;
      _licensePackage = package;
      _forward = true;
    });
    _publishProfileBack();
    _showTopBar();
    _focusDetailPane();
  }

  /// 切窗格内容时把（可能已被滚走的）顶栏调出来：
  /// 「滑动时收起顶栏」开着时，否则新视图会带着收起的顶栏出现，
  /// 用户看不到标题 / 搜索 / 返回。
  void _showTopBar() {
    _navigation.animateBarsHide(0, reduceMotion: reduceMotionOf(context));
  }

  /// 右窗格换了内容之后，把键盘焦点带进右窗格：列表-详情布局里内容换了焦点
  /// 不能留在左窗格，否则键盘用户得先穿过左窗格剩下的条目才能到右边。
  ///
  /// 读屏播报不在这里做：右窗格内容外面挂了 liveRegion 语义（见
  /// [_buildTwoPane]），念什么、什么时候念由 TalkBack 自己按它那一版的逻辑
  /// 决定（引擎也提示过 announceForAccessibility 在 Android 上已废弃、应改用
  /// 语义属性）。Flutter 也没有「应用主动移动读屏焦点」的 API（dart:ui 里只有
  /// 入站的 SemanticsAction.focus / didGainAccessibilityFocus），所以读屏焦点
  /// 只能由用户自己滑过去。
  void _focusDetailPane() {
    _paneFocus.requestFocus();
  }

  /// 详情（账号管理 / 设置某类别 / 关于）的条目文案。
  String _detailLabel(AppLocalizations l10n, _ProfileDetail detail) =>
      detail.settingsCategory?.label(l10n) ??
      switch (detail) {
        _ProfileDetail.about => l10n.about,
        _ProfileDetail.update => l10n.update,
        _ => l10n.accountManagement,
      };

  /// 「更新」条目的副标题：有效检测结果里发现新版本时显示「检测到更新」。
  String? _updateSubtitle(BuildContext context, UpdateStatus status) =>
      status == UpdateStatus.available
      ? context.l10n.updateDetectedSubtitle
      : null;

  void _startSearch() {
    setState(() => _searching = true);
    _publishProfileBack();
  }

  void _exitSearch() {
    if (!_searching) return;
    setState(() {
      _searching = false;
      _search.clear();
    });
    _publishProfileBack();
  }

  /// 让外壳的返回键先落在本页（退出搜索 / 关闭二级设置页）：
  /// 与网盘页处理「返回上一级 / 退出搜索」是同一套机制
  ///（见 NavigationState.onProfileBack）。
  void _publishProfileBack() {
    final active =
        widget.tabIndex != null &&
        (_searching || _subPage != null || _deepPage != null);
    _navigation.onProfileBack = active ? _handleProfileBack : null;
  }

  /// 返回键：搜索 > 二级页 > 交给外壳（回默认视图）。
  Future<bool> _handleProfileBack() async {
    if (_searching) {
      _exitSearch();
      return true;
    }
    if (_deepPage != null) {
      _closeDeepPage();
      return true;
    }
    if (_subPage != null) {
      _closeSubPage();
      return true;
    }
    return false;
  }

  /// 右窗格当前内容的标题（顶栏标题，也是读屏朗读的文案）：
  /// 二级页用二级页名、设置类别用类别名、账号 / 关于用条目名。
  ///
  /// 类别用类别名而不是「设置」：单栏态 push 出来的类别页标题就是类别名
  /// （见 SettingsCategoryPage），两栏态对齐后读屏念顶栏标题才有信息量。
  String _paneTitle(AppLocalizations l10n) {
    final deepTitle = _deepTitle;
    if (deepTitle != null) return deepTitle;
    final sub = _subPage;
    if (sub != null) return sub.label(l10n);
    return _detailLabel(l10n, _detail);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求
    final appearance = ref.watch(navigationAppearanceSettingsStateProvider);
    return ListenableBuilder(
      listenable: appearance.revision,
      builder: (context, _) =>
          _buildPage(context, appearance.hideTopBar, _navigation),
    );
  }

  Widget _buildPage(
    BuildContext context,
    bool hideTopBar,
    NavigationState navigation,
  ) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final headerHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final standalone = !(ModalRoute.of(context)?.isFirst ?? true);
    final wide = MediaQuery.sizeOf(context).width >= kProfileTwoPaneBreakpoint;
    // 单栏没有搜索入口（各二级页自带）：从两栏缩到单栏时把残留状态清掉
    if (!wide && _searching) {
      _searching = false;
      _search.clear();
    }
    // 顶栏空白处点击：滚动当前布局正在用的那个滚动视图
    final topScroll = wide ? _paneScroll(_paneKey) : _scroll;
    // 两栏时左窗格宽度按当前语言的实测最长条目算（单栏用不到，给 0）
    final paneWidth = wide ? _listPaneWidthFor(context) : 0.0;

    return Scaffold(
      // 大屏外壳里的页面：背景交给外壳的圆角卡片；
      // 独立打开的大屏页面（非外壳）铺导航区色，与两窗格之间的底色一致
      backgroundColor: transparentPageBackground(context)
          ? Colors.transparent
          : (isLargeLayout(context) ? scheme.surfaceContainer : null),
      // 桌面端键盘：Esc 走 Flutter 的默认快捷键映射（Esc → DismissIntent，
      // 由 WidgetsApp 提供），这里用官方的 Actions/DismissIntent 接——
      // M3 的 Escape 语义是「关闭 / 移除焦点 / 清除选择」。弹窗、菜单自带更近
      // 的 DismissAction，自动优先于这里；没有可关的东西时这里是空操作。
      body: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              unawaited(_handleProfileBack());
              return null;
            },
          ),
        },
        child: Stack(
          children: [
            if (wide)
              _buildTwoPane(
                context,
                navigation,
                headerHeight,
                paneWidth,
                hideTopBar,
              )
            else
              _buildSinglePane(context, navigation, headerHeight, hideTopBar),
            // 顶栏浮层：与底栏共用收起进度
            Positioned(
              // 两栏时顶栏只盖在右卡片那一列上（内容 + 底色）：
              // 左窗格是导航区，整条都不被顶栏覆盖
              left: paneWidth,
              right: 0,
              top: 0,
              child: TopBarOverlay(
                height: headerHeight,
                background: topBarBackgroundColor(context, scheme),
                // 点顶栏空白处回到列表顶部（按钮自行响应，不会误触）
                builder: (context) {
                  final bar = AppBar(
                    backgroundColor: Colors.transparent,
                    scrolledUnderElevation: 0,
                    // 优先级：搜索时「关闭搜索」> 二级页返回 > 独立页返回
                    leading: _searching
                        ? IconButton(
                            tooltip: l10n.closeSearch,
                            icon: const Icon(Icons.close),
                            onPressed: _exitSearch,
                          )
                        : (_subPage != null || _deepPage != null)
                        ? AppBarBackButton(onPressed: _closeSubPage)
                        : (standalone ? const AppBarBackButton() : null),
                    // 两栏：标题跟随右窗格（账号 / 设置 / 二级页 / 关于），
                    // 搜索框顶替标题；单栏：保持「我的」（搜索入口在各二级页里）
                    title: wide
                        ? AppBarSearchSwitcher(
                            searching: _searching,
                            // 读屏：标题自己就是 live region——右窗格换内容时
                            // 标题跟着换，TalkBack 按它那一版的逻辑念标题
                            //（不自己发 announcement、也不加「右侧内容」这类
                            // 自造文案；引擎也提示过 Android 上应改用语义属性）。
                            title: Semantics(
                              liveRegion: true,
                              child: Text(_paneTitle(l10n)),
                            ),
                            searchField: TextField(
                              controller: _search,
                              autofocus: true,
                              decoration: InputDecoration(
                                hintText: l10n.searchSettings,
                                border: InputBorder.none,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          )
                        : Text(l10n.tabProfile),
                    actions: _paneActions(l10n, wide),
                    // 备份与恢复（窗格内）网络操作时，顶栏底下显示进度线
                    bottom:
                        _subPage == ProfileSubPage.backup &&
                            _subPageProgress.value
                        ? kBackupProgressBar
                        : null,
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _scrollToTop(topScroll),
                    child: bar,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _paneActions(AppLocalizations l10n, bool wide) {
    if (!wide) return const <Widget>[];
    final backupController = _backupOptionsController;
    if (_deepPage == _ProfileDeepPage.backupOptions &&
        backupController != null) {
      return [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ListenableBuilder(
            listenable: backupController,
            builder: (context, _) => TextButton(
              onPressed: backupController.canConfirm
                  ? backupController.confirm
                  : null,
              child: Text(_backupConfirmLabel),
            ),
          ),
        ),
      ];
    }
    if (!_searching &&
        _subPage == null &&
        _deepPage == null &&
        _detail.settingsCategory != null) {
      return [
        IconButton(
          tooltip: l10n.searchSettings,
          icon: const Icon(Icons.search),
          onPressed: _startSearch,
        ),
      ];
    }
    return const <Widget>[];
  }

  /// 单栏（手机 / 窄窗）：账号 + 设置各大类 + 关于；点类别进入二级页
  /// （与 M3 一致：单栏下选中项离开列表、以页面承载详情）。
  Widget _buildSinglePane(
    BuildContext context,
    NavigationState navigation,
    double headerHeight,
    bool hideTopBar,
  ) {
    return BodySideInset(
      child: ScrollTint(
        hideDistance: headerHeight,
        readBarsHidden: () => navigation.topBarHide.value,
        onBarsHidden: hideTopBar ? navigation.setTopBarHideFromScroll : null,
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
                padding: kM3eSectionPagePadding,
                // 整块布局：避免懒布局估算导致滚动条滑块抖动（见 SliverColumn）
                sliver: SliverColumn(children: _singlePaneChildren(context)),
              ),
              // 底栏盖在正文上方（extendBody）时，补足列表末尾留白
              SliverToBoxAdapter(
                child: SizedBox(height: shellBottomBarInset(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _singlePaneChildren(BuildContext context) {
    final l10n = context.l10n;
    return [
      // 组 1：账号（分组小标题 + 信息卡 + 网页版 / 个人中心 / 回收站）
      M3eSectionHeader(l10n.accountTitle),
      SegmentedList(
        children: [
          ProfileAccountTile(
            onSwitchAccount: () => _showAccountSwitcher(context),
          ),
          ..._webLinkTiles(context),
        ],
      ),
      // 组 2：设置（分组小标题 + 5 个大类）
      M3eSectionHeader(l10n.settings),
      SegmentedList(
        children: [
          for (final category in SettingsCategory.values)
            ListTile(
              leading: Icon(category.icon),
              title: Text(category.label(l10n)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsCategoryPage(category: category),
                ),
              ),
            ),
        ],
      ),
      // 组 3：应用（分组小标题 + 更新 / 关于）
      M3eSectionHeader(l10n.appSection),
      SegmentedList(
        children: [
          // 自动检测到新版本时在副标题引导用户进入更新页
          riverpod.Consumer(
            builder: (context, ref, _) {
              final subtitle = _updateSubtitle(
                context,
                ref.watch(updateStatusProvider),
              );
              return ListTile(
                leading: const Icon(Icons.cloud_done),
                title: Text(l10n.update),
                subtitle: subtitle == null ? null : Text(subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const UpdatePage()),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.about),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
          ),
        ],
      ),
    ];
  }

  /// 两栏时的左窗格宽度：按「当前语言 + 文字缩放」实测最长条目，而不是写死。
  ///
  /// 中英文条目长度差得多（中文最长 5 个字，英文 “Notifications &
  /// reminders”），写死 280dp 在中文下会留出大片空白。测量用的样式和文字
  /// 缩放与条目实际渲染完全一致（labelLarge + MediaQuery.textScaler），所以
  /// 量出来的就是「刚好放得下最长条目一格」的宽度。
  ///
  /// 上下限只作护栏：下限避免窄语言（或将来更短的文案）把窗格挤成一条缝
  /// ——M3 展开导航栏给的 220–360dp 是含 FAB / 菜单 / 徽标的导航栏容器，
  /// 这里是列表性质的选择条目，按内容取更合适；上限避免长语言把详情窗格
  /// 挤压得太小。
  double _listPaneWidthFor(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);

    double measure(String text, TextStyle? style) => (TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout()).width;

    // 条目固定占位：左右外边距 16×2 + 指示器内边距 16×2 + 图标 24 +
    // 图标与文字的间距 8
    const itemChrome = 16.0 + 16.0 + 16.0 + 16.0 + 24.0 + 8.0;
    var width = 0.0;
    for (final label in [
      l10n.accountManagement,
      for (final category in SettingsCategory.values) category.label(l10n),
      l10n.update,
      l10n.about,
    ]) {
      final needed = itemChrome + measure(label, theme.textTheme.labelLarge);
      if (needed > width) width = needed;
    }
    // 分组小标题（账号 / 设置 / 应用）也要放得下：左缩进 32 + 右侧 16
    for (final label in [l10n.accountTitle, l10n.settings, l10n.appSection]) {
      final needed = 32.0 + 16.0 + measure(label, theme.textTheme.titleSmall);
      if (needed > width) width = needed;
    }
    // +1 是亚像素余量：别让最长的那条正好卡在换行边界上
    return (width + 1).clamp(_listPaneWidthMin, _listPaneWidthMax).toDouble();
  }

  /// 两栏（≥840dp）：左窗格 = 账号 / 设置 5 大类 / 关于（父），
  /// 右窗格 = 选中项的详情（子），默认选中账号。
  Widget _buildTwoPane(
    BuildContext context,
    NavigationState navigation,
    double headerHeight,
    double paneWidth,
    bool hideTopBar,
  ) {
    // 右窗格内容身份 = (类别, 二级页)：二级页进出同样走滑动切换
    final switcherKey = ValueKey(_paneKey);
    return BodySideInset(
      child: Padding(
        // 独立页面（不在外壳里）时让开系统导航栏；外壳里的卡片已经让过位
        padding: EdgeInsets.only(bottom: shellBottomBarInset(context)),
        // 两窗格之间的“底”用导航区色（M3：窗格=surface、导航区=
        // surfaceContainer）。两张窗格卡片和外壳的内容卡片占同一个矩形
        //（左边贴侧栏，右/下由外壳统一让开 8dp），不额外再缩一圈。
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: paneWidth,
                // 左窗格不做卡片：直接坐在导航区底色上（类似 navigation
                // rail / drawer），只有选中行用次级容器色高亮
                // 键盘：M3 导航栏的语义是「Tab / 方向键在交互元素间移动、
                // Enter / Space 选中」，这里把 ↑ / ↓ 映射成焦点移动。
                // 只包住左窗格：右窗格里的方向键（滑杆、列表）不受影响
                child: Shortcuts(
                  shortcuts: const <ShortcutActivator, Intent>{
                    SingleActivator(LogicalKeyboardKey.arrowDown):
                        NextFocusIntent(),
                    SingleActivator(LogicalKeyboardKey.arrowUp):
                        PreviousFocusIntent(),
                  },
                  // 焦点在窗格内按阅读顺序移动，不窜到右窗格
                  child: FocusTraversalGroup(
                    child: CustomScrollView(
                      controller: _scroll,
                      slivers: [
                        // 左窗格是导航区、不被顶栏覆盖：只让开状态栏，
                        // 再留一点呼吸位（不然横屏无状态栏时几乎贴着屏幕顶边）
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: MediaQuery.paddingOf(context).top + 4,
                          ),
                        ),
                        SliverPadding(
                          // 左右留白由条目自己承担（16dp 指示器起点）；
                          // 上下收到 6 / 12：三条分组小标题加进来后，整列要在默认
                          // 窗口高度里放得下（否则最后一条会被视口裁掉一截）
                          padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
                          // 整块布局：避免懒布局估算导致滚动条滑块抖动
                          //（见 SliverColumn）
                          sliver: SliverColumn(
                            children: _listPaneChildren(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 两窗格之间不另留间距：左窗格条目自带左右 16dp 内边距
              //（选中指示器离窗格边缘 16dp），再留一档就是双重边距。
              // M3 的窗格间距（24dp）假设窗格内容铺满整个窗格，这里不适用。
              Expanded(
                // 左窗格（导航区）通到窗口底边；右卡片照旧让开正文卡片
                // 底部那 8dp（独立页面外面已经套了卡片，helper 返回 0）
                child: Padding(
                  padding: EdgeInsets.only(bottom: shellBodyCardGap(context)),
                  child: ValueListenableBuilder<double>(
                    valueListenable: navigation.topBarHide,
                    builder: (context, hide, content) {
                      final t = hideTopBar ? hide.clamp(0.0, 1.0) : 0.0;
                      return Stack(
                        children: [
                          // 卡片底：顶边贴着顶栏下沿（静止时圆角完整露出），
                          // 顶栏收起时跟着上移——和外壳内容卡片同一节奏。
                          // 内容层不跟着动（滚动仍 1:1），避免两倍阻尼。
                          Positioned(
                            left: 0,
                            right: 0,
                            top: headerHeight * (1 - t),
                            bottom: 0,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: ColoredBox(
                                color: Theme.of(context)
                                    .scaffoldBackgroundColor,
                              ),
                            ),
                          ),
                          Positioned.fill(child: content!),
                        ],
                      );
                    },
                    child: ScrollTint(
                      hideDistance: headerHeight,
                      readBarsHidden: () => navigation.topBarHide.value,
                      onBarsHidden: hideTopBar
                          ? navigation.setTopBarHideFromScroll
                          : null,
                      // 切换详情（账号 / 各设置类别 / 二级页 / 关于）：
                      // forward/backward 式滑动 + 淡入淡出——在列表里往下选
                      // 或进二级页 = 前进（新内容从右侧滑入、旧内容向左淡出），
                      // 往上选或返回则相反。
                      // 时长取规范里「起止都在屏内」的 Standard 300ms。
                      // 外面包的 Focus 是「右窗格内容的焦点落点」：切类别 /
                      // 进二级页后键盘焦点移到这里（见 _focusDetailPane），
                      // skipTraversal：它不占 Tab 位置，Tab 直接进新内容
                      child: Focus(
                        focusNode: _paneFocus,
                        skipTraversal: true,
                        child: AnimatedSwitcher(
                          duration: reduceMotionOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 300),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                                fit: StackFit.expand,
                                children: [...previousChildren, ?currentChild],
                              ),
                          transitionBuilder: (child, animation) {
                            final incoming = child.key == switcherKey;
                            final slide = Offset(
                              _forward ? _paneSlide : -_paneSlide,
                              0,
                            );
                            // 新内容从 dx 侧滑入；旧内容反向滑出
                            //（AnimatedSwitcher 对旧内容反向播放同一段动画）
                            return SlideTransition(
                              position: Tween<Offset>(
                                begin: incoming ? slide : -slide,
                                end: Offset.zero,
                              ).animate(animation),
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            );
                          },
                          child: KeyedSubtree(
                            key: switcherKey,
                            child: _buildDetailPane(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _listPaneChildren(BuildContext context) {
    final l10n = context.l10n;
    // 左窗格按 M3「展开导航栏」组织：条目之间 4dp 间距（collapsed rail
    // 的 ItemVerticalSpace 量级），每个分组前有一条小标题
    //（账号 / 设置 / 应用），小标题自身的内边距承担分组留白。
    final children = <Widget>[
      // 组 1：账号（分组小标题 + 账号管理）
      _RailSectionLabel(l10n.accountTitle),
      _PaneTile(
        icon: Icons.person_outline,
        label: l10n.accountManagement,
        selected: _detail == _ProfileDetail.account,
        onTap: () => _select(_ProfileDetail.account),
      ),
      // 组 2：设置（分组小标题 + 5 个大类）
      _RailSectionLabel(l10n.settings),
      for (final category in SettingsCategory.values)
        _PaneTile(
          icon: category.icon,
          label: category.label(l10n),
          selected: _detail.settingsCategory == category,
          onTap: () => _select(_ProfileDetail.ofCategory(category)),
        ),
      // 组 3：应用（分组小标题 + 更新 / 关于）
      _RailSectionLabel(l10n.appSection),
      // 自动检测到新版本时在副标题引导用户进入更新页
      riverpod.Consumer(
        builder: (context, ref, _) => _PaneTile(
          icon: Icons.cloud_done,
          label: l10n.update,
          subtitle: _updateSubtitle(context, ref.watch(updateStatusProvider)),
          selected: _detail == _ProfileDetail.update,
          onTap: () => _select(_ProfileDetail.update),
        ),
      ),
      _PaneTile(
        icon: Icons.info_outline,
        label: l10n.about,
        selected: _detail == _ProfileDetail.about,
        onTap: () => _select(_ProfileDetail.about),
      ),
    ];
    return [
      for (var i = 0; i < children.length; i++) ...[
        children[i],
        if (i != children.length - 1) const SizedBox(height: 4),
      ],
    ];
  }

  Widget _buildDetailPane(BuildContext context) {
    final deep = _deepPage;
    if (deep == _ProfileDeepPage.backupOptions) {
      final controller = _backupOptionsController;
      if (controller == null) return const SizedBox.shrink();
      return _paneScrollView(
        context,
        controller: _paneScroll(_paneKey),
        children: [
          BackupOptionsPage(
            initialSections: _backupInitialSections,
            confirmLabel: _backupConfirmLabel,
            initialPassphrase: _backupInitialPassphrase,
            verifySensitive: _backupVerifySensitive,
            embedded: true,
            controller: controller,
            onResult: _completeBackupOptions,
          ),
        ],
      );
    }
    if (deep == _ProfileDeepPage.licenseDetail) {
      final package = _licensePackage;
      if (package == null) return const SizedBox.shrink();
      return _paneScrollView(
        context,
        controller: _paneScroll(_paneKey),
        children: [LicenseDetailContent(package: package)],
        topPadding: 16,
      );
    }
    // 第三层：二级页（高级覆盖项 / 备份与恢复 / 开源许可）
    final sub = _subPage;
    if (sub != null) {
      final topPadding = sub == ProfileSubPage.backup ? 8.0 : 16.0;
      final loadingMinHeight = math.max(
        0.0,
        MediaQuery.sizeOf(context).height -
            MediaQuery.paddingOf(context).top -
            kToolbarHeight -
            topPadding -
            kM3eSectionPagePadding.bottom,
      );
      return _paneScrollView(
        context,
        controller: _paneScroll(_paneKey),
        children: [
          switch (sub) {
            ProfileSubPage.advanced => const AdvancedContent(),
            ProfileSubPage.backup => BackupContent(
              progress: _subPageProgress,
              backupOptionsOpener: _openBackupOptionsInPane,
            ),
            ProfileSubPage.licenses => LicensesContent(
              onOpenPackage: _openLicensePackage,
              loadingMinHeight: loadingMinHeight,
            ),
          },
        ],
        topPadding: topPadding,
      );
    }
    final detail = _detail;
    final category = detail.settingsCategory;
    if (category != null) {
      return SettingsCategoryPage(
        category: category,
        embedded: true,
        searching: _searching,
        query: _search.text,
        scrollController: _paneScroll(_paneKey),
        onSwitchCategory: (target) =>
            _select(_ProfileDetail.ofCategory(target)),
        onOpenSubPage: _openSubPage,
      );
    }
    if (detail == _ProfileDetail.about) {
      return _paneScrollView(
        context,
        controller: _paneScroll(_paneKey),
        children: [
          AboutContent(
            onOpenLicenses: () => _openSubPage(ProfileSubPage.licenses),
          ),
        ],
      );
    }
    if (detail == _ProfileDetail.update) {
      return _paneScrollView(
        context,
        controller: _paneScroll(_paneKey),
        children: [const UpdateContent()],
      );
    }
    return _paneScrollView(
      context,
      controller: _paneScroll(_paneKey),
      children: [
        SegmentedList(
          children: [
            ProfileAccountTile(
              onSwitchAccount: () => _showAccountSwitcher(context),
            ),
            ..._webLinkTiles(context),
          ],
        ),
      ],
      topPadding: 16,
    );
  }

  /// 详情窗格里的滚动视图（快速滑动条 + 整块布局，与设置页嵌入形态一致）。
  Widget _paneScrollView(
    BuildContext context, {
    required ScrollController controller,
    required List<Widget> children,
    double topPadding = 8,
  }) {
    // 顶栏是「我的」页的浮层：正文顶上留出等高占位（与其它页一致），
    // 顶栏收起时随内容滚走；滑块也不要从顶栏下面露头。
    final headerHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return FastScrollbar(
      controller: controller,
      padding: EdgeInsets.only(
        top: headerHeight,
        bottom: shellBottomBarInset(context),
      ),
      child: CustomScrollView(
        controller: controller,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
          SliverPadding(
            padding: kM3eSectionPagePadding.copyWith(top: topPadding),
            // 整块布局：避免懒布局估算导致滚动条滑块抖动（见 SliverColumn）
            sliver: SliverColumn(children: children),
          ),
        ],
      ),
    );
  }

  /// 网页版 / 个人中心 / 回收站三个网页入口（单栏与详情窗格共用）。
  List<Widget> _webLinkTiles(BuildContext context) {
    final l10n = context.l10n;
    return [
      ListTile(
        leading: const Icon(Icons.public),
        title: Text(l10n.webManagement),
        trailing: const Icon(Icons.open_in_new),
        onTap: () =>
            _openWeb(context, LanzouClient.mydiskUrl, l10n.webManagement),
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
        leading: const Icon(Icons.restore_from_trash_outlined),
        title: Text(l10n.recycleBin),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => _openWeb(
          context,
          '${LanzouClient.mydiskUrl}?item=recycle',
          l10n.recycleBin,
        ),
      ),
    ];
  }

  Future<void> _showAccountSwitcher(BuildContext context) async {
    final accountState = ref.read(accountStateProvider);
    final session = ref.read(accountSessionProvider);
    final accounts = accountState.store.accounts;
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
              for (final account in accounts)
                M3ePickTile(
                  label: account.nickname.isEmpty
                      ? l10n.accountUid(account.uid)
                      : account.nickname,
                  subtitle: l10n.uidLabel(account.uid),
                  selected: account.uid == accountState.store.activeUid,
                  singleSelect: true,
                  onTap: () async {
                    Navigator.of(context).pop();
                    await session.switchAccount(account.uid);
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
                  final uid = accountState.store.activeUid;
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
    final session = ref.read(accountSessionProvider);
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
    await session.removeAccount(uid, clearData: clearData);
  }
}

/// 账号信息卡（单栏与两栏详情窗格共用）；只订阅账号摘要字段。
class ProfileAccountTile extends riverpod.ConsumerWidget {
  const ProfileAccountTile({super.key, required this.onSwitchAccount});

  final VoidCallback onSwitchAccount;

  @override
  Widget build(BuildContext context, riverpod.WidgetRef ref) {
    final accountState = ref.watch(accountStateProvider);
    return ListenableBuilder(
      listenable: accountState,
      builder: (context, _) {
        final l10n = context.l10n;
        final account = accountState.store.active;
        final snapshot = (
          signedIn: account != null,
          uid: accountState.store.activeUid ?? '',
          nickname: account?.nickname ?? '',
          level: account?.levelLabel ?? '',
          free: account?.isFreeTier ?? true,
        );
        final name = snapshot.nickname.isNotEmpty
            ? snapshot.nickname
            : snapshot.uid;
        return ListTile(
          // 头像里的首字母是装饰：账号名 / 账号在标题与副标题里，读屏跳过它。
          leading: ExcludeSemantics(
            child: CircleAvatar(
              child: Text(name.isEmpty ? '?' : name.substring(0, 1)),
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  !snapshot.signedIn
                      ? l10n.notLoggedIn
                      : snapshot.nickname.isEmpty
                      ? l10n.accountUid(snapshot.uid)
                      : snapshot.nickname,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 会员等级（网页版个人中心截取）；「普」
              //（含还没取到的情况）不显示，开通会员才有卡片。
              if (snapshot.signedIn && !snapshot.free) ...[
                const SizedBox(width: 8),
                _LevelChip(level: snapshot.level),
              ],
            ],
          ),
          subtitle: Text(l10n.uidLabel(snapshot.uid)),
          trailing: FilledButton.tonal(
            onPressed: onSwitchAccount,
            child: Text(l10n.switchAccountShort),
          ),
        );
      },
    );
  }
}

/// 昵称右侧的会员等级小卡片（普通用户「普」不显示）。
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

/// 两栏模式下「我的」右侧详情窗格显示的内容。
enum _ProfileDetail {
  account,
  appearanceLayout,
  behaviorPermissions,
  notificationsReminders,
  transferConnection,
  privacyData,
  update,
  about;

  static _ProfileDetail ofCategory(
    SettingsCategory category,
  ) => switch (category) {
    SettingsCategory.appearanceLayout => _ProfileDetail.appearanceLayout,
    SettingsCategory.behaviorPermissions => _ProfileDetail.behaviorPermissions,
    SettingsCategory.notificationsReminders =>
      _ProfileDetail.notificationsReminders,
    SettingsCategory.transferConnection => _ProfileDetail.transferConnection,
    SettingsCategory.privacyData => _ProfileDetail.privacyData,
  };

  /// 设置类别的详情返回对应大类页；账号 / 关于返回 null。
  SettingsCategory? get settingsCategory => switch (this) {
    _ProfileDetail.appearanceLayout => SettingsCategory.appearanceLayout,
    _ProfileDetail.behaviorPermissions => SettingsCategory.behaviorPermissions,
    _ProfileDetail.notificationsReminders =>
      SettingsCategory.notificationsReminders,
    _ProfileDetail.transferConnection => SettingsCategory.transferConnection,
    _ProfileDetail.privacyData => SettingsCategory.privacyData,
    _ => null,
  };
}

/// 左窗格（展开导航栏）里的一个导航条目。
///
/// **来自 M3（Expanded navigation rail）**：指示器高 56dp、图标 24dp、
/// 图标与文字间距 8dp、条目左侧留白 16dp；选中指示器是 pill（CornerFull），
/// 采用规范允许的「铺满整行」变体（贴近 navigation drawer 的样子）；
/// 选中内容用 on secondary container、未选中用 on surface variant；
/// 选中图标填充、未选中描边。
///
/// 高亮与波纹合并成一个：底色由 [Material] 自己画、波纹（[InkWell]）画在
/// 同一层的上面，并用同一个圆角裁剪——两者的区域、形状完全一致。
///
/// **本应用的设计决定（规范未公布条目文字字号）**：文字用 labelLarge。
class _PaneTile extends StatelessWidget {
  const _PaneTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;

  /// 可选副标题（如「检测到更新」）：在标签下方另起一行，字号更小。
  final String? subtitle;

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      // 条目左右各留 16dp：指示器（高亮 + 波纹）铺满整行但不到边
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
          // 高亮底色和波纹在同一层、同一个圆角里（Material 画底色，
          // InkWell 的波纹盖在它上面，一起被这个圆角裁掉）
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                // 指示器内左侧留白 16dp（图标起点）
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 24,
                      fill: selected ? 1 : 0,
                      color: foreground,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 文字放大时条目纵向增长、最多两行（M3 无障碍要求）
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: foreground,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: selected
                                    ? scheme.onSecondaryContainer.withValues(
                                        alpha: 0.75,
                                      )
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 左窗格里的分组小标题（对应展开导航栏的 section label）。
/// M3 没有公布 section label 的排版规格：这里取 titleSmall + on surface
/// variant、左缩进 16dp（与条目指示器的起点对齐）。
class _RailSectionLabel extends StatelessWidget {
  const _RailSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // 左缩进与条目图标的起点对齐（条目 16dp 外边距 + 指示器内 16dp）；
      // 上 8 / 下 2：分组之间的留白由它承担，收到刚好能分清组
      padding: const EdgeInsets.fromLTRB(32, 8, 16, 2),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
