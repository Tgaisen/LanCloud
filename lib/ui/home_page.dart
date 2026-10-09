import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/data/app_db.dart';
import '../core/lanzou_link.dart';
import '../core/transfer/transfer_manager.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'drive_page.dart';
import 'm3e.dart';
import 'qr_scan.dart';
import 'scroll_tint.dart';
import 'share_file_sheet.dart';
import 'share_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.tabIndex});

  /// 外壳中的 page 视图下标；作为独立路由打开时为 null（不响应切换通知）。
  final int? tabIndex;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  List<RecentItem> _recents = [];
  List<PinItem> _quick = [];

  /// 正在播放删除动画的条目（动画播完再真正删库）
  final Set<String> _removingQuick = {};
  final Set<String> _removingRecents = {};
  bool _loading = true;
  bool _quickExpanded = true;
  bool _recentsExpanded = true;
  late final AppDb _db;

  /// dispose 里不能再读 context（元素正在卸载），控制器在 initState 存下来。
  late final AppController _app;
  final ScrollController _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
    _app = app;
    _db = app.db;
    _quickExpanded = app.settings.quickExpanded;
    _recentsExpanded = app.settings.recentsExpanded;
    _load();
    _db.revision.addListener(_load);
    app.activeTab.addListener(_onActiveTabChanged);
  }

  @override
  void dispose() {
    _db.revision.removeListener(_load);
    _app.activeTab.removeListener(_onActiveTabChanged);
    _scroll.dispose();
    super.dispose();
  }

  /// 切到本视图时刷新本地数据（收藏/最近使用可能已在别处变化）。
  void _onActiveTabChanged() {
    final app = context.read<AppController>();
    if (widget.tabIndex == null) return;
    if (app.activeTab.value == widget.tabIndex) {
      _load();
    }
  }

  /// 识别二维码：底部弹窗选择「拍照获取 / 从相册选取」（都不需要相机权限），
  /// 识别到蓝奏云分享链接后直接打开解析弹窗。
  Future<void> _scanQr() async {
    final l10n = context.l10n;
    final source = await showQrSourceSheet(context);
    if (source == null || !mounted) return;
    final raw = await scanQrFromImage(context, source);
    if (!mounted || raw == null) return;
    final link = LanzouLink.parse(raw);
    if (link == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.scanNotLanzou)));
      return;
    }
    await openShareSheet(context, initialLink: link.url, initialPwd: link.pwd);
  }

  /// 展开 / 折叠「快速访问」，状态记在设置里（重启后保持）。
  Future<void> _toggleQuickExpanded() async {
    final app = context.read<AppController>();
    setState(() => _quickExpanded = !_quickExpanded);
    await app.setQuickExpanded(_quickExpanded);
  }

  Future<void> _toggleRecentsExpanded() async {
    final app = context.read<AppController>();
    setState(() => _recentsExpanded = !_recentsExpanded);
    await app.setRecentsExpanded(_recentsExpanded);
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

  /// 快速访问条目：名称 + 该目录路径，右侧 ⋯ 打开菜单。
  Widget _quickItem(
    BuildContext context,
    AppController app,
    PinItem item, {
    required bool first,
    required int index,
  }) {
    final l10n = context.l10n;
    final removing = _removingQuick.contains(item.ref);
    return Md3ListItem(
      key: ValueKey('quick-${item.ref}'),
      index: index,
      removing: removing,
      icon: Icons.folder_outlined,
      title: item.name,
      subtitle: quickAccessPathLabel(l10n, item),
      trailing: IconButton(
        // 与收藏 / 传输页的 ⋯ 保持一致（紧凑尺寸）
        visualDensity: VisualDensity.standard,
        iconSize: 20,
        tooltip: l10n.moreActions,
        icon: const Icon(Icons.more_vert),
        onPressed: () => _showPinMenu(item, first: first),
      ),
      // 桌面端右键：与 ⋯ 菜单同一套操作
      onSecondaryTap: () => _showPinMenu(item, first: first),
      onTap: () => _openItem(context, 'folder', item.ref, item.name, ''),
    );
  }

  /// 快速访问菜单：取消固定；不在顶部时可以移到顶部。
  Future<void> _showPinMenu(PinItem item, {required bool first}) async {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    await showAppSheet<void>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(l10n.open),
            onTap: () {
              Navigator.of(context).pop();
              _openItem(context, 'folder', item.ref, item.name, '');
            },
          ),
          ListTile(
            leading: const Icon(Icons.keep_off),
            title: Text(l10n.removeFromQuickAccess),
            onTap: () async {
              Navigator.of(context).pop();
              // 先播放删除动画，再真正删库（列表由 db.revision 通知刷新）
              setState(() => _removingQuick.add(item.ref));
              await Future<void>.delayed(const Duration(milliseconds: 220));
              if (!mounted) return;
              await app.db.removePin(item.ref);
            },
          ),
          if (!first)
            ListTile(
              leading: const Icon(Icons.vertical_align_top),
              title: Text(l10n.moveToTop),
              onTap: () async {
                Navigator.of(context).pop();
                await app.db.movePinToTop(item.ref);
              },
            ),
        ],
      ),
    );
  }

  /// 最近使用菜单：打开 / 删除此条记录（与快速访问菜单同款底部弹窗）。
  Future<void> _showRecentMenu(RecentItem item) async {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    await showAppSheet<void>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(l10n.open),
            onTap: () {
              Navigator.of(context).pop();
              _openItem(context, item.kind, item.ref, item.name, item.pwd);
            },
          ),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: Text(l10n.addFavorite),
            onTap: () {
              Navigator.of(context).pop();
              _favoriteRecent(item);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.deleteRecord),
            onTap: () async {
              Navigator.of(context).pop();
              setState(() => _removingRecents.add(item.ref));
              await Future<void>.delayed(const Duration(milliseconds: 220));
              if (!mounted) return;
              await app.db.removeRecent(
                account: app.activeUid ?? '',
                ref: item.ref,
              );
            },
          ),
        ],
      ),
    );
  }

  /// 最近使用条目加入收藏：分享链接直接收藏；网盘文件 / 目录先取分享链接
  /// 再按分享收藏（与网盘页的收藏行为一致）。
  Future<void> _favoriteRecent(RecentItem item) async {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (item.kind) {
        case 'shareFile':
        case 'shareFolder':
          await app.db.addFavorite(
            kind: item.kind,
            name: item.name,
            ref: item.ref,
            pwd: item.pwd,
          );
        case 'folder':
          final client = app.client;
          if (client == null) return;
          final info = await client.shareInfoOfFolder(item.ref);
          await app.db.addFavorite(
            kind: 'shareFolder',
            name: item.name,
            ref: info.url,
            pwd: info.pwd,
          );
        default:
          final client = app.client;
          if (client == null) return;
          final info = await client.shareInfoOfFile(item.ref);
          await app.db.addFavorite(
            kind: 'shareFile',
            name: item.name,
            ref: info.url,
            pwd: info.pwd,
          );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l10n.addedToFavorites)));
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    final uid = app.activeUid ?? '';
    try {
      final recents = await app.db.recents(uid, limit: 6);
      final pins = await app.db.pins(uid);
      if (!mounted) return;
      setState(() {
        _recents = recents;
        _quick = pins;
        _loading = false;
        // 数据已刷新：清理删除动画标记。清早了会让还没从列表消失的条目
        // 反向展开（先上移再下移），所以统一放在这里。
        _removingQuick.clear();
        _removingRecents.clear();
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openItem(
    BuildContext context,
    String kind,
    String ref,
    String name,
    String pwd,
  ) async {
    switch (kind) {
      case 'folder':
        final app = context.read<AppController>();
        if (app.settings.homeFolderOpenMode == 'drive') {
          // 跳转网盘视图并加载到该目录
          app.openFolderInDrive(ref);
        } else {
          await Navigator.of(context).push(
            MaterialPageRoute(
              // 大屏下独立打开的网盘页同样套 MD3E 卡片
              builder: (_) => Md3ePageFrame(
                topBarHeight:
                    MediaQuery.paddingOf(context).top +
                    kToolbarHeight +
                    kDrivePathBarHeight,
                hide: app.topBarHide,
                child: DrivePage(initialFolderId: ref, initialName: name),
              ),
            ),
          );
        }
      case 'file':
        await _showOwnFileActions(context, ref, name);
      case 'shareFile':
        await showAppSheet<void>(
          context,
          child: ShareFileInfoSheet(name: name, url: ref, pwd: pwd),
        );
      case 'shareFolder':
        await openShareSheet(context, initialLink: ref, initialPwd: pwd);
    }
    if (mounted) _load();
  }

  Future<void> _showOwnFileActions(
    BuildContext context,
    String fileId,
    String name,
  ) async {
    final app = context.read<AppController>();
    // 与其它弹窗一致：走统一外壳（MD3E 底部弹窗 + 自适应高度）。
    await showAppSheet<void>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(context.l10n.download),
            onTap: () async {
              Navigator.of(context).pop();
              final client = app.client;
              if (client == null) return;
              try {
                final info = await client.shareInfoOfFile(fileId);
                if (!context.mounted) return;
                await downloadShareFile(
                  context,
                  url: info.url,
                  pwd: info.pwd,
                  fallbackName: name,
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.link_outlined),
            title: Text(context.l10n.copyLink),
            onTap: () async {
              Navigator.of(context).pop();
              final client = app.client;
              if (client == null) return;
              try {
                final info = await client.shareInfoOfFile(fileId);
                if (!context.mounted) return;
                await copyText(
                  context,
                  info.pwd.isEmpty
                      ? info.url
                      : context.l10n.linkWithPassword(info.url, info.pwd),
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.watch<AppController>();
    final transfers = context.watch<TransferManager>();
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final running = transfers.tasks
        .where(
          (t) =>
              t.status == TransferStatus.running ||
              t.status == TransferStatus.queued,
        )
        .length;
    final headerHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;
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
                // 顶栏是浮层：滑块从顶栏下方开始，底部让开底栏
                padding: EdgeInsets.only(
                  top: headerHeight,
                  bottom: shellBottomBarInset(context),
                ),
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    // 顶栏不占布局，这里留出等高占位
                    SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
                    // 入口按钮：横向滚动，左右边距用 padding 实现，
                    // 这样滑到头也不会被裁掉；按钮间距 = 卡片边距（20dp），
                    // 顶部留白与左右一致
                    SliverToBoxAdapter(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExpressiveIconButton(
                              icon: Icons.open_in_new,
                              label: l10n.openLink,
                              onPressed: () => openShareSheet(context),
                            ),
                            const SizedBox(width: 20),
                            ExpressiveIconButton(
                              icon: Icons.qr_code,
                              label: l10n.scanButton,
                              onPressed: _scanQr,
                            ),
                            const SizedBox(width: 20),
                            ExpressiveIconButton(
                              icon: Icons.swap_vert,
                              label: l10n.transferCenter,
                              badge: running > 0 ? '$running' : null,
                              onPressed: () => app.switchTab(2),
                            ),
                            const SizedBox(width: 20),
                            ExpressiveIconButton(
                              icon: Icons.star_border,
                              label: l10n.favorite,
                              onPressed: () => app.switchTab(3),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    SliverPadding(
                      // 底部留白交给最后一个 SectionCard 自带的 16dp
                      //（它内部还带 4dp 分组外边距），与其他页面保持一致
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      // 整块布局：避免懒布局估算导致滚动条滑块抖动（见 SliverColumn）
                      sliver: SliverColumn(
                        children: [
                          SectionCard(
                            title: l10n.quickAccess,
                            expanded: _quickExpanded,
                            onToggle: _toggleQuickExpanded,
                            child: _quick.isEmpty
                                ? SegmentedList(
                                    children: [
                                      EmptyHint(
                                        icon: Icons.push_pin_outlined,
                                        text: l10n.quickAccessHint,
                                      ),
                                    ],
                                  )
                                : SegmentedList(
                                    adaptive: true,
                                    children: [
                                      for (var i = 0; i < _quick.length; i++)
                                        _quickItem(
                                          context,
                                          app,
                                          _quick[i],
                                          first: i == 0,
                                          index: i,
                                        ),
                                    ],
                                  ),
                          ),
                          SectionCard(
                            title: l10n.recent,
                            expanded: _recentsExpanded,
                            onToggle: _toggleRecentsExpanded,
                            child: _loading
                                ? const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(child: M3eLoadingIndicator()),
                                  )
                                : (_recents.isEmpty
                                      ? SegmentedList(
                                          children: [
                                            EmptyHint(
                                              icon: Icons.history,
                                              text: l10n.noRecent,
                                            ),
                                          ],
                                        )
                                      : SegmentedList(
                                          adaptive: true,
                                          children: [
                                            for (
                                              var i = 0;
                                              i < _recents.length;
                                              i++
                                            )
                                              Md3ListItem(
                                                key: ValueKey(
                                                  'recent-${_recents[i].ref}',
                                                ),
                                                index: i,
                                                removing: _removingRecents
                                                    .contains(_recents[i].ref),
                                                icon:
                                                    _recents[i].kind
                                                        .toLowerCase()
                                                        .contains('folder')
                                                    ? Icons.folder_outlined
                                                    : iconForFile(
                                                        _recents[i].name,
                                                      ),
                                                title: _recents[i].name,
                                                subtitle:
                                                    _recents[i].kind.startsWith(
                                                      'share',
                                                    )
                                                    ? l10n.sharedContent
                                                    : l10n.myDrive,
                                                trailing: IconButton(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  iconSize: 20,
                                                  tooltip: l10n.moreActions,
                                                  icon: const Icon(
                                                    Icons.more_vert,
                                                  ),
                                                  onPressed: () =>
                                                      _showRecentMenu(
                                                        _recents[i],
                                                      ),
                                                ),
                                                // 桌面端右键：与 ⋯ 菜单同一套操作
                                                onSecondaryTap: () =>
                                                    _showRecentMenu(
                                                      _recents[i],
                                                    ),
                                                onTap: () => _openItem(
                                                  context,
                                                  _recents[i].kind,
                                                  _recents[i].ref,
                                                  _recents[i].name,
                                                  _recents[i].pwd,
                                                ),
                                              ),
                                          ],
                                        )),
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
          // 顶栏浮层：与底栏共用收起进度，切换视图时会下滑出现
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
                  title: Text(l10n.appName),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 快速访问副标题：显示该文件夹「所在目录」的路径（不含文件夹自身），
/// 例如 根目录/abc/示例 → 根目录/abc；「根目录」按当前语言显示。
///
/// 兼容早期数据：那时 path 存的是「根目录 + 完整路径 + 文件夹自身」，
/// 且「根目录」是固定时语言写死的，这里会识别任意支持语言的写法后剥掉。
String quickAccessPathLabel(AppLocalizations l10n, PinItem item) {
  var segments = item.path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty && isRootLabelSegment(segments.first)) {
    segments = segments.sublist(1);
    if (segments.isNotEmpty && segments.last == item.name) {
      segments = segments.sublist(0, segments.length - 1);
    }
  }
  return [l10n.root, ...segments].join('/');
}

/// 是否是「根目录」在任一支持语言下的写法（旧数据固定的是固定时的语言）。
bool isRootLabelSegment(String segment) => AppLocalizations.supportedLocales
    .any((locale) => lookupAppLocalizations(locale).root == segment);
