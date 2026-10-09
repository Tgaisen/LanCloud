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

class _ShareFolderPageState extends State<ShareFolderPage>
    with SingleTickerProviderStateMixin {
  bool _selecting = false;
  bool _searching = false;
  final Set<String> _selected = {};
  final TextEditingController _search = TextEditingController();
  String _filter = '';

  /// 长列表的入场动画：只播一次，之后滑进来的条目直接显示。
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: ListEnterAnimation.duration,
  )..forward();

  /// 文件分页：解析时只取第一页，进页面后按「自动加载全部目录内容」
  /// 设置与滚动位置继续加载（与网盘页一致）。
  final ScrollController _scroll = ScrollController();
  late List<ShareFileItem> _files = List.of(widget.folder.files);
  int _page = 1;
  late bool _hasMore = widget.folder.hasMore;
  bool _loadingMore = false;

  /// 上一次拉取失败且还有下一页：底部给出「重试」入口，
  /// 不能一直挂着「加载下一页」的转圈（转圈只代表"正在加载"）。
  bool _loadFailed = false;

  /// 自动补页失败后的剩余重试次数：网络抖一下也能自己恢复。
  int _autoRetriesLeft = _maxAutoRetries;
  static const int _maxAutoRetries = 3;

  /// 已经排了下一帧的补页检查；同一帧里重复调用只排一次。
  bool _fillCheckScheduled = false;

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
    _enter.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 320) {
      _loadMore();
    }
  }

  /// 加载下一页文件；没有分页上下文 / 搜索过滤 / 已到底时直接返回。
  /// [auto] 表示这次是「内容不满一屏，自动补页」发起的（失败会自动重试）。
  Future<void> _loadMore({bool auto = false}) async {
    final paging = widget.folder.paging;
    if (paging == null || _loadingMore || !_hasMore) return;
    if (_filter.isNotEmpty) return;
    setState(() {
      _loadingMore = true;
      _loadFailed = false;
    });
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
      _autoRetriesLeft = _maxAutoRetries;
      // 第一页没填满屏幕时继续补页，避免出现「没有滚动条就再也加载不了」
      _fillViewportIfNeeded();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadFailed = true;
      });
      // 自动补页失败：退避重试几次。少了这一步，文件夹内容少（一屏装得下）
      // 时底部会一直停在转圈上，直到用户自己滑一下才重新触发加载。
      if (auto && _autoRetriesLeft > 0) {
        _autoRetriesLeft -= 1;
        Future<void>.delayed(const Duration(milliseconds: 700), () {
          if (!mounted) return;
          // 定时器链路上没有帧在跑，直接查一次（不用等 post-frame）
          _fillViewportIfNeeded(immediate: true);
        });
      }
    }
  }

  /// 内容不足一屏时继续加载下一页（最多到填满或加载完为止）。
  ///
  /// 默认排到下一帧再判断（此时布局刚更新）；[immediate] 用于定时器重试这类
  /// 没有帧在跑的场景，直接按当前布局判断。
  void _fillViewportIfNeeded({bool immediate = false}) {
    if (!mounted || !_hasMore || _loadingMore || _autoLoading) return;
    if (_filter.isNotEmpty) return;
    if (!immediate) {
      if (_fillCheckScheduled) return;
      _fillCheckScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fillCheckScheduled = false;
        _fillViewportIfNeeded(immediate: true);
      });
      // post-frame 回调不会自己排帧：动画全关、界面静止时它会一直悬着，
      // 底部就停在「加载下一页」上不动了
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    if (!_scroll.hasClients) return;
    // 用和滚动加载同一个预加载阈值：只判 maxScrollExtent <= 0 的话，
    // 文件数刚好比一屏多一点时不会补页，底部的"加载下一页"转圈会一直停着
    if (_scroll.position.maxScrollExtent <= _scroll.position.pixels + 320) {
      _loadMore(auto: true);
    }
  }

  /// 「自动加载全部目录内容」：按页把剩余文件补完（页间隔与原来的解析逻辑一致）。
  Future<void> _autoLoadAll() async {
    if (_autoLoading) return;
    _autoLoading = true;
    var failures = 0;
    while (mounted && _hasMore) {
      final before = _page;
      await _loadMore();
      if (!mounted) break;
      if (_page == before) {
        // 本轮没有进展：失败就退避重试几次，重试完还不行就把底部
        // 交回「重试」入口，避免死循环
        if (++failures > _maxAutoRetries) break;
        await Future<void>.delayed(Duration(milliseconds: 600 * failures));
        continue;
      }
      failures = 0;
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

  /// 分页尾部的文字提示（与「已经到底了」同款样式）。
  Widget _footerText(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    ),
  );

  /// 分页拉取失败时的重试入口（点一下重新拉这一页）。
  Widget _footerRetry(VoidCallback onRetry) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Center(
      child: TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
    ),
  );

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
    final wasSelecting = _selecting;
    setState(() {
      _selecting = true;
      _selected.add(url);
    });
    if (!wasSelecting) announceEnteredMultiSelect(context);
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
    final files = _files.where((f) => _selected.contains(f.url)).toList();
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
    final files = _files.where((f) => _selected.contains(f.url)).toList();
    if (files.isEmpty) return;
    await copyText(context, files.map((f) => '${f.name} ${f.url}').join('\n'));
  }

  Future<void> _favoriteSelected() async {
    final app = context.read<AppController>();
    final files = _files.where((f) => _selected.contains(f.url)).toList();
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.addedToFavorites)));
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
            leading: const Icon(Icons.checklist),
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
      final detail = await app.publicClient.resolveFolderShare(
        sub.url,
        pwd: widget.pwd,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ShareFolderPage(folder: detail, link: sub.url, pwd: widget.pwd),
        ),
      );
    } on LanzouException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
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
        : _files.where((f) => f.name.toLowerCase().contains(query)).toList();
    final isEmpty =
        _files.isEmpty && folder.folders.isEmpty && folder.desc.isEmpty;
    // 分页尾部：正在拉下一页才转圈，全部加载完提示到底。
    // 作为列表的 trailing 跟着条目一起懒构建（另起 sliver 的话，
    // 即使整条在屏幕外也会构建第一个子节点，转圈会常驻重绘）。
    //
    // 搜索只在「已加载的页面」里过滤（_loadMore 会跳过），不会继续补页，
    // 所以搜索时不能显示加载转圈（会让人以为在自动加载），改为提示可能不全。
    //
    // 还有下一页但当前没在加载时不要转圈：转圈只表示「正在加载」，
    // 否则内容不满一屏、自动补页又没跑起来时会一直停在转圈上。
    final footer = query.isNotEmpty && (_hasMore || _loadingMore)
        ? _footerText(l10n.searchIncomplete)
        : _loadingMore
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        : _hasMore
        ? (_loadFailed
              ? _footerRetry(() => _loadMore())
              : const SizedBox.shrink())
        : (_files.isNotEmpty && query.isEmpty
              ? _footerText(l10n.reachedEnd)
              : const SizedBox.shrink());
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
      // 列表尺寸一变化（进页面、补页、窗口大小变化）就重新评估要不要补页：
      // 这条触发不依赖「下一帧还会不会有帧」，界面静止时也能自己补齐，
      // 否则内容不满一屏时底部会一直停在「加载下一页」的转圈上。
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.metrics.hasContentDimensions) {
            _fillViewportIfNeeded();
          }
          return false;
        },
        child: TopBarOverlayScaffold(
          controller: _scroll,
          // 顶栏空白处点按回到顶部由 TopBarOverlayScaffold 统一处理
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
                          tooltip: l10n.closeSearch,
                          icon: const Icon(Icons.close),
                          onPressed: _exitSearch,
                        )
                      : const AppBarBackButton()),
            title: _selecting
                ? Text(l10n.selectedCount(_selected.length))
                // 标题 ↔ 搜索框带显示 / 隐藏动画，不要直接闪出来
                : AppBarSearchSwitcher(
                    searching: _searching,
                    title: Text(folder.name),
                    searchField: TextField(
                      controller: _search,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: l10n.searchCurrentFolder,
                        border: InputBorder.none,
                      ),
                      onChanged: (value) => setState(() => _filter = value),
                    ),
                  ),
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
                child: EmptyHint(
                  icon: Icons.folder_open,
                  text: l10n.shareEmpty,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    if (folder.desc.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: _SectionTitle(text: l10n.shareMessage),
                      ),
                      SliverToBoxAdapter(
                        child: SegmentedList(
                          margin: const EdgeInsets.only(bottom: 12),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(folder.desc),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (folders.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: _SectionTitle(text: l10n.folder),
                      ),
                      // 懒加载：条目多了也只构建可见部分
                      SegmentedSliverList(
                        adaptive: true,
                        itemCount: folders.length,
                        // 只有文件夹（没有文件）时，尾部挂在文件夹列表上
                        trailing: files.isEmpty ? footer : null,
                        itemBuilder: (context, index) {
                          final sub = folders[index];
                          return ListEnterAnimation(
                            progress: _enter,
                            index: index,
                            child: Md3ListItem(
                              key: ValueKey('share-folder-${sub.url}'),
                              icon: Icons.folder_outlined,
                              title: sub.name,
                              subtitle: sub.desc,
                              animateIn: false,
                              onTap: () => _openSubfolder(sub),
                            ),
                          );
                        },
                      ),
                    ],
                    if (files.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: _SectionTitle(text: l10n.files),
                      ),
                      SegmentedSliverList(
                        adaptive: true,
                        itemCount: files.length,
                        trailing: footer,
                        itemBuilder: (context, index) {
                          final file = files[index];
                          return ListEnterAnimation(
                            progress: _enter,
                            index: index,
                            child: Md3ListItem(
                              key: ValueKey('share-file-${file.url}'),
                              icon: iconForFile(file.name),
                              title: file.name,
                              subtitle: [
                                prettyLzSize(file.size),
                                if (file.time.isNotEmpty) file.time,
                              ].where((e) => e.isNotEmpty).join(' · '),
                              selected:
                                  _selecting && _selected.contains(file.url),
                              animateIn: false,
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
                          );
                        },
                      ),
                    ],
                    // 既没有文件夹也没有文件（只有简介）时，尾部单独放
                    if (folders.isEmpty && files.isEmpty)
                      SliverToBoxAdapter(child: footer),
                  ],
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
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
