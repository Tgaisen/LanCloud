import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/data/app_db.dart';
import '../core/transfer/transfer_manager.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'drive_page.dart';
import 'profile_page.dart';
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
              builder: (_) =>
                  DrivePage(initialFolderId: ref, initialName: name),
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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
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
      body: Stack(
        children: [
          ScrollTint(
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
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => openShareSheet(context),
                        icon: const Icon(Icons.open_in_new),
                        label: Text(l10n.openShareLink),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: Text(
                          running > 0
                              ? l10n.transferringCount(running)
                              : l10n.transferCenter,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: l10n.quickAccess,
                  leading: const Icon(Icons.push_pin_outlined),
                  expanded: _quickExpanded,
                  onToggle: _toggleQuickExpanded,
                  child: _quick.isEmpty
                      ? EmptyHint(
                          icon: Icons.push_pin_outlined,
                          text: l10n.quickAccessHint,
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
                  leading: const Icon(Icons.history),
                  expanded: _recentsExpanded,
                  onToggle: _toggleRecentsExpanded,
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : (_recents.isEmpty
                          ? EmptyHint(
                              icon: Icons.history,
                              text: l10n.noRecent,
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
              ],
            ),
          ),
          // 顶栏浮层：与底栏共用收起进度，切换视图时会下滑出现
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: TopBarOverlay(
              height: headerHeight,
              child: AppBar(
                backgroundColor: Color.lerp(
                  Theme.of(context).colorScheme.surface,
                  Theme.of(context).colorScheme.surfaceContainer,
                  ScrollTint.of(context),
                ),
                scrolledUnderElevation: 0,
                title: Text(l10n.appName),
                actions: [
                  IconButton(
                    tooltip: l10n.openShareLink,
                    icon: const Icon(Icons.link),
                    onPressed: () => openShareSheet(context),
                  ),
                  IconButton(
                    tooltip: l10n.scanComingSoonTooltip,
                    icon: const Icon(Icons.qr_code),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.scanComingSoon)),
                    ),
                  ),
                  // MD3 trailing avatar：圆形头像按钮，打开「我的」弹窗
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 10),
                    child: Material(
                      color: scheme.primaryContainer,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => showProfileSheet(context),
                        child: Tooltip(
                          message: l10n.my,
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: Icon(
                              Icons.person,
                              size: 20,
                              color: scheme.onPrimaryContainer,
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
        ],
      ),
    );
  }
}
