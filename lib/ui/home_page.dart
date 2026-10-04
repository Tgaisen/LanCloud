import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/data/app_db.dart';
import '../core/lanzou_link.dart';
import '../core/transfer/transfer_manager.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'drive_page.dart';
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
  bool _loading = true;
  bool _quickExpanded = true;
  bool _recentsExpanded = true;
  late final AppDb _db;
  final ScrollController _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
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
    context.read<AppController>().activeTab.removeListener(_onActiveTabChanged);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.scanNotLanzou)),
      );
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

  /// 快速访问条目：名称 + 该目录路径，右侧 ⋯ 打开菜单。
  Widget _quickItem(
    BuildContext context,
    AppController app,
    PinItem item, {
    required bool first,
  }) {
    final l10n = context.l10n;
    return Md3ListItem(
      icon: Icons.folder_outlined,
      title: item.name,
      subtitle: item.path,
      trailing: IconButton(
        tooltip: l10n.moreActions,
        icon: const Icon(Icons.more_vert),
        onPressed: () => _showPinMenu(item, first: first),
      ),
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
            leading: const Icon(Icons.push_pin_outlined),
            title: Text(l10n.unpin),
            onTap: () async {
              Navigator.of(context).pop();
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
                topBarHeight: MediaQuery.paddingOf(context).top +
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
          child: ShareFileInfoSheet(
            name: name,
            url: ref,
            pwd: pwd,
          ),
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
    // 窗口比 MD3 弹窗宽度上限还宽时弹窗会居中，两侧用不到系统栏让位
    final fullWidthSheet =
        MediaQuery.sizeOf(context).width <= kModalSheetMaxWidth;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // 通铺整屏时让弹窗窗体整体避开左右挖孔（作用在面板外侧）；
      // 面板内部只再让开底部系统栏，不要把状态栏高度算进弹窗内容
      useSafeArea: fullWidthSheet,
      builder: (sheetContext) => SafeArea(
        top: false,
        // 左右由上面的 useSafeArea 统一处理（SafeArea 默认会带上左右）
        left: false,
        right: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(context.l10n.download),
              onTap: () async {
                Navigator.of(sheetContext).pop();
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
                Navigator.of(sheetContext).pop();
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
        .where((t) =>
            t.status == TransferStatus.running ||
            t.status == TransferStatus.queued)
        .length;
    final headerHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;
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
                          label: l10n.scan,
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
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
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
                            children: [
                              for (var i = 0; i < _quick.length; i++)
                                _quickItem(
                                  context,
                                  app,
                                  _quick[i],
                                  first: i == 0,
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
                            child: Center(child: CircularProgressIndicator()),
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
                                children: [
                                  for (final item in _recents)
                                    Md3ListItem(
                                      icon: item.kind
                                              .toLowerCase()
                                              .contains('folder')
                                          ? Icons.folder_outlined
                                          : iconForFile(item.name),
                                      title: item.name,
                                      subtitle: item.kind.startsWith('share')
                                          ? l10n.sharedContent
                                          : l10n.myDrive,
                                      onTap: () => _openItem(
                                        context,
                                        item.kind,
                                        item.ref,
                                        item.name,
                                        item.pwd,
                                      ),
                                    ),
                                ],
                              )),
                  ),
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
          // 顶栏浮层：与底栏共用收起进度，切换视图时会下滑出现
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
                title: Text(l10n.appName),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
