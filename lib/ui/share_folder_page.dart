import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/api/lanzou_client.dart';
import '../core/api/models.dart';
import '../core/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'share_file_sheet.dart';
import 'web_page.dart';

/// 分享文件夹浏览页：布局类似网盘页，支持子文件夹与多选批量操作。
class ShareFolderPage extends StatefulWidget {
  const ShareFolderPage({
    super.key,
    required this.folder,
    required this.link,
    required this.pwd,
  });

  final FolderShareDetail folder;
  final String link;
  final String pwd;

  @override
  State<ShareFolderPage> createState() => _ShareFolderPageState();
}

class _ShareFolderPageState extends State<ShareFolderPage> {
  bool _selecting = false;
  bool _searching = false;
  final Set<String> _selected = {};
  final TextEditingController _search = TextEditingController();
  String _filter = '';
  /// 文件分页：解析时只取第一页，进页面后按「自动加载全部目录内容」
  /// 设置与滚动位置继续加载（与网盘页一致）。
  final ScrollController _scroll = ScrollController();
  late List<ShareFileItem> _files = List.of(widget.folder.files);
  int _page = 1;
  late bool _hasMore = widget.folder.hasMore;
  bool _loadingMore = false;
  /// 「自动加载全部目录内容」打开时后台把剩余分页补完。
  bool _autoLoading = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    if (widget.folder.hasMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (context.read<AppController>().settings.loadAllPages) {
          _autoLoadAll();
        } else {
          _fillViewportIfNeeded();
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 320) {
      _loadMore();
    }
  }

  /// 加载下一页文件；没有分页上下文 / 搜索过滤 / 已到底时直接返回。
  Future<void> _loadMore() async {
    final paging = widget.folder.paging;
    if (paging == null || _loadingMore || !_hasMore) return;
    if (_filter.isNotEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final next = await context
          .read<AppController>()
          .publicClient
          .fetchShareFolderFiles(paging, _page + 1);
      if (!mounted) return;
      setState(() {
        _files = [..._files, ...next.files];
        _page += 1;
        _hasMore = next.hasMore && next.files.isNotEmpty;
        _loadingMore = false;
      });
      // 第一页没填满屏幕时继续补页，避免出现「没有滚动条就再也加载不了」
      _fillViewportIfNeeded();
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// 内容不足一屏时继续加载下一页（最多到填满或加载完为止）。
  void _fillViewportIfNeeded() {
    if (!mounted || !_hasMore || _loadingMore || _autoLoading) return;
    if (_filter.isNotEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hasMore || _loadingMore || _autoLoading) return;
      if (!_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent <= 0) _loadMore();
    });
  }

  /// 「自动加载全部目录内容」：按页把剩余文件补完（页间隔与原来的解析逻辑一致）。
  Future<void> _autoLoadAll() async {
    if (_autoLoading) return;
    _autoLoading = true;
    while (mounted && _hasMore) {
      final before = _page;
      await _loadMore();
      if (!mounted) break;
      // 本轮没有进展（失败 / 已到底）：结束，避免死循环
      if (_page == before) break;
      if (_hasMore) await Future.delayed(const Duration(milliseconds: 600));
    }
    _autoLoading = false;
  }

  void _exitSearch() {
    setState(() {
      _searching = false;
      _filter = '';
      _search.clear();
    });
  }

  void _toggleSelecting() {
    setState(() {
      _selecting = !_selecting;
      _selected.clear();
    });
  }

  void _toggleFile(String url) {
    setState(() {
      if (!_selected.remove(url)) _selected.add(url);
    });
  }

  /// 长按条目进入多选并选中它。
  void _enterSelection(String url) {
    setState(() {
      _selecting = true;
      _selected.add(url);
    });
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == _files.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_files.map((f) => f.url));
      }
    });
  }

  void _invertSelection() {
    setState(() {
      for (final file in _files) {
        if (!_selected.remove(file.url)) _selected.add(file.url);
      }
    });
  }

  Future<void> _downloadSelected() async {
    final files = _files
        .where((f) => _selected.contains(f.url))
        .toList();
    if (files.isEmpty) return;
    await downloadShareFiles(
      context,
      urls: [for (final f in files) f.url],
      names: [for (final f in files) f.name],
      pwd: widget.pwd,
    );
    if (mounted) _toggleSelecting();
  }

  Future<void> _copySelectedLinks() async {
    final files = _files
        .where((f) => _selected.contains(f.url))
        .toList();
    if (files.isEmpty) return;
    await copyText(
      context,
      files.map((f) => '${f.name} ${f.url}').join('\n'),
    );
  }

  Future<void> _favoriteSelected() async {
    final app = context.read<AppController>();
    final files = _files
        .where((f) => _selected.contains(f.url))
        .toList();
    for (final file in files) {
      await app.db.addFavorite(
        kind: 'shareFile',
        name: file.name,
        ref: file.url,
        pwd: widget.pwd,
        sharer: widget.folder.sharer,
      );
    }
    if (!mounted) return;
    _toggleSelecting();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.favoritedCount(files.length))),
    );
  }

  Future<void> _favoriteFolder() async {
    final app = context.read<AppController>();
    await app.db.addFavorite(
      kind: 'shareFolder',
      name: widget.folder.name,
      ref: widget.link,
      pwd: widget.pwd,
      sharer: widget.folder.sharer,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.addedToFavorites)),
      );
    }
  }

  Future<void> _showMenu() async {
    final app = context.read<AppController>();
    await showAppSheet<void>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            // 原顶栏的多选入口移到这里
            ListTile(
              leading: const Icon(Icons.done_all),
              title: Text(context.l10n.multiSelect),
              onTap: () {
                Navigator.of(context).pop();
                _toggleSelecting();
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: Text(context.l10n.favorite),
              onTap: () {
                Navigator.of(context).pop();
                _favoriteFolder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(context.l10n.copyLink),
              onTap: () {
                Navigator.of(context).pop();
                copyText(context, widget.link);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(context.l10n.openLink),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WebPage(
                      title: widget.folder.name,
                      url: widget.link,
                      cookie: app.activeAccount?.cookie,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _openSubfolder(SubFolder sub) async {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    showLoadingDialog(context, l10n.resolving);
    try {
      final detail =
          await app.publicClient.resolveFolderShare(sub.url, pwd: widget.pwd);
      if (!mounted) return;
      Navigator.of(context).pop();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ShareFolderPage(
            folder: detail,
            link: sub.url,
            pwd: widget.pwd,
          ),
        ),
      );
    } on LanzouException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final folder = widget.folder;
    final query = _filter.trim().toLowerCase();
    final folders = query.isEmpty
        ? folder.folders
        : folder.folders
            .where((f) => f.name.toLowerCase().contains(query))
            .toList();
    final files = query.isEmpty
        ? _files
        : _files
            .where((f) => f.name.toLowerCase().contains(query))
            .toList();
    final isEmpty =
        _files.isEmpty && folder.folders.isEmpty && folder.desc.isEmpty;
    return PopScope(
      // 多选 / 搜索状态下先退出，再退出页面
      canPop: !_selecting && !_searching,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selecting) {
          _toggleSelecting();
        } else if (_searching) {
          _exitSearch();
        }
      },
      child: TopBarOverlayScaffold(
        controller: _scroll,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
          leading: _selecting
              ? IconButton(
                  tooltip: l10n.exitSelection,
                  icon: const Icon(Icons.close),
                  onPressed: _toggleSelecting,
                )
              : (_searching
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _exitSearch,
                    )
                  : const AppBarBackButton()),
          title: _selecting
              ? Text(l10n.selectedCount(_selected.length))
              : (_searching
                  ? TextField(
                      controller: _search,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: l10n.searchCurrentFolder,
                        border: InputBorder.none,
                      ),
                      onChanged: (value) => setState(() => _filter = value),
                    )
                  : Text(folder.name)),
          actions: _selecting
              ? [
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
                ]
              : (_searching
                  ? const <Widget>[]
                  : [
                      IconButton(
                        tooltip: l10n.search,
                        icon: const Icon(Icons.search),
                        onPressed: () => setState(() => _searching = true),
                      ),
                      IconButton(
                        tooltip: l10n.moreActions,
                        icon: const Icon(Icons.more_vert),
                        onPressed: _showMenu,
                      ),
                    ]),
        ),
        slivers: [
          if (isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyHint(icon: Icons.folder_open, text: l10n.shareEmpty),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (folder.desc.isNotEmpty) ...[
                    _SectionTitle(text: l10n.shareMessage),
                    SegmentedList(
                      margin: const EdgeInsets.only(bottom: 12),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(folder.desc),
                        ),
                      ],
                    ),
                  ],
                  if (folders.isNotEmpty) ...[
                    _SectionTitle(text: l10n.folder),
                    SegmentedList(
                      adaptive: true,
                      children: [
                        for (final sub in folders)
                          Md3ListItem(
                            key: ValueKey('share-folder-${sub.url}'),
                            icon: Icons.folder_outlined,
                            title: sub.name,
                            subtitle: sub.desc,
                            onTap: () => _openSubfolder(sub),
                          ),
                      ],
                    ),
                  ],
                  if (files.isNotEmpty) ...[
                    _SectionTitle(text: l10n.files),
                    SegmentedList(
                      adaptive: true,
                      children: [
                        for (final file in files)
                          Md3ListItem(
                            key: ValueKey('share-file-${file.url}'),
                            icon: iconForFile(file.name),
                            title: file.name,
                            subtitle: [
                              prettyLzSize(file.size),
                              if (file.time.isNotEmpty) file.time,
                            ].where((e) => e.isNotEmpty).join(' · '),
                            selected:
                                _selecting && _selected.contains(file.url),
                            onLongPress: () => _enterSelection(file.url),
                            onTap: () {
                              if (_selecting) {
                                _toggleFile(file.url);
                              } else {
                                showAppSheet<void>(
                                  context,
                                  child: ShareFileInfoSheet(
                                    name: file.name,
                                    url: file.url,
                                    pwd: widget.pwd,
                                    size: file.size,
                                    time: file.time,
                                  ),
                                );
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                  // 分页尾部：加载下一页时转圈，全部加载完提示到底
                  if (_hasMore || _loadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (_files.isNotEmpty && query.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          l10n.reachedEnd,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                ]),
              ),
            ),
        ],
        bottomNavigationBar: _selecting
            ? BatchActionBar(
                children: [
                  BatchAction(
                    icon: Icons.download,
                    label: l10n.download,
                    onPressed: _selected.isEmpty ? null : _downloadSelected,
                  ),
                  BatchAction(
                    icon: Icons.copy,
                    label: l10n.copyLink,
                    onPressed: _selected.isEmpty ? null : _copySelectedLinks,
                  ),
                  BatchAction(
                    icon: Icons.star_outline,
                    label: l10n.favorite,
                    onPressed: _selected.isEmpty ? null : _favoriteSelected,
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

