import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/data/app_db.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'scroll_tint.dart';
import 'share_file_sheet.dart';
import 'share_page.dart';

/// 收藏视图：独立底栏页，布局与传输页一致（分组 + 多选删除）。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key, this.tabIndex});

  /// 外壳中的 page 视图下标；作为独立路由打开时为 null（不响应切换通知）。
  final int? tabIndex;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  static const _anim = Duration(milliseconds: 200);

  List<FavoriteItem> _folders = [];
  List<FavoriteItem> _files = [];
  bool _loading = true;
  bool _selecting = false;
  final Set<int> _selected = {};

  /// 正在播放删除动画的条目（动画播完再真正删库）
  final Set<int> _removing = {};

  /// 修改后的高亮闪烁计数（值变化触发一次）
  final Map<int, int> _pulse = {};
  final ScrollController _scroll = ScrollController();

  /// 顶栏搜索：与网盘页一致，在当前收藏里按名称过滤。
  final TextEditingController _search = TextEditingController();
  bool _searching = false;
  String _filter = '';

  /// 排序方式：time（收藏时间新到旧，默认）/ name / size。
  String _sort = 'time';

  late final AppDb _db;
  AppController? _app;

  /// 拖拽判定用的探针：当前是否"可见地"处于收藏页（底栏 tab 或独立路由）。
  late final bool Function() _dropProbe = _visibleAsDropTarget;

  bool _visibleAsDropTarget() {
    if (!mounted) return false;
    final app = _app;
    if (app == null) return false;
    final route = ModalRoute.of(context);
    // 被别的页面（例如从收藏打开的子目录）盖住时不算
    if (route != null && !route.isCurrent) return false;
    // 底栏形态：只有当前激活的 tab 才算；独立页面：在最上层就算
    if (route == null || route.isFirst) {
      return widget.tabIndex != null && app.activeTab.value == widget.tabIndex;
    }
    return true;
  }

  /// 长列表的入场动画：首次载入后播一次，之后滑进来的条目直接显示。
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: ListEnterAnimation.duration,
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
    _db = app.db;
    _db.revision.addListener(_load);
    app.activeTab.addListener(_onActiveTabChanged);
    app.addFavoritesProbe(_dropProbe);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = context.read<AppController>();
  }

  @override
  void dispose() {
    _db.revision.removeListener(_load);
    final app = _app;
    if (app != null) {
      app.removeFavoritesProbe(_dropProbe);
      app.activeTab.removeListener(_onActiveTabChanged);
      if (_selecting) {
        app.setSelectionMode(false);
        app.onRequestExitSelection = null;
      }
    }
    _scroll.dispose();
    _search.dispose();
    _enter.dispose();
    super.dispose();
  }

  /// 切到本视图时重新读取收藏（可能在别处新增/删除了收藏）。
  void _onActiveTabChanged() {
    final app = _app;
    if (app == null || widget.tabIndex == null) return;
    if (app.activeTab.value == widget.tabIndex) _load();
  }

  Future<void> _load() async {
    try {
      final all = await _db.favorites();
      if (!mounted) return;
      setState(() {
        _folders = all.where((f) => f.kind == 'shareFolder').toList();
        _files = all.where((f) => f.kind == 'shareFile').toList();
        _loading = false;
        // 数据已刷新：清掉删除动画标记（清早了会让还没消失的条目反向展开）
        _removing.clear();
      });
      if (!_enter.isAnimating && _enter.value == 0) _enter.forward();
    } catch (_) {
      // 读取失败时保持已有内容
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 当前可见（过滤 + 排序后）的收藏：全选 / 反选只作用于可见项。
  List<FavoriteItem> get _items => [..._visible(_folders), ..._visible(_files)];

  // -------------------------------------------------------------- 搜索 / 排序

  void _exitSearch() {
    setState(() {
      _searching = false;
      _filter = '';
      _search.clear();
    });
  }

  /// 过滤 + 排序：默认按收藏时间新到旧（数据库本身就是这个顺序）。
  List<FavoriteItem> _visible(List<FavoriteItem> source) {
    final query = _filter.trim().toLowerCase();
    final items = query.isEmpty
        ? List<FavoriteItem>.of(source)
        : source
              .where(
                (item) =>
                    item.name.toLowerCase().contains(query) ||
                    item.title.toLowerCase().contains(query),
              )
              .toList();
    switch (_sort) {
      case 'name':
        items.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case 'size':
        items.sort(
          (a, b) => lzSizeToBytes(b.size).compareTo(lzSizeToBytes(a.size)),
        );
      default:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return items;
  }

  /// 顶栏 ⋯ 菜单：排序（时间 / 名称 / 大小）、多选、添加收藏。
  Future<void> _showMenu() async {
    final l10n = context.l10n;
    var sort = _sort;
    await showAppSheet<void>(
      context,
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.sort,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ConnectedSegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'time',
                          label: Text(l10n.sortTime),
                        ),
                        ButtonSegment(
                          value: 'name',
                          label: Text(l10n.sortName),
                        ),
                        ButtonSegment(
                          value: 'size',
                          label: Text(l10n.sortSize),
                        ),
                      ],
                      selected: {sort},
                      onSelectionChanged: (values) {
                        setSheetState(() => sort = values.first);
                        setState(() => _sort = values.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.done_all),
              title: Text(l10n.multiSelect),
              onTap: () {
                Navigator.of(context).pop();
                _enterSelection();
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: Text(l10n.addFavorite),
              onTap: () {
                Navigator.of(context).pop();
                // 打开「打开链接」弹窗，识别出文件（夹）后直接加入收藏
                openShareSheet(context, addFavoriteOnResolve: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 多选

  void _enterSelection({int? id}) {
    final wasSelecting = _selecting;
    if (!_selecting) {
      // 其它页面可能正处于多选：先退出，避免两处状态打架
      context.read<AppController>().onRequestExitSelection?.call();
    }
    setState(() {
      _selecting = true;
      if (id != null) _selected.add(id);
    });
    final app = context.read<AppController>();
    app.onRequestExitSelection = _exitSelection;
    app.setSelectionMode(true);
    if (!wasSelecting) announceEnteredMultiSelect(context);
  }

  void _exitSelection() {
    if (!_selecting) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    final app = context.read<AppController>();
    app.onRequestExitSelection = null;
    app.setSelectionMode(false);
  }

  void _toggleSelected(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
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

  void _selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll(_items.map((item) => item.id));
    });
  }

  void _invertSelection() {
    setState(() {
      for (final item in _items) {
        if (!_selected.remove(item.id)) _selected.add(item.id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final l10n = context.l10n;
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.favoriteDeleteConfirmTitle),
        content: Text(l10n.favoriteDeleteConfirmMessage(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final ids = _selected.toList();
    _exitSelection();
    // 批量删除不逐条播动画：一次落库、一次 revision，列表整体刷新一遍
    await _db.removeFavoritesByIds(ids);
  }

  // ------------------------------------------------------------------ 条目

  String _subtitle(FavoriteItem item) {
    final l10n = context.l10n;
    if (item.kind == 'shareFolder') return l10n.folder;
    final parts = <String>[l10n.file];
    if (item.size.isNotEmpty) parts.add(prettyLzSize(item.size));
    return parts.join(' · ');
  }

  Future<void> _open(FavoriteItem item) async {
    if (_selecting) {
      _toggleSelected(item.id);
      return;
    }
    if (item.kind == 'shareFile') {
      await showAppSheet<void>(
        context,
        child: ShareFileInfoSheet(
          name: item.name,
          url: item.ref,
          pwd: item.pwd,
          size: item.size,
        ),
      );
    } else {
      await openShareSheet(
        context,
        initialLink: item.ref,
        initialPwd: item.pwd,
      );
    }
  }

  Future<void> _itemOptions(FavoriteItem item) async {
    final app = context.read<AppController>();
    final action = await showAppSheet<String>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(context.l10n.editInfo),
            onTap: () => Navigator.of(context).pop('edit'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(context.l10n.delete),
            onTap: () => Navigator.of(context).pop('delete'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _editFavorite(item);
    } else if (action == 'delete') {
      setState(() => _removing.add(item.id));
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
      await app.db.removeFavoriteById(item.id);
    }
  }

  Future<void> _editFavorite(FavoriteItem item) async {
    final app = context.read<AppController>();
    final titleController = TextEditingController(text: item.title);
    final linkController = TextEditingController(text: item.ref);
    final pwdController = TextEditingController(text: item.pwd);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.editInfo),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: context.l10n.favoriteTitle,
                  hintText: context.l10n.favoriteTitleHint,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: linkController,
                decoration: InputDecoration(labelText: context.l10n.shareLink),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pwdController,
                decoration: InputDecoration(
                  labelText: context.l10n.passwordOptional,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final link = linkController.text.trim();
              if (link.isEmpty) return;
              Navigator.of(dialogContext).pop();
              app.db.updateFavorite(
                item.id,
                title: titleController.text.trim(),
                ref: link,
                pwd: pwdController.text.trim(),
              );
              // 修改后闪一下，和网盘列表一致
              setState(() => _pulse[item.id] = (_pulse[item.id] ?? 0) + 1);
            },
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
  }

  Widget _tile(FavoriteItem item, {required int index}) {
    final l10n = context.l10n;
    final selected = _selected.contains(item.id);
    final isFolder = item.kind == 'shareFolder';
    return Md3ListItem(
      key: ValueKey('favorite-${item.id}'),
      index: index,
      // 入场动画由外层 ListEnterAnimation 统一驱动（只播一次）
      animateIn: false,
      removing: _removing.contains(item.id),
      pulse: _pulse[item.id] ?? 0,
      icon: isFolder ? Icons.folder_outlined : iconForFile(item.name),
      title: item.title.isEmpty ? item.name : item.title,
      subtitle: _subtitle(item),
      titleMaxLines: 2,
      subtitleMaxLines: 2,
      selected: selected,
      onTap: () => _open(item),
      onLongPress: () => _enterSelection(id: item.id),
      // 桌面端右键：与 ⋯ 菜单同一套操作（多选时不响应，和 ⋯ 一起隐藏）
      onSecondaryTap: _selecting ? null : () => _itemOptions(item),
      // 多选时隐藏 ⋯，但保留占位：条目高度不会跳
      trailing: HideKeepingSpace(
        hidden: _selecting,
        child: IconButton(
          visualDensity: VisualDensity.standard,
          iconSize: 20,
          tooltip: l10n.moreActions,
          icon: const Icon(Icons.more_vert),
          onPressed: () => _itemOptions(item),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.read<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final headerHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final selectedCount = _selected.length;
    final folders = _visible(_folders);
    final files = _visible(_files);
    return PopScope(
      // 独立页面（_openView 打开的二级路由）没有外壳的返回处理：
      // 多选状态下返回先退出多选；位于底栏（首个路由）时交给外壳统一处理。
      // 注意不能用 tabIndex 判断：独立打开时它也带着同一个值。
      canPop: inRootShell(context) || !_selecting,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selecting) _exitSelection();
      },
      child: Scaffold(
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
                      if (_loading)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            // 底栏盖在正文上方时，空状态保持在可见区域居中
                            padding: EdgeInsets.only(
                              bottom: shellBottomBarInset(context),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        )
                      else if (folders.isEmpty && files.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: shellBottomBarInset(context),
                            ),
                            child: EmptyHint(
                              icon: Icons.star_border,
                              text: _filter.trim().isEmpty
                                  ? l10n.favoritesHint
                                  : l10n.filterResult,
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          // 底部留白与首页 / 网盘 / 传输保持一致
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          sliver: SliverMainAxisGroup(
                            slivers: [
                              if (folders.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: SectionHeader(
                                    title: l10n.favoriteFolders,
                                    count: folders.length,
                                  ),
                                ),
                                // 懒加载：收藏多了也只构建可见部分
                                SegmentedSliverList(
                                  adaptive: true,
                                  // 幸存条目按 key 复用元素，删除后不重建
                                  findChildIndexCallback: childIndexLookup(
                                    folders,
                                    (item) =>
                                        ValueKey('favorite-entry-${item.id}'),
                                  ),
                                  itemCount: folders.length,
                                  itemBuilder: (context, index) =>
                                      ListEnterAnimation(
                                        key: ValueKey(
                                          'favorite-entry-${folders[index].id}',
                                        ),
                                        progress: _enter,
                                        index: index,
                                        child: _tile(
                                          folders[index],
                                          index: index,
                                        ),
                                      ),
                                ),
                                const SliverToBoxAdapter(
                                  child: SizedBox(height: 20),
                                ),
                              ],
                              if (files.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: SectionHeader(
                                    title: l10n.favoriteFiles,
                                    count: files.length,
                                  ),
                                ),
                                SegmentedSliverList(
                                  adaptive: true,
                                  findChildIndexCallback: childIndexLookup(
                                    files,
                                    (item) =>
                                        ValueKey('favorite-entry-${item.id}'),
                                  ),
                                  itemCount: files.length,
                                  itemBuilder: (context, index) =>
                                      ListEnterAnimation(
                                        key: ValueKey(
                                          'favorite-entry-${files[index].id}',
                                        ),
                                        progress: _enter,
                                        index: index,
                                        child: _tile(
                                          files[index],
                                          index: index,
                                        ),
                                      ),
                                ),
                              ],
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
                // 点顶栏空白处回到列表顶部（按钮 / 输入框自行响应，不会误触）
                builder: (context) => GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _scrollToTop,
                  child: AppBar(
                    backgroundColor: Colors.transparent,
                    scrolledUnderElevation: 0,
                    leading: _searching
                        ? IconButton(
                            tooltip: l10n.closeSearch,
                            icon: const Icon(Icons.close),
                            onPressed: _exitSearch,
                          )
                        : ((ModalRoute.of(context)?.isFirst ?? true)
                              ? null
                              : const AppBarBackButton()),
                    title: _searching
                        ? TextField(
                            controller: _search,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: l10n.searchFavorites,
                              border: InputBorder.none,
                            ),
                            onChanged: (value) =>
                                setState(() => _filter = value),
                          )
                        : Text(l10n.myFavorites),
                    actions: _searching
                        ? const <Widget>[]
                        : [
                            IconButton(
                              tooltip: l10n.search,
                              icon: const Icon(Icons.search),
                              onPressed: () =>
                                  setState(() => _searching = true),
                            ),
                            IconButton(
                              tooltip: l10n.menu,
                              icon: const Icon(Icons.more_vert),
                              onPressed: _showMenu,
                            ),
                          ],
                  ),
                ),
              ),
            ),
            // 多选顶栏
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                ignoring: !_selecting,
                child: AnimatedOpacity(
                  opacity: _selecting ? 1 : 0,
                  duration: _anim,
                  curve: Curves.easeInOut,
                  child: Material(
                    elevation: 0,
                    color: scheme.surface,
                    child: SizedBox(
                      height: headerHeight,
                      child: AppBar(
                        key: const ValueKey('favorites-selection-appbar'),
                        leading: IconButton(
                          tooltip: l10n.exitSelection,
                          icon: const Icon(Icons.close),
                          onPressed: _exitSelection,
                        ),
                        title: Text(l10n.selectedCount(selectedCount)),
                        actions: [
                          IconButton(
                            tooltip: l10n.selectAll,
                            icon: const Icon(Icons.select_all),
                            onPressed: _selectAll,
                          ),
                          IconButton(
                            tooltip: l10n.invertSelection,
                            icon: const Icon(Icons.flip),
                            onPressed: _invertSelection,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 多选操作栏
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_selecting,
                child: AnimatedOpacity(
                  opacity: _selecting ? 1 : 0,
                  duration: _anim,
                  curve: Curves.easeInOut,
                  child: BatchActionBar(
                    children: [
                      BatchAction(
                        icon: Icons.delete_outline,
                        label: l10n.delete,
                        onPressed: selectedCount == 0 ? null : _deleteSelected,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
