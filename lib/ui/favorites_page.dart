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
    with AutomaticKeepAliveClientMixin {
  static const _anim = Duration(milliseconds: 200);

  List<FavoriteItem> _folders = [];
  List<FavoriteItem> _files = [];
  bool _loading = true;
  bool _selecting = false;
  final Set<int> _selected = {};
  final ScrollController _scroll = ScrollController();
  late final AppDb _db;
  AppController? _app;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
    _db = app.db;
    _db.revision.addListener(_load);
    app.activeTab.addListener(_onActiveTabChanged);
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
      app.activeTab.removeListener(_onActiveTabChanged);
      if (_selecting) {
        app.setSelectionMode(false);
        app.onRequestExitSelection = null;
      }
    }
    _scroll.dispose();
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
      });
    } catch (_) {
      // 读取失败时保持已有内容
      if (mounted) setState(() => _loading = false);
    }
  }

  List<FavoriteItem> get _items => [..._folders, ..._files];

  // ------------------------------------------------------------------ 多选

  void _enterSelection({int? id}) {
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
    for (final id in ids) {
      await _db.removeFavoriteById(id);
    }
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
      await openShareSheet(context, initialLink: item.ref, initialPwd: item.pwd);
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
            },
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
  }

  Widget _tile(FavoriteItem item) {
    final l10n = context.l10n;
    final selected = _selected.contains(item.id);
    final isFolder = item.kind == 'shareFolder';
    return Md3ListItem(
      icon: isFolder ? Icons.folder_outlined : iconForFile(item.name),
      title: item.title.isEmpty ? item.name : item.title,
      subtitle: _subtitle(item),
      titleMaxLines: 2,
      subtitleMaxLines: 2,
      selected: selected,
      onTap: () => _open(item),
      onLongPress: () => _enterSelection(id: item.id),
      trailing: _selecting
          ? null
          : IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              tooltip: l10n.moreActions,
              icon: const Icon(Icons.more_vert),
              onPressed: () => _itemOptions(item),
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
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_folders.isEmpty && _files.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyHint(
                      icon: Icons.star_border,
                      text: l10n.favoritesHint,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (_folders.isNotEmpty) ...[
                          SectionHeader(
                            title: l10n.favoriteFolders,
                            count: _folders.length,
                          ),
                          SegmentedList(
                            children: [
                              for (final item in _folders) _tile(item),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (_files.isNotEmpty) ...[
                          SectionHeader(
                            title: l10n.favoriteFiles,
                            count: _files.length,
                          ),
                          SegmentedList(
                            children: [for (final item in _files) _tile(item)],
                          ),
                        ],
                        const SizedBox(height: 96),
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
              builder: (context, opacity) => AppBar(
                toolbarOpacity: opacity,
                backgroundColor: Color.lerp(
                  scheme.surface,
                  scheme.surfaceContainer,
                  ScrollTint.of(context),
                ),
                scrolledUnderElevation: 0,
                title: Text(l10n.myFavorites),
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
                      onPressed:
                          selectedCount == 0 ? null : _deleteSelected,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
