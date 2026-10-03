import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Icons;
import 'package:lpinyin/lpinyin.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/api/lanzou_client.dart';
import '../core/api/models.dart';
import '../core/app_controller.dart';
import '../core/drive_cache.dart';
import '../core/file_picker_channel.dart';
import '../core/transfer/transfer_manager.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'drive_refresh_indicator.dart' as drive_refresh;
import 'scroll_tint.dart';
import 'web_page.dart';

const int kFreeUploadLimit = 100 * 1024 * 1024;

class DrivePage extends StatefulWidget {
  const DrivePage({
    super.key,
    this.initialFolderId = '-1',
    this.initialName,
    this.tabIndex,
  });

  final String initialFolderId;
  final String? initialName;
  /// 外壳中的 page 视图下标；作为独立路由打开时为 null（不响应切换通知）。
  final int? tabIndex;

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage>
    with
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver {
  static const _anim = Duration(milliseconds: 200);

  @override
  bool get wantKeepAlive => true;

  late final AnimationController _selAnim = AnimationController(
    vsync: this,
    duration: _anim,
  );

  /// 目录切换：当前内容先淡出（[_exitAnim]），新内容再按 index 错峰淡入。
  /// 整张列表共享同一个 [_enterAnim]，滑动时新构建的条目只会读到当前进度，
  /// 所以“逐个显现”只在目录加载完成后播放一次，滑动不会重播。
  late final AnimationController _enterAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 440),
    value: 1,
  );

  late final AnimationController _exitAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 170),
  );

  late final Animation<double> _contentFade = Tween<double>(
    begin: 1,
    end: 0,
  ).animate(CurvedAnimation(parent: _exitAnim, curve: Curves.easeIn));

  /// 局部刷新的行内动画状态：正在淡出 / 刚出现 / 刚被修改的条目 id。
  final Set<String> _removingFiles = {};
  final Set<String> _removingFolders = {};
  final Set<String> _appearingFiles = {};
  final Set<String> _appearingFolders = {};
  final Set<String> _pulsingFiles = {};
  final Set<String> _pulsingFolders = {};
  bool _directorySwitching = false;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  late String _folderId = widget.initialFolderId;
  List<PathNode> _path = [];
  List<LzFolder> _folders = [];
  List<LzFile> _files = [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  bool _searching = false;
  String _filter = '';
  String _sortMode = 'default';
  final Map<String, double> _folderOffsets = {};
  bool _selecting = false;
  final Set<String> _selectedFiles = {};
  final Set<String> _selectedFolders = {};
  final Map<String, String> _fileDescCache = {};
  final Map<String, String> _folderDescCache = {};
  final Map<String, String> _folderSizeCache = {};
  /// 键盘是否弹出（悬浮底栏的 FAB 留白跟随它，见 didChangeMetrics）。
  final ValueNotifier<bool> _keyboardUp = ValueNotifier(false);
  late AppController _app;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // initState 里不能做 InheritedWidget 查询（View.of 会触发 debug 断言），
    // 这里直接读窗口指标；didChangeMetrics 之后照旧用 View.of。
    _keyboardUp.value =
        WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom >
            0;
    final app = context.read<AppController>();
    _sortMode = app.settings.sortMode;
    context.read<TransferManager>().addTaskListener(_onTaskDone);
    if (widget.initialName != null) {
      _path = [PathNode(id: widget.initialFolderId, name: widget.initialName!)];
    }
    _scroll.addListener(_onScroll);
    app.driveFolderRequest.addListener(_onDriveFolderRequest);
    if (app.driveFolderRequest.value != null) {
      // 首页请求的目录：直接加载目标目录，不再先加载根目录
      WidgetsBinding.instance.addPostFrameCallback((_) => _onDriveFolderRequest());
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyboardUp.dispose();
    _app.driveFolderRequest.removeListener(_onDriveFolderRequest);
    context.read<TransferManager>().removeTaskListener(_onTaskDone);
    if (widget.initialFolderId == '-1' && widget.initialName == null) {
      _app.onDriveBack = null;
    }
    if (_selecting) {
      _app.setSelectionMode(false);
      _app.onRequestExitSelection = null;
    }
    _selAnim.dispose();
    _enterAnim.dispose();
    _exitAnim.dispose();
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    // 底栏外壳的 Scaffold 会消耗键盘 inset（页面内 MediaQuery.viewInsets 归零），
    // 所以直接读窗口的原始 inset 判断键盘是否弹出；只在状态变化时通知 FAB 重建。
    _keyboardUp.value = View.of(context).viewInsets.bottom > 0;
  }

  bool get _animationsEnabled =>
      context.read<AppController>().settings.transitionAnimations;

  /// 首页选择“网盘页打开”时：跳转到请求的目录。
  void _onDriveFolderRequest() {
    final folderId = _app.driveFolderRequest.value;
    if (folderId == null) return;
    _app.driveFolderRequest.value = null;
    if (!mounted) return;
    _openFolderById(folderId);
  }

  /// 直接定位到指定目录（路径由接口返回，从根目录算起）。
  Future<void> _openFolderById(String folderId) async {
    if (_directorySwitching || folderId == _folderId) return;
    _directorySwitching = true;
    try {
      _app.animateBarsHide(0);
      _rememberFolderOffset();
      await _animateDirectorySwitch(folderId);
      if (!mounted) return;
      setState(() {
        _folderId = folderId;
        _filter = '';
        _searchController.clear();
        _path = const [];
      });
      await _load();
      if (!mounted) return;
      _restoreFolderOffset(folderId);
    } finally {
      _directorySwitching = false;
    }
  }

  /// 上传完成后，若目标是当前目录，只刷新文件列表（局部刷新）。
  void _onTaskDone(TransferTask task) {
    if (task.kind != TransferKind.upload ||
        task.folderId != _folderId ||
        !mounted) {
      return;
    }
    _refreshInPlace();
  }

  /// 局部刷新：保持当前列表可见，拉取完成后按差异播放新增/移除动画。
  /// [refreshFolders] 为 true 时同时重新拉取文件夹列表（新建/移动之后需要）。
  Future<bool> _refreshInPlace({bool refreshFolders = false}) async {
    final app = context.read<AppController>();
    final client = app.client;
    if (client == null) return false;
    try {
      // 已经加载过几页就刷新几页，避免局部刷新把后面的条目吞掉
      final listing = await _fetchListing(
        app,
        client,
        maxPages: math.max(_page, 1),
        withFolders: refreshFolders,
      );
      if (!mounted) return false;
      _applyListing(
        folders: refreshFolders ? listing.folders : _folders,
        files: listing.files,
        page: listing.page,
        hasMore: listing.hasMore,
      );
      return true;
    } catch (_) {
      // 局部刷新失败不打扰用户，下拉或菜单刷新可兜底
      return false;
    }
  }

  /// 拉取当前目录快照；[maxPages] 控制最多加载多少页（默认按“全部加载”设置）。
  Future<_Listing> _fetchListing(
    AppController app,
    LanzouClient client, {
    int? maxPages,
    bool withFolders = true,
  }) async {
    final foldersResult =
        withFolders ? await client.listFolders(_folderId) : null;
    final limit = maxPages ?? (app.settings.loadAllPages ? 60 : 1);
    final first = await client.listFilesPage(_folderId, 1);
    var files = first.files;
    var hasMore = first.hasMore;
    var page = 1;
    while (hasMore && page < limit) {
      page += 1;
      final next = await client.listFilesPage(_folderId, page);
      files = [...files, ...next.files];
      hasMore = next.hasMore;
    }
    return _Listing(
      folders: foldersResult?.folders ?? const [],
      files: files,
      path: foldersResult?.path ?? const [],
      page: page,
      hasMore: hasMore,
    );
  }

  /// 把最新快照合并进列表：新增条目渐入、消失条目留在原位淡出，
  /// 动画结束后再对齐到全量快照。
  void _applyListing({
    required List<LzFolder> folders,
    required List<LzFile> files,
    int? page,
    bool? hasMore,
    List<PathNode>? path,
  }) {
    final animate = _animationsEnabled;
    final oldFolders = _folders;
    final oldFiles = _files;
    final oldFolderIds = {for (final f in oldFolders) f.id};
    final oldFileIds = {for (final f in oldFiles) f.id};
    final folderIds = {for (final f in folders) f.id};
    final fileIds = {for (final f in files) f.id};
    final addedFolders = folderIds.difference(oldFolderIds);
    final addedFiles = fileIds.difference(oldFileIds);
    final goneFolders =
        animate ? oldFolderIds.difference(folderIds) : const <String>{};
    final goneFiles =
        animate ? oldFileIds.difference(fileIds) : const <String>{};

    setState(() {
      _removingFolders.addAll(goneFolders);
      _removingFiles.addAll(goneFiles);
      _appearingFolders.addAll(addedFolders);
      _appearingFiles.addAll(addedFiles);
      _folders = goneFolders.isEmpty
          ? folders
          : _mergeVanishing(oldFolders, folders, goneFolders, (f) => f.id);
      _files = goneFiles.isEmpty
          ? files
          : _mergeVanishing(oldFiles, files, goneFiles, (f) => f.id);
      _page = page ?? _page;
      _hasMore = hasMore ?? _hasMore;
      if (path != null) _path = path;
    });

    if (addedFolders.isNotEmpty || addedFiles.isNotEmpty) {
      Future<void>.delayed(const Duration(milliseconds: 420), () {
        if (!mounted) return;
        setState(() {
          _appearingFolders.removeAll(addedFolders);
          _appearingFiles.removeAll(addedFiles);
        });
      });
    }
    if (goneFolders.isNotEmpty || goneFiles.isNotEmpty) {
      Future<void>.delayed(const Duration(milliseconds: 240), () {
        if (!mounted) return;
        setState(() {
          _removingFolders.removeAll(goneFolders);
          _removingFiles.removeAll(goneFiles);
          _folders = folders;
          _files = files;
        });
        _updateCacheSnapshot();
      });
    } else {
      _updateCacheSnapshot();
    }
  }

  /// 保留正在淡出的旧条目，并按原索引插回结果，避免它们瞬间消失。
  List<T> _mergeVanishing<T>(
    List<T> oldList,
    List<T> newList,
    Set<String> goneIds,
    String Function(T item) idOf,
  ) {
    final result = [...newList];
    for (var i = 0; i < oldList.length; i++) {
      final item = oldList[i];
      if (!goneIds.contains(idOf(item))) continue;
      result.insert(math.min(i, result.length), item);
    }
    return result;
  }

  /// 先播放移除动画再从列表里移除；无动画时直接移除。
  Future<void> _removeItemsWithAnimation({
    Set<String> fileIds = const {},
    Set<String> folderIds = const {},
  }) async {
    if (fileIds.isEmpty && folderIds.isEmpty) return;
    if (_animationsEnabled) {
      setState(() {
        _removingFiles.addAll(fileIds);
        _removingFolders.addAll(folderIds);
      });
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
    }
    setState(() {
      _removingFiles.removeAll(fileIds);
      _removingFolders.removeAll(folderIds);
      _files.removeWhere((f) => fileIds.contains(f.id));
      _folders.removeWhere((f) => folderIds.contains(f.id));
    });
    _updateCacheSnapshot();
  }

  /// 条目内容被修改后播放一次高亮闪烁。
  void _pulseItems({
    Set<String> fileIds = const {},
    Set<String> folderIds = const {},
  }) {
    if (!_animationsEnabled || (fileIds.isEmpty && folderIds.isEmpty)) return;
    setState(() {
      _pulsingFiles.addAll(fileIds);
      _pulsingFolders.addAll(folderIds);
    });
    Future<void>.delayed(const Duration(milliseconds: 720), () {
      if (!mounted) return;
      setState(() {
        _pulsingFiles.removeAll(fileIds);
        _pulsingFolders.removeAll(folderIds);
      });
    });
  }

  /// 目录切换动画：先淡出当前内容，再把已收起的悬浮顶栏顺势滑下来
  /// （滑动的过程发生在内容淡出之后，视觉上只有顶栏在动），
  /// 然后调用方才真正切换数据。等新内容就绪后再播放错峰出现动画。
  Future<void> _animateDirectorySwitch(String targetFolderId) async {
    if (!_animationsEnabled || _loading) return;
    await _exitAnim.forward(from: 0);
    if (!mounted || !_scroll.hasClients) return;
    final target = _folderOffsets[targetFolderId] ?? 0;
    final from = _scroll.position.pixels;
    if (target >= from) return;
    await _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  /// 内容就绪：恢复不透明度并播放一次错峰出现动画。
  void _playEnterAnimation() {
    if (!_animationsEnabled) {
      _enterAnim.value = 1;
      return;
    }
    _enterAnim.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = context.read<AppController>();
    if (widget.initialFolderId == '-1' && widget.initialName == null) {
      _app.onDriveBack = _handleDriveBack;
    }
    // 换账号兜底：页面状态如果被保留下来，也要丢掉上一个账号的目录内容
    final uid = _app.activeUid;
    if (_loadedUid == null) {
      _loadedUid = uid;
    } else if (_loadedUid != uid) {
      _loadedUid = uid;
      WidgetsBinding.instance.addPostFrameCallback((_) => _resetForAccount());
    }
  }

  /// 当前已加载数据的账号，用于换账号时重置页面。
  String? _loadedUid;

  /// 换账号：清掉目录内容并回到根目录重新加载（缓存已按账号清空）。
  void _resetForAccount() {
    if (!mounted) return;
    _folderOffsets.clear();
    _fileDescCache.clear();
    _folderDescCache.clear();
    _folderSizeCache.clear();
    _searchController.clear();
    setState(() {
      _folderId = '-1';
      _path = const [];
      _folders = [];
      _files = [];
      _filter = '';
      _searching = false;
      _page = 1;
      _hasMore = false;
      _loading = true;
      _error = null;
    });
    _load(force: true);
  }

  /// 返回键：多选 > 搜索栏 > 上一级目录 > 交给外壳处理
  Future<bool> _handleDriveBack() async {
    if (_selecting) {
      _exitSelection();
      return true;
    }
    if (_searching) {
      _closeSearch();
      return true;
    }
    if (_path.isNotEmpty) {
      await _jumpTo(_path.length - 2);
      return true;
    }
    return false;
  }

  /// 关闭搜索栏并清空过滤条件。
  void _closeSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _searching = false;
      _filter = '';
      _searchController.clear();
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pixels = _scroll.position.pixels;
    if (pixels >= _scroll.position.maxScrollExtent - 320) {
      _loadMore();
    }
  }

  CachedFolder _snapshot() => CachedFolder(
    folders: _folders,
    files: _files,
    path: _path,
    page: _page,
    hasMore: _hasMore,
  );

  void _updateCacheSnapshot() {
    final app = context.read<AppController>();
    if (app.settings.cacheFolders) {
      app.driveCache.put(_folderId, _snapshot());
    }
  }

  Future<void> _load({bool force = false}) async {
    final app = context.read<AppController>();
    final client = app.client;
    if (client == null) return;

    final cached = app.settings.cacheFolders
        ? app.driveCache.get(_folderId)
        : null;
    if (!force && cached != null) {
      _exitAnim.value = 0;
      setState(() {
        _folders = cached.folders;
        _files = cached.files;
        _path = _folderId == '-1'
            ? const <PathNode>[]
            : (cached.path.isEmpty ? _path : cached.path);
        _page = cached.page;
        _hasMore = cached.hasMore;
        _loading = false;
        _error = null;
      });
      _playEnterAnimation();
      return;
    }

    // 旧内容已经淡出，加载指示器需要恢复可见
    _exitAnim.value = 0;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await _fetchListing(app, client);
      if (!mounted) return;
      _exitAnim.value = 0;
      setState(() {
        _folders = listing.folders;
        _path = _folderId == '-1'
            ? const <PathNode>[]
            : (listing.path.isEmpty ? _path : listing.path);
        _files = listing.files;
        _page = listing.page;
        _hasMore = listing.hasMore;
        _loading = false;
        _selectedFiles.clear();
        _selectedFolders.clear();
        _removingFiles.clear();
        _removingFolders.clear();
        _appearingFiles.clear();
        _appearingFolders.clear();
        _pulsingFiles.clear();
        _pulsingFolders.clear();
      });
      _playEnterAnimation();
      if (app.settings.cacheFolders) {
        app.driveCache.put(_folderId, _snapshot());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _directorySwitching || _loadingMore || !_hasMore) return;
    if (_filter.isNotEmpty) return;
    final app = context.read<AppController>();
    final client = app.client;
    if (client == null) return;
    setState(() => _loadingMore = true);
    try {
      final next = await client.listFilesPage(_folderId, _page + 1);
      if (!mounted) return;
      setState(() {
        _files = [..._files, ...next.files];
        _page += 1;
        _hasMore = next.hasMore;
        _loadingMore = false;
      });
      if (app.settings.cacheFolders) {
        app.driveCache.put(_folderId, _snapshot());
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _reloadAfterChange() async {
    context.read<AppController>().driveCache.clear();
    await _load(force: true);
  }

  List<LzFolder> get _visibleFolders {
    final query = _filter.toLowerCase();
    final list = _folders
        .where((f) => query.isEmpty || f.name.toLowerCase().contains(query))
        .toList();
    if (_sortMode == 'name') {
      list.sort(
        (a, b) => _nameSortKey(a.name).compareTo(_nameSortKey(b.name)),
      );
    }
    return list;
  }

  String _nameSortKey(String name) => PinyinHelper.getPinyinE(
        name,
        separator: '',
        defPinyin: '~',
      ).toLowerCase();

  List<LzFile> get _visibleFiles {
    final query = _filter.toLowerCase();
    final list = _files
        .where((f) => query.isEmpty || f.name.toLowerCase().contains(query))
        .toList();
    switch (_sortMode) {
      case 'size':
        list.sort(
          (a, b) => lzSizeToBytes(b.size).compareTo(lzSizeToBytes(a.size)),
        );
      case 'default':
        break;
      default:
        list.sort(
          (a, b) => _nameSortKey(a.name).compareTo(_nameSortKey(b.name)),
        );
    }
    return list;
  }

  void _enterSelection({String? fileId, String? folderId}) {
    setState(() {
      _selecting = true;
      if (fileId != null) _selectedFiles.add(fileId);
      if (folderId != null) _selectedFolders.add(folderId);
    });
    _selAnim.forward();
    _app.onRequestExitSelection = _exitSelection;
    _app.setSelectionMode(true);
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selectedFiles.clear();
      _selectedFolders.clear();
    });
    _selAnim.reverse();
    _app.onRequestExitSelection = null;
    _app.setSelectionMode(false);
  }

  void _selectAll() {
    setState(() {
      _selectedFiles.addAll(_visibleFiles.map((f) => f.id));
      _selectedFolders.addAll(_visibleFolders.map((f) => f.id));
    });
  }

  void _invertSelection() {
    setState(() {
      for (final id in _visibleFiles.map((f) => f.id)) {
        if (!_selectedFiles.remove(id)) _selectedFiles.add(id);
      }
      for (final id in _visibleFolders.map((f) => f.id)) {
        if (!_selectedFolders.remove(id)) _selectedFolders.add(id);
      }
    });
  }

  PreferredSizeWidget _selectionAppBar(int count) => AppBar(
    key: const ValueKey('selection-appbar'),
    leading: IconButton(
      tooltip: context.l10n.exitSelection,
      icon: const Icon(Icons.close),
      onPressed: _exitSelection,
    ),
    title: Text(context.l10n.selectedCount(count)),
    actions: [
      IconButton(
        tooltip: context.l10n.selectAll,
        icon: const Icon(Icons.select_all),
        onPressed: _selectAll,
      ),
      IconButton(
        tooltip: context.l10n.invertSelection,
        icon: const Icon(Icons.flip),
        onPressed: _invertSelection,
      ),
    ],
  );

  Future<void> _openFolder(LzFolder folder) async {
    if (_selecting) {
      setState(() {
        if (!_selectedFolders.remove(folder.id)) _selectedFolders.add(folder.id);
      });
      return;
    }
    if (_directorySwitching) return;
    _directorySwitching = true;
    try {
      final app = context.read<AppController>();
      await app.db.addRecent(
        account: app.activeUid ?? '',
        kind: 'folder',
        name: folder.name,
        ref: folder.id,
        limit: app.settings.recentLimit,
      );
      // 进入新目录时若顶/底栏处于收起状态，先带动画恢复显示，
      // 否则目录内容较少无法滚动时底栏就唤不出来。
      app.animateBarsHide(0);
      _rememberFolderOffset();
      await _animateDirectorySwitch(folder.id);
      if (!mounted) return;
      setState(() {
        _folderId = folder.id;
        _path = [..._path, PathNode(id: folder.id, name: folder.name)];
        _filter = '';
        _searchController.clear();
      });
      await _load();
      if (!mounted) return;
      _restoreFolderOffset(folder.id);
    } finally {
      _directorySwitching = false;
    }
  }

  Future<void> _jumpTo(int index) async {
    if (_directorySwitching) return;
    _directorySwitching = true;
    try {
      final app = context.read<AppController>();
      app.animateBarsHide(0);
      final newPath = index < 0 ? <PathNode>[] : _path.sublist(0, index + 1);
      final targetId = newPath.isEmpty ? '-1' : newPath.last.id;
      _rememberFolderOffset();
      await _animateDirectorySwitch(targetId);
      if (!mounted) return;
      setState(() {
        _path = newPath;
        _folderId = targetId;
        _filter = '';
        _searchController.clear();
      });
      await _load();
      if (!mounted) return;
      _restoreFolderOffset(targetId);
    } finally {
      _directorySwitching = false;
    }
  }

  void _rememberFolderOffset() {
    if (_scroll.hasClients) {
      _folderOffsets[_folderId] = _scroll.position.pixels;
    }
  }

  void _restoreFolderOffset(String folderId) {
    final target = _folderOffsets[folderId] ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        final max = _scroll.position.maxScrollExtent;
        final to = target.clamp(0.0, max);
        final from = _scroll.position.pixels;
        // 回到列表顶部时让悬浮顶栏顺势滑下来（下移显示），
        // 而不是 jumpTo 造成的瞬间出现。
        final slideTopBar = _animationsEnabled &&
            context.read<AppController>().settings.hideTopBar;
        if (slideTopBar && to < from) {
          _scroll.animateTo(
            to,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          );
        } else {
          _scroll.jumpTo(to);
        }
      }
    });
  }

  void _scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// 网盘菜单：底部弹窗承载布局、排序与列表操作。
  Future<void> _showDriveMenu() async {
    final app = context.read<AppController>();
    var grid = app.settings.gridView;
    var sort = _sortMode;
    final isRoot = _folderId == '-1';
    await showAppSheet<void>(
      context,
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.layout,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ConnectedSegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'grid',
                          icon: const Icon(Icons.grid_view),
                          label: Text(context.l10n.grid),
                        ),
                        ButtonSegment(
                          value: 'list',
                          icon: const Icon(Icons.view_list),
                          label: Text(context.l10n.list),
                        ),
                      ],
                      selected: {grid ? 'grid' : 'list'},
                      onSelectionChanged: (values) {
                        final value = values.first;
                        setSheetState(() => grid = value == 'grid');
                        app.setGridView(grid);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.sort,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ConnectedSegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'default',
                          label: Text(context.l10n.sortTime),
                        ),
                        ButtonSegment(
                          value: 'name',
                          label: Text(context.l10n.sortName),
                        ),
                        ButtonSegment(
                          value: 'size',
                          label: Text(context.l10n.sortSize),
                        ),
                      ],
                      selected: {sort},
                      onSelectionChanged: (values) {
                        setSheetState(() => sort = values.first);
                        setState(() => _sortMode = values.first);
                        app.setSortMode(values.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.done_all),
              title: Text(context.l10n.multiSelect),
              onTap: () {
                Navigator.of(context).pop();
                _enterSelection();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(context.l10n.refresh),
              onTap: () {
                Navigator.of(context).pop();
                _reloadAfterChange();
              },
            ),
            if (!isRoot)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(context.l10n.folderProperties),
                onTap: () {
                  Navigator.of(context).pop();
                  showAppSheet<void>(
                    context,
                    child: _FolderInfoSheet(
                      folder: LzFolder(
                        id: _folderId,
                        name: _path.last.name,
                        desc: '',
                      ),
                      page: this,
                    ),
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddMenu() async {
    await showAppSheet<void>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(context.l10n.newFolder),
              onTap: () {
                Navigator.of(context).pop();
                _mkdir();
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: Text(context.l10n.uploadFile),
              onTap: () {
                Navigator.of(context).pop();
                _upload();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_open),
              title: Text(context.l10n.uploadFromApp),
              onTap: () {
                Navigator.of(context).pop();
                _uploadFromApp();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;
    final transfers = context.read<TransferManager>();
    var skipped = 0;
    var added = 0;
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      if (file.size > kFreeUploadLimit) {
        skipped += 1;
        continue;
      }
      transfers.addUpload(
        name: file.name,
        folderId: _folderId,
        path: path,
        size: file.size,
      );
      added += 1;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skipped > 0
              ? context.l10n.uploadSkipped(added, skipped)
              : context.l10n.uploadAdded(added),
        ),
      ),
    );
  }

  /// 从其他应用/文档提供器选取文件上传（ACTION_OPEN_DOCUMENT）。
  Future<void> _uploadFromApp() async {
    try {
      final paths = await ProviderFilePicker.pickFiles();
      if (paths.isEmpty || !mounted) return;
      final transfers = context.read<TransferManager>();
      var added = 0;
      var skipped = 0;
      for (final path in paths) {
        final size = await File(path).length();
        if (size > kFreeUploadLimit) {
          skipped += 1;
          continue;
        }
        transfers.addUpload(
          name: p.basename(path),
          folderId: _folderId,
          path: path,
          size: size,
        );
        added += 1;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skipped > 0
                ? context.l10n.uploadSkipped(added, skipped)
                : context.l10n.uploadTasksAdded(added),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _mkdir() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.newFolder),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(labelText: context.l10n.nameRequired),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: InputDecoration(labelText: context.l10n.descOptional),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.create),
          ),
        ],
      ),
    );
    if (result != true || !mounted) return;
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.folderNameRequired)));
      return;
    }
    try {
      await context.read<AppController>().client?.mkdir(
        _folderId,
        name,
        desc: descController.text.trim(),
      );
      // 局部刷新：只重新拉取文件夹列表，新文件夹淡入出现
      final ok = await _refreshInPlace(refreshFolders: true);
      if (!ok) await _reloadAfterChange();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteSelected() async {
    final count = _selectedFiles.length + _selectedFolders.length;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.deleteConfirmTitle),
        content: Text(context.l10n.deleteConfirmMessage(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final app = context.read<AppController>();
    final client = app.client;
    if (client == null) return;
    final fileIds = _selectedFiles.toList();
    final folderIds = _selectedFolders.toList();
    final fileNames = {for (final f in _files) f.id: f.name};
    final folderNames = {for (final f in _folders) f.id: f.name};
    try {
      await runBatchWithProgress(
        context,
        title: context.l10n.delete,
        total: fileIds.length + folderIds.length,
        run: (report) async {
          var done = 0;
          for (final id in fileIds) {
            report(++done, fileNames[id] ?? '');
            await client.deleteItem(id: id, isFile: true);
          }
          for (final id in folderIds) {
            report(++done, folderNames[id] ?? '');
            await client.deleteItem(id: id, isFile: false);
          }
        },
      );
      await app.db.removeDownloaded([
        for (final id in fileIds) '${app.activeUid ?? ''}:$id',
      ]);
      if (!mounted) return;
      _exitSelection();
      await _removeItemsWithAnimation(
        fileIds: fileIds.toSet(),
        folderIds: folderIds.toSet(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _batchDownload() async {
    if (_selectedFiles.isEmpty) return;
    final app = context.read<AppController>();
    final transfers = context.read<TransferManager>();
    final l10n = context.l10n;
    final ids = _selectedFiles.toList();
    final names = {for (final file in _files) file.id: file.name};
    var failed = 0;
    final messenger = ScaffoldMessenger.of(context);
    await runBatchWithProgress(
      context,
      title: l10n.batchDownload,
      total: ids.length,
      run: (report) async {
        for (var i = 0; i < ids.length; i++) {
          final id = ids[i];
          final name = names[id] ?? '';
          report(i + 1, name);
          try {
            final info = await app.client!.shareInfoOfFile(id);
            final direct = await app.publicClient.resolveFileShare(
              info.url,
              pwd: info.pwd,
            );
            transfers.addDownload(
              url: direct.url,
              name: direct.name.isEmpty ? name : direct.name,
              referer: info.url,
              via: app.publicClient,
              refId: '${app.activeUid ?? ''}:$id',
            );
          } catch (_) {
            failed += 1;
          }
        }
      },
    );
    if (!mounted) return;
    _exitSelection();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? l10n.addedDownloads(ids.length)
              : l10n.addedDownloadsPartial(ids.length - failed, failed),
        ),
      ),
    );
  }

  Future<void> _batchShare() async {
    final fileIds = _selectedFiles.toList();
    final folderIds = _selectedFolders.toList();
    if (fileIds.isEmpty && folderIds.isEmpty) return;
    final app = context.read<AppController>();
    final l10n = context.l10n;
    final lines = <String>[];
    final fileNames = {for (final f in _files) f.id: f.name};
    final folderNames = {for (final f in _folders) f.id: f.name};
    await runBatchWithProgress(
      context,
      title: l10n.share,
      total: fileIds.length + folderIds.length,
      run: (report) async {
        var done = 0;
        for (final id in fileIds) {
          final name = fileNames[id] ?? '';
          report(++done, name);
          try {
            final info = await app.client!.shareInfoOfFile(id);
            lines.add(
              info.pwd.isEmpty
                  ? '$name ${info.url}'
                  : l10n.linkWithPassword('$name ${info.url}', info.pwd),
            );
          } catch (_) {}
        }
        for (final id in folderIds) {
          final name = folderNames[id] ?? '';
          report(++done, name);
          try {
            final info = await app.client!.shareInfoOfFolder(id);
            final linkName = info.name.isEmpty ? name : info.name;
            lines.add(
              info.pwd.isEmpty
                  ? '$linkName ${info.url}'
                  : l10n.linkWithPassword('$linkName ${info.url}', info.pwd),
            );
          } catch (_) {}
        }
      },
    );
    if (!mounted) return;
    _exitSelection();
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.noLinksToCopy)),
      );
      return;
    }
    await copyText(context, lines.join('\n'));
  }

  Future<void> _batchFavorite() async {
    final app = context.read<AppController>();
    final client = app.client;
    final sharer = app.activeAccount?.nickname ?? '';
    final fileIds = _selectedFiles.toList();
    final folderIds = _selectedFolders.toList();
    var count = 0;
    var failed = 0;
    if (client != null) {
      final files = {for (final f in _files) f.id: f};
      final folders = {for (final f in _folders) f.id: f};
      await runBatchWithProgress(
        context,
        title: context.l10n.favorite,
        total: fileIds.length + folderIds.length,
        run: (report) async {
          var done = 0;
          for (final id in fileIds) {
            final file = files[id];
            report(++done, file?.name ?? '');
            try {
              final info = await client.shareInfoOfFile(id);
              await app.db.addFavorite(
                kind: 'shareFile',
                name: file?.name ?? '',
                ref: info.url,
                pwd: info.pwd,
                size: file?.size ?? '',
                sharer: sharer,
              );
              count += 1;
            } catch (_) {
              failed += 1;
            }
          }
          for (final id in folderIds) {
            final folder = folders[id];
            report(++done, folder?.name ?? '');
            try {
              final info = await client.shareInfoOfFolder(id);
              await app.db.addFavorite(
                kind: 'shareFolder',
                name: folder?.name ?? '',
                ref: info.url,
                pwd: info.pwd,
                sharer: sharer,
              );
              count += 1;
            } catch (_) {
              failed += 1;
            }
          }
        },
      );
    }
    if (mounted) _exitSelection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? context.l10n.favoritedCount(count)
              : context.l10n.favoritedPartial(count, failed),
        ),
      ),
    );
  }

  Future<void> _batchMore() async {
    final action = await showAppSheet<String>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(context.l10n.move),
              subtitle: Text(context.l10n.moveSubtitle),
              onTap: () => Navigator.of(context).pop('move'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(context.l10n.editDesc),
              subtitle: Text(context.l10n.editDescBatchSubtitle),
              onTap: () => Navigator.of(context).pop('desc'),
            ),
            ListTile(
              leading: const Icon(Icons.password),
              title: Text(context.l10n.setPassword),
              subtitle: Text(context.l10n.setPasswordSubtitle),
              onTap: () => Navigator.of(context).pop('pwd'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'move') await _batchMove();
    if (action == 'desc') await _batchSetDesc();
    if (action == 'pwd') await _batchSetPasswd();
  }

  Future<void> _batchMove() async {
    final app = context.read<AppController>();
    final client = app.client;
    if (client == null) return;
    final fileIds = _selectedFiles.toList();
    final folderIds = _selectedFolders.toList();
    if (fileIds.isEmpty && folderIds.isEmpty) return;
    final target = await showFolderPicker(
      context,
      client: client,
      excludeIds: {...fileIds, ...folderIds},
    );
    if (target == null || !mounted) return;
    final fileNames = {for (final f in _files) f.id: f.name};
    final folderNames = {for (final f in _folders) f.id: f.name};
    var failed = 0;
    await runBatchWithProgress(
      context,
      title: context.l10n.move,
      total: fileIds.length + folderIds.length,
      run: (report) async {
        var done = 0;
        for (final id in fileIds) {
          report(++done, fileNames[id] ?? '');
          try {
            await client.moveFile(id, target.folderId);
          } catch (_) {
            failed += 1;
          }
        }
        for (final id in folderIds) {
          report(++done, folderNames[id] ?? '');
          try {
            await client.moveFolder(id, target.folderId);
          } catch (_) {
            failed += 1;
          }
        }
      },
    );
    if (!mounted) return;
    final count = fileIds.length + folderIds.length;
    _exitSelection();
    // 局部刷新：移走的条目原位淡出，其余条目保持不动
    final ok = await _refreshInPlace(refreshFolders: true);
    if (!ok) await _reloadAfterChange();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? context.l10n.movedTo(count, target.name)
              : context.l10n.movedPartial(count - failed, failed),
        ),
      ),
    );
  }

  Future<void> _batchSetDesc() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.editDesc),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: InputDecoration(hintText: context.l10n.newDescHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final client = context.read<AppController>().client;
    if (client == null) return;
    final fileIds = _selectedFiles.toList();
    final folderIds = _selectedFolders.toList();
    final fileNames = {for (final f in _files) f.id: f.name};
    final folderNames = {for (final f in _folders) f.id: f.name};
    var failed = 0;
    await runBatchWithProgress(
      context,
      title: context.l10n.editDesc,
      total: fileIds.length + folderIds.length,
      run: (report) async {
        var done = 0;
        for (final id in fileIds) {
          report(++done, fileNames[id] ?? '');
          try {
            await client.setDesc(id, controller.text.trim());
          } catch (_) {
            failed += 1;
          }
        }
        for (final id in folderIds) {
          report(++done, folderNames[id] ?? '');
          try {
            await client.setFolderDesc(id, controller.text.trim());
          } catch (_) {
            failed += 1;
          }
        }
      },
    );
    if (!mounted) return;
    final count = fileIds.length + folderIds.length;
    _exitSelection();
    _fileDescCache.clear();
    _folderDescCache.clear();
    final desc = controller.text.trim();
    setState(() {
      _files = [
        for (final f in _files)
          fileIds.contains(f.id)
              ? LzFile(
                  id: f.id,
                  name: f.name,
                  time: f.time,
                  size: f.size,
                  downs: f.downs,
                  hasPwd: f.hasPwd,
                  hasDes: true,
                )
              : f,
      ];
      _folders = [
        for (final fo in _folders)
          folderIds.contains(fo.id)
              ? LzFolder(
                  id: fo.id,
                  name: fo.name,
                  desc: desc,
                  hasPwd: fo.hasPwd,
                )
              : fo,
      ];
    });
    _pulseItems(
      fileIds: fileIds.toSet(),
      folderIds: folderIds.toSet(),
    );
    _updateCacheSnapshot();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? context.l10n.descUpdatedCount(count)
              : context.l10n.descUpdatedPartial(count - failed, failed),
        ),
      ),
    );
  }

  Future<void> _batchSetPasswd() async {
    // 批量不逐项取密码，默认按“启用”打开（留空即关闭）
    final result = await showPasswordDialog(
      context,
      enabled: true,
      pwd: '',
    );
    if (result == null || !mounted) return;
    final pwd = result.enabled ? result.pwd : '';
    final client = context.read<AppController>().client;
    if (client == null) return;
    final fileIds = _selectedFiles.toList();
    final folderIds = _selectedFolders.toList();
    final fileNames = {for (final f in _files) f.id: f.name};
    final folderNames = {for (final f in _folders) f.id: f.name};
    var failed = 0;
    await runBatchWithProgress(
      context,
      title: context.l10n.setPassword,
      total: fileIds.length + folderIds.length,
      run: (report) async {
        var done = 0;
        for (final id in fileIds) {
          report(++done, fileNames[id] ?? '');
          try {
            await client.setPasswd(id, pwd);
          } catch (_) {
            failed += 1;
          }
        }
        for (final id in folderIds) {
          report(++done, folderNames[id] ?? '');
          try {
            await client.setFolderPasswd(id, pwd);
          } catch (_) {
            failed += 1;
          }
        }
      },
    );
    if (!mounted) return;
    final count = fileIds.length + folderIds.length;
    _exitSelection();
    if (!mounted) return;
    setState(() {
      _files = [
        for (final f in _files)
          fileIds.contains(f.id)
              ? LzFile(
                  id: f.id,
                  name: f.name,
                  time: f.time,
                  size: f.size,
                  downs: f.downs,
                  hasPwd: pwd.isNotEmpty,
                  hasDes: f.hasDes,
                )
              : f,
      ];
      _folders = [
        for (final fo in _folders)
          folderIds.contains(fo.id)
              ? LzFolder(
                  id: fo.id,
                  name: fo.name,
                  desc: fo.desc,
                  hasPwd: pwd.isNotEmpty,
                )
              : fo,
      ];
    });
    _pulseItems(
      fileIds: fileIds.toSet(),
      folderIds: folderIds.toSet(),
    );
    _updateCacheSnapshot();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? (pwd.isEmpty
                    ? context.l10n.passwordClearedCount(count)
                    : context.l10n.passwordSetCount(count))
              : context.l10n.passwordSetPartial(count - failed, failed),
        ),
      ),
    );
  }

  Future<void> _openShareInBrowser(LzFile file) async {
    final app = context.read<AppController>();
    final client = app.client;
    if (client == null) return;
    try {
      final info = await client.shareInfoOfFile(file.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WebPage(
            title: file.name,
            url: info.url,
            cookie: app.activeAccount?.cookie,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openFolderShareInBrowser(LzFolder folder) async {
    final app = context.read<AppController>();
    final client = app.client;
    if (client == null) return;
    try {
      final info = await client.shareInfoOfFolder(folder.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WebPage(
            title: folder.name,
            url: info.url,
            cookie: app.activeAccount?.cookie,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// 本地生成二维码（不经过任何服务器）。
  Future<void> _showQr(String title, String url, String pwd) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: url,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(url, style: Theme.of(context).textTheme.bodySmall),
            if (pwd.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(context.l10n.passwordLabel(pwd)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.close),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              copyText(context, url);
            },
            child: Text(context.l10n.copyLink),
          ),
        ],
      ),
    );
  }

  Future<void> _showFileQr(LzFile file) async {
    final client = context.read<AppController>().client;
    if (client == null) return;
    try {
      final info = await client.shareInfoOfFile(file.id);
      if (!mounted) return;
      await _showQr(file.name, info.url, info.pwd);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _showFolderQr(LzFolder folder) async {
    final client = context.read<AppController>().client;
    if (client == null) return;
    try {
      final info = await client.shareInfoOfFolder(folder.id);
      if (!mounted) return;
      await _showQr(folder.name, info.url, info.pwd);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _fileActions(LzFile file) async {
    await _showFileProperties(file);
  }

  /// 点文件本身：属性弹窗（属性、链接、二维码、下载、收藏）
  Future<void> _showFileProperties(LzFile file) async {
    if (file.hasDes && !_fileDescCache.containsKey(file.id)) {
      try {
        final client = context.read<AppController>().client;
        if (client != null) {
          final desc = await client.fileDesc(file.id);
          if (desc.isNotEmpty) _fileDescCache[file.id] = desc;
        }
      } catch (_) {}
      if (!mounted) return;
    }
    if (_selecting) {
      setState(() {
        if (!_selectedFiles.remove(file.id)) _selectedFiles.add(file.id);
      });
      return;
    }
    // 与文件夹属性等弹窗保持一致：统一使用 showAppSheet（内容自适应高度 +
    // 到顶后继续下拉带走弹窗的手感）
    await showAppSheet<void>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            PropertyHeaderCard(
              icon: iconForFile(file.name),
              title: file.name,
              subtitle: [
                if (file.size.isNotEmpty) prettyLzSize(file.size),
                if (file.time.isNotEmpty) file.time,
                if (file.downs > 0) context.l10n.downloadsCount(file.downs),
                if (file.hasPwd) context.l10n.hasPassword,
              ].join(' · '),
              desc: _fileDescCache[file.id] ?? '',
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(context.l10n.download),
              onTap: () {
                Navigator.of(context).pop();
                _downloadOwnFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: Text(context.l10n.copyLink),
              onTap: () {
                Navigator.of(context).pop();
                _copyShareLink(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(context.l10n.openLink),
              onTap: () {
                Navigator.of(context).pop();
                _openShareInBrowser(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code),
              title: Text(context.l10n.showQr),
              onTap: () {
                Navigator.of(context).pop();
                _showFileQr(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: Text(context.l10n.addFavorite),
              onTap: () {
                Navigator.of(context).pop();
                _favoriteFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(context.l10n.delete),
              onTap: () {
                Navigator.of(context).pop();
                _deleteFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.more_horiz),
              title: Text(context.l10n.moreActions),
              onTap: () {
                Navigator.of(context).pop();
                _fileMenuSheet(file);
              },
            ),
        ],
      ),
    );
  }

  /// 点 ⋯：操作弹窗（常用操作）
  Future<void> _fileMenuSheet(LzFile file) async {
    if (_selecting) {
      setState(() {
        if (!_selectedFiles.remove(file.id)) _selectedFiles.add(file.id);
      });
      return;
    }
    await showAppSheet<void>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(context.l10n.move),
              onTap: () {
                Navigator.of(context).pop();
                _moveSingleFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(context.l10n.editDesc),
              onTap: () {
                Navigator.of(context).pop();
                _singleSetDesc(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.password),
              title: Text(context.l10n.setPassword),
              onTap: () {
                Navigator.of(context).pop();
                _singleSetPasswd(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(context.l10n.delete),
              onTap: () {
                Navigator.of(context).pop();
                _deleteFile(file);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _moveSingleFile(LzFile file) async {
    final app = context.read<AppController>();
    final client = app.client;
    if (client == null) return;
    final target = await showFolderPicker(
      context,
      client: client,
      excludeIds: {file.id},
    );
    if (target == null || !mounted) return;
    try {
      await client.moveFile(file.id, target.folderId);
      // 局部刷新：被移走的条目原位淡出
      final ok = await _refreshInPlace(refreshFolders: true);
      if (!ok) await _reloadAfterChange();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.movedTo(1, target.name))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _singleSetDesc(LzFile file) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.editDesc),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: InputDecoration(hintText: context.l10n.newDescHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context
          .read<AppController>()
          .client
          ?.setDesc(file.id, controller.text.trim());
      if (!mounted) return;
      _fileDescCache.remove(file.id);
      setState(() {
        _files = [
          for (final f in _files)
            f.id == file.id
                ? LzFile(
                    id: f.id,
                    name: f.name,
                    time: f.time,
                    size: f.size,
                    downs: f.downs,
                    hasPwd: f.hasPwd,
                    hasDes: true,
                  )
                : f,
        ];
      });
      _pulseItems(fileIds: {file.id});
      _updateCacheSnapshot();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.descUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _singleSetPasswd(LzFile file) async {
    final client = context.read<AppController>().client;
    if (client == null) return;
    // 先取当前是否启用与密码，用于预填开关和输入框
    final navigator = Navigator.of(context);
    showLoadingDialog(context, context.l10n.resolving);
    String currentPwd = '';
    try {
      currentPwd = (await client.shareInfoOfFile(file.id)).pwd;
    } catch (_) {
      // 取不到就按未启用处理
    } finally {
      navigator.pop();
    }
    if (!mounted) return;
    final result = await showPasswordDialog(
      context,
      enabled: currentPwd.isNotEmpty,
      pwd: currentPwd,
    );
    if (result == null || !mounted) return;
    final pwd = result.enabled ? result.pwd : '';
    try {
      await client.setPasswd(file.id, pwd);
      if (!mounted) return;
      setState(() {
        _files = [
          for (final f in _files)
            f.id == file.id
                ? LzFile(
                    id: f.id,
                    name: f.name,
                    time: f.time,
                    size: f.size,
                    downs: f.downs,
                    hasPwd: pwd.isNotEmpty,
                    hasDes: f.hasDes,
                  )
                : f,
        ];
      });
      _pulseItems(fileIds: {file.id});
      _updateCacheSnapshot();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pwd.isEmpty ? context.l10n.passwordCleared : context.l10n.passwordSet,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// 文件夹改名 / 简介 / 密码变化后同步到列表、路径与缓存。
  void _applyFolderUpdate(
    String folderId, {
    String? name,
    String? desc,
    bool? hasPwd,
  }) {
    setState(() {
      _folders = [
        for (final folder in _folders)
          folder.id == folderId
              ? LzFolder(
                  id: folder.id,
                  name: name ?? folder.name,
                  desc: desc ?? folder.desc,
                  hasPwd: hasPwd ?? folder.hasPwd,
                )
              : folder,
      ];
      if (name != null) {
        _path = [
          for (final node in _path)
            node.id == folderId ? PathNode(id: node.id, name: name) : node,
        ];
      }
    });
    if (desc != null) _folderDescCache[folderId] = desc;
    _pulseItems(folderIds: {folderId});
    _updateCacheSnapshot();
  }

  /// 文件夹访问密码：先取当前是否启用与密码，再弹开关 + 密码框。
  Future<void> _setFolderPasswd(LzFolder folder) async {
    final client = context.read<AppController>().client;
    if (client == null) return;
    final navigator = Navigator.of(context);
    showLoadingDialog(context, context.l10n.resolving);
    var currentPwd = '';
    try {
      currentPwd = (await client.shareInfoOfFolder(folder.id)).pwd;
    } catch (_) {
      // 取不到就按未启用处理
    } finally {
      navigator.pop();
    }
    if (!mounted) return;
    final result = await showPasswordDialog(
      context,
      enabled: currentPwd.isNotEmpty,
      pwd: currentPwd,
    );
    if (result == null || !mounted) return;
    final pwd = result.enabled ? result.pwd : '';
    try {
      await client.setFolderPasswd(folder.id, pwd);
      if (!mounted) return;
      _applyFolderUpdate(folder.id, hasPwd: pwd.isNotEmpty);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pwd.isEmpty
                ? context.l10n.passwordCleared
                : context.l10n.passwordSet,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// 修改文件夹信息（名称 + 简介），成功后返回新值给调用方刷新弹窗。
  Future<({String name, String desc})?> _editFolderInfo(
    LzFolder folder,
  ) async {
    final client = context.read<AppController>().client;
    if (client == null) return null;
    final nameController = TextEditingController(text: folder.name);
    final descController = TextEditingController(text: folder.desc);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.folderInfo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.l10n.nameRequired,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: InputDecoration(
                labelText: context.l10n.descOptional,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.confirm),
          ),
        ],
      ),
    );
    final name = nameController.text.trim();
    final desc = descController.text.trim();
    nameController.dispose();
    descController.dispose();
    if (ok != true || !mounted) return null;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.folderNameRequired)),
      );
      return null;
    }
    try {
      await client.setFolderInfo(folder.id, name: name, desc: desc);
      if (!mounted) return null;
      _applyFolderUpdate(folder.id, name: name, desc: desc);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.folderInfoSaved)),
      );
      return (name: name, desc: desc);
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return null;
    }
  }

  Future<void> _folderActions(LzFolder folder) async {
    if (_selecting) {
      setState(() {
        if (!_selectedFolders.remove(folder.id)) _selectedFolders.add(folder.id);
      });
      return;
    }
    await showAppSheet<void>(
      context,
      child: _FolderInfoSheet(folder: folder, page: this),
    );
  }

  Future<void> _downloadOwnFile(LzFile file) async {
    final app = context.read<AppController>();
    final transfers = context.read<TransferManager>();
    final client = app.client;
    if (client == null) return;
    try {
      final info = await client.shareInfoOfFile(file.id);
      if (!mounted) return;
      final direct = await app.publicClient.resolveFileShare(
        info.url,
        pwd: info.pwd,
      );
      transfers.addDownload(
        url: direct.url,
        name: direct.name.isEmpty ? file.name : direct.name,
        referer: info.url,
        via: app.publicClient,
        refId: '${app.activeUid ?? ''}:${file.id}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.addedToQueue)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _copyShareLink(LzFile file) async {
    final client = context.read<AppController>().client;
    if (client == null) return;
    try {
      final info = await client.shareInfoOfFile(file.id);
      if (!mounted) return;
      await copyText(
        context,
        info.pwd.isEmpty
            ? info.url
            : context.l10n.linkWithPassword(info.url, info.pwd),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _copyFolderShareLink(LzFolder folder) async {
    final client = context.read<AppController>().client;
    if (client == null) return;
    try {
      final info = await client.shareInfoOfFolder(folder.id);
      if (!mounted) return;
      await copyText(
        context,
        info.pwd.isEmpty
            ? info.url
            : context.l10n.linkWithPassword(info.url, info.pwd),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _favoriteFile(LzFile file) async {
    final app = context.read<AppController>();
    final client = app.client;
    if (client == null) return;
    try {
      final info = await client.shareInfoOfFile(file.id);
      await app.db.addFavorite(
        kind: 'shareFile',
        name: file.name,
        ref: info.url,
        pwd: info.pwd,
        size: file.size,
        sharer: app.activeAccount?.nickname ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.favorited)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _favoriteFolder(LzFolder folder) async {
    final app = context.read<AppController>();
    final client = app.client;
    if (client == null) return;
    try {
      final info = await client.shareInfoOfFolder(folder.id);
      await app.db.addFavorite(
        kind: 'shareFolder',
        name: folder.name,
        ref: info.url,
        pwd: info.pwd,
        sharer: app.activeAccount?.nickname ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.favorited)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteFile(LzFile file) async {
    final app = context.read<AppController>();
    final client = app.client;
    if (client == null) return;
    try {
      await client.deleteItem(id: file.id, isFile: true);
      await app.db.removeDownloaded(['${app.activeUid ?? ''}:${file.id}']);
      if (!mounted) return;
      _fileDescCache.remove(file.id);
      await _removeItemsWithAnimation(fileIds: {file.id});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteFolder(LzFolder folder) async {
    final app = context.read<AppController>();
    final client = app.client;
    if (client == null) return;
    try {
      await client.deleteItem(id: folder.id, isFile: false);
      if (!mounted) return;
      _folderDescCache.remove(folder.id);
      _folderSizeCache.remove(folder.id);
      await _removeItemsWithAnimation(folderIds: {folder.id});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.watch<AppController>();
    final grid = app.settings.gridView;
    final selectedCount = _selectedFiles.length + _selectedFolders.length;
    final headerHeight = MediaQuery.paddingOf(context).top + kToolbarHeight + 46;
    // 底部被占住的高度（外壳底栏 / 系统导航栏），用来把 FAB 抬到它上面。
    // 必须在页面上下文里读：FAB 槽位的 MediaQuery 已经把底部内边距清掉了。
    final bottomObstruction = bottomObstructionHeight(context);
    // 悬浮胶囊只在外壳里有；独立页面按系统导航栏避让即可。
    final floatingNavInShell =
        inRootShell(context) && app.settings.floatingNavBar;

    return AnimatedBuilder(
      animation: Listenable.merge([_selAnim, _exitAnim]),
      builder: (context, _) {
        return Scaffold(
          // 大屏外壳里的页面：背景交给外壳的圆角卡片
          backgroundColor:
              transparentPageBackground(context) ? Colors.transparent : null,
          // 键盘弹出时不压缩页面：搜索框在顶栏，页面由外层底栏 Scaffold
          // 压到键盘上沿即可（FAB 的留白见 floatingActionButton）
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              _buildBody(grid),
              // 顶栏浮层：与底栏共用收起进度，切换视图时会下滑出现
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: TopBarOverlay(
                  height: headerHeight,
                  background: topBarBackgroundColor(
                    context,
                    Theme.of(context).colorScheme,
                  ),
                  // 显式高度：带 bottom（路径栏）的 AppBar 需要有限高度约束
                  builder: (context) => SizedBox(
                    height: headerHeight,
                    child: _topBar(context),
                  ),
                ),
              ),
              // 多选时只覆盖顶栏；路径栏保持可见，平时透明且不拦截点击
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: IgnorePointer(
                  ignoring: !_selecting,
                  child: Opacity(
                    opacity: _selAnim.value,
                    child: Material(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surface,
                      // 显式高度：Stack 的 Positioned 不提供高度约束
                      child: SizedBox(
                        height:
                            MediaQuery.paddingOf(context).top + kToolbarHeight,
                        child: _selectionAppBar(selectedCount),
                      ),
                    ),
                  ),
                ),
              ),
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
                          label: context.l10n.delete,
                          onPressed:
                              selectedCount == 0 ? null : _deleteSelected,
                        ),
                        BatchAction(
                          icon: Icons.download_outlined,
                          label: context.l10n.download,
                          onPressed: _selectedFiles.isEmpty
                              ? null
                              : _batchDownload,
                        ),
                        BatchAction(
                          icon: Icons.share_outlined,
                          label: context.l10n.share,
                          onPressed: selectedCount == 0 ? null : _batchShare,
                        ),
                        BatchAction(
                          icon: Icons.star_outline,
                          label: context.l10n.favorite,
                          onPressed:
                              selectedCount == 0 ? null : _batchFavorite,
                        ),
                        BatchAction(
                          icon: Icons.more_horiz,
                          label: context.l10n.more,
                          onPressed: selectedCount == 0 ? null : _batchMore,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
      floatingActionButton: ValueListenableBuilder<double>(
        valueListenable: app.barsHide,
        builder: (context, hide, child) {
          // 只跟随“底栏收起”设置：底栏跟随滚动时 FAB 也同步下滑，
          // 多选等程序化隐藏则用补间动画，方向统一为上滑显示、下滑消失。
          final follow = app.settings.hideBottomBar
              ? hide.clamp(0.0, 1.0)
              : 0.0;
          return ValueListenableBuilder<bool>(
            valueListenable: _keyboardUp,
            builder: (context, keyboardUp, _) {
              // 悬浮底栏留白：键盘弹出时底栏沉在键盘下方、屏幕上看不见，
              // 此时页面已被外层 Scaffold 压到键盘上沿，FAB 停在键盘上方即可，
              // 不能再叠加底栏高度，否则会高出约一个底栏的距离。
              // 普通底栏同理：外壳开了 extendBody 后，FAB 按系统手势区
              // 算出来的位置会落到底栏下面，这里按底栏总高度把它抬回去。
              // 悬浮样式的胶囊自带上下留白（16 / 12），减 20 后落在胶囊上沿之上。
              final lift = keyboardUp
                  ? 0.0
                  : math.max(
                      0.0,
                      floatingNavInShell
                          ? bottomObstruction - 20.0
                          : bottomObstruction,
                    );
              return AnimatedPadding(
                padding: EdgeInsets.only(bottom: lift),
                duration: _anim,
                curve: Curves.easeOutCubic,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _selecting ? 1.0 : 0.0),
                  duration: _anim,
                  curve: Curves.easeOutCubic,
                  builder: (context, selecting, child) {
                    final t = math.max(selecting, follow);
                    return IgnorePointer(
                      ignoring: t > 0.85,
                      child: Opacity(
                        opacity: (1 - t).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, 150 * t),
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: FloatingActionButton.extended(
                    onPressed: _showAddMenu,
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.add),
                  ),
                ),
              );
            },
          );
        },
      ),
        );
      },
    );
  }

  /// 顶栏（含路径栏）：作为浮层显示，与底栏共用收起进度。
  Widget _topBar(BuildContext context) {
    // 点顶栏空白处回到列表顶部（子级按钮 / 路径胶囊自行响应，不会误触）
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _scrollToTop,
      child: AppBar(
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
      leading: (ModalRoute.of(context)?.isFirst ?? true)
          ? null
          : IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
      title: _searching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.l10n.searchCurrentFolder,
                border: InputBorder.none,
              ),
              onChanged: (value) => setState(() => _filter = value.trim()),
            )
          : Text(context.l10n.tabDrive),
      actions: _searching
          ? [
              IconButton(
                tooltip: context.l10n.closeSearch,
                icon: const Icon(Icons.close),
                onPressed: _closeSearch,
              ),
            ]
          : [
              IconButton(
                tooltip: context.l10n.search,
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _searching = true),
              ),
              IconButton(
                tooltip: context.l10n.menu,
                icon: const Icon(Icons.more_vert),
                onPressed: _showDriveMenu,
              ),
            ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(kDrivePathBarHeight),
        // 多选期间禁用路径切换，但路径栏保持可见；
        // bottom 拿到的是无界高度，必须自己声明固定高度，否则会把工具栏挤成 0
        child: SizedBox(
          height: 46,
          child: IgnorePointer(
            ignoring: _selecting,
            child: _pathBar(),
          ),
        ),
      ),
      ),
    );
  }

  /// 顶栏不参与列表布局，列表顶部留出等高占位。
  Widget _buildBody(bool grid) {
    final headerInset =
        MediaQuery.of(context).padding.top + kToolbarHeight + 46;
    final app = context.read<AppController>();
    return ScrollTint(
      hideDistance: headerInset,
      readBarsHidden: () => app.topBarHide.value,
      onBarsHidden:
          app.settings.hideTopBar ? app.setTopBarHideFromScroll : null,
      child: drive_refresh.LanRefreshIndicator(
        onRefresh: _reloadAfterChange,
        edgeOffset: headerInset,
        child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: headerInset)),
          // 目录切换时内容整体淡出（顶栏与路径栏不受影响）
          ..._contentSlivers(grid).map(
            (sliver) => SliverFadeTransition(
              opacity: _contentFade,
              sliver: sliver,
            ),
          ),
            ],
          ),
      ),
    );
  }

  Widget _pathBar() {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (var i = -1; i < _path.length; i++) ...[
            if (i >= 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: scheme.outline,
                ),
              ),
            PathChip(
              label: i < 0 ? context.l10n.root : _path[i].name,
              current: i == _path.length - 1,
              // 点当前目录 = 刷新；点上一级 = 返回该目录
              onTap: () => i == _path.length - 1
                  ? _reloadAfterChange()
                  : _jumpTo(i),
            ),
          ],
        ],
      ),
    );
  }

  /// 顶栏与路径栏之外的剩余 slivers，按加载状态切换。
  List<Widget> _contentSlivers(bool grid) {
    // 底栏盖在正文上方（extendBody）时，各种占满高度的空状态
    // 要靠这份留白保持在可见区域居中，而不是被底栏压住。
    final cover = shellBottomBarInset(context);
    if (_loading) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: cover),
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: cover),
            child: FadeIn(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off,
                        size: 40,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.loadFailed(_error!),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => _load(force: true),
                        child: Text(context.l10n.retry),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ];
    }
    final folders = _visibleFolders;
    final files = _visibleFiles;
    if (folders.isEmpty && files.isEmpty && !_loadingMore) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: cover),
            child: _EmptyFolderView(filter: _filter),
          ),
        ),
      ];
    }
    final showFolders = _filter.isEmpty || folders.isNotEmpty;
    final animate = _animationsEnabled;
    return [
      if (showFolders && folders.isNotEmpty)
        if (grid)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.86,
              ),
              itemCount: folders.length,
              itemBuilder: (context, index) => _folderItem(
                folders[index],
                index,
                grid: true,
                animate: animate,
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: folders.length,
            itemBuilder: (context, index) => _folderItem(
              folders[index],
              index,
              grid: false,
              animate: animate,
            ),
          ),
      if (files.isNotEmpty)
        if (grid)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.86,
              ),
              itemCount: files.length,
              itemBuilder: (context, index) => _fileItem(
                files[index],
                index,
                grid: true,
                animate: animate,
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: files.length,
            itemBuilder: (context, index) => _fileItem(
              files[index],
              index,
              grid: false,
              animate: animate,
            ),
          ),
      SliverToBoxAdapter(
        child: Padding(
          // 外壳里给底栏（悬浮胶囊 / 收起）让位；作为独立页面打开时
          // 末尾由 shellBottomBarInset 按系统导航栏补，只留常规留白
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            inRootShell(context) ? 96 : 16,
          ),
          child: Center(
            child: _loadingMore
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _hasMore
                        ? ''
                        : (_filter.isEmpty
                            ? context.l10n.reachedEnd
                            : context.l10n.filterResult),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
          ),
        ),
      ),
      // 底栏盖在正文上方（extendBody）时，补足列表末尾留白
      SliverToBoxAdapter(
        child: SizedBox(height: shellBottomBarInset(context)),
      ),
    ];
  }

  /// 单个文件夹条目的动画包装（共享错峰控制器 + 局部刷新动画）。
  Widget _folderItem(
    LzFolder folder,
    int index, {
    required bool grid,
    required bool animate,
  }) {
    return _AnimatedListItem(
      key: ValueKey('$_folderId-f-${folder.id}'),
      index: index,
      enter: _enterAnim,
      enabled: animate,
      removing: _removingFolders.contains(folder.id),
      appearing: _appearingFolders.contains(folder.id),
      pulsing: _pulsingFolders.contains(folder.id),
      collapse: !grid,
      child: grid
          ? _FolderTile(
              folder: folder,
              selected: _selectedFolders.contains(folder.id),
              onTap: () => _openFolder(folder),
              onMenu: () => _folderActions(folder),
              onLongPress: () => _enterSelection(folderId: folder.id),
            )
          : _FolderRow(
              folder: folder,
              selected: _selectedFolders.contains(folder.id),
              onTap: () => _openFolder(folder),
              onMenu: () => _folderActions(folder),
              onLongPress: () => _enterSelection(folderId: folder.id),
            ),
    );
  }

  /// 单个文件条目的动画包装。
  Widget _fileItem(
    LzFile file,
    int index, {
    required bool grid,
    required bool animate,
  }) {
    return _AnimatedListItem(
      key: ValueKey('$_folderId-l-${file.id}'),
      index: index,
      enter: _enterAnim,
      enabled: animate,
      removing: _removingFiles.contains(file.id),
      appearing: _appearingFiles.contains(file.id),
      pulsing: _pulsingFiles.contains(file.id),
      collapse: !grid,
      child: grid
          ? _FileTile(
              file: file,
              selected: _selectedFiles.contains(file.id),
              onTap: () => _fileActions(file),
              onMenu: () => _fileMenuSheet(file),
              onLongPress: () => _enterSelection(fileId: file.id),
            )
          : _FileRow(
              file: file,
              selected: _selectedFiles.contains(file.id),
              onTap: () => _fileActions(file),
              onMenu: () => _fileMenuSheet(file),
              onLongPress: () => _enterSelection(fileId: file.id),
            ),
    );
  }
}

/// 列表项动画：
/// - [enter] 目录加载后的错峰出现（整张列表共享一个控制器，
///   滑到新构建的条目时只会读到当前进度，不会重播动画）；
/// - [appearing] 局部刷新新增条目的淡入；
/// - [removing] 移除前的淡出（列表模式同时收起高度，条目平滑收拢）；
/// - [pulsing] 修改描述/密码后的高亮闪烁。
class _AnimatedListItem extends StatelessWidget {
  const _AnimatedListItem({
    super.key,
    required this.index,
    required this.enter,
    required this.enabled,
    required this.child,
    this.appearing = false,
    this.removing = false,
    this.pulsing = false,
    this.collapse = false,
  });

  final int index;
  /// 目录进入动画的共享进度（0..1，动画结束后为 1）。
  final Animation<double> enter;
  final bool enabled;
  final Widget child;
  final bool appearing;
  final bool removing;
  final bool pulsing;
  final bool collapse;

  /// 与控制器时长一致，用于把共享进度换算成单项的错峰区间。
  static const double _enterDuration = 440;
  static const double _enterItemDuration = 232;
  static const double _enterStep = 26;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    var item = child;

    if (removing) {
      item = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInCubic,
        builder: (context, t, child) {
          final faded = Opacity(
            opacity: (1 - t).clamp(0.0, 1.0),
            child: Transform.scale(scale: 1 - 0.06 * t, child: child),
          );
          if (!collapse) return faded;
          return Align(
            heightFactor: (1 - t).clamp(0.0, 1.0),
            alignment: Alignment.topCenter,
            child: faded,
          );
        },
        child: item,
      );
    } else if (appearing) {
      item = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
        ),
        child: item,
      );
    }

    if (pulsing) {
      final scheme = Theme.of(context).colorScheme;
      item = TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOut,
        builder: (context, t, child) => Stack(
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.16 * t),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        child: item,
      );
    }

    if (removing || appearing) return item;
    // 共享错峰出现：动画结束后进度恒为 1，之后滑动出来的条目直接显示。
    return AnimatedBuilder(
      animation: enter,
      child: item,
      builder: (context, child) {
        final delay = index.clamp(0, 8) * _enterStep;
        final progress =
            ((enter.value * _enterDuration - delay) / _enterItemDuration)
                .clamp(0.0, 1.0);
        final t = Curves.easeOutCubic.transform(progress);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

/// 空目录 / 无匹配结果：整块居中显示并带显隐渐变。
class _EmptyFolderView extends StatelessWidget {
  const _EmptyFolderView({required this.filter});

  final String filter;

  @override
  Widget build(BuildContext context) {
    return EmptyHint(
      icon: Icons.folder_open,
      text: filter.isEmpty
          ? context.l10n.emptyFolder
          : context.l10n.noMatchContent(filter),
    );
  }
}

/// 一次目录拉取的结果。
class _Listing {
  const _Listing({
    required this.folders,
    required this.files,
    required this.path,
    required this.page,
    required this.hasMore,
  });

  final List<LzFolder> folders;
  final List<LzFile> files;
  final List<PathNode> path;
  final int page;
  final bool hasMore;
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.selected,
    required this.onTap,
    required this.onMenu,
    required this.onLongPress,
  });

  final LzFolder folder;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color:
          selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.surface
                          : scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      selected ? Icons.check_circle : Icons.folder,
                      size: 21,
                      color: selected
                          ? scheme.primary
                          : scheme.primary.withValues(alpha: 0.9),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    tooltip: context.l10n.folderActions,
                    onPressed: onMenu,
                    icon: const Icon(Icons.more_vert),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                folder.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (folder.hasPwd)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.lock_outline, size: 14),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.selected,
    required this.onTap,
    required this.onMenu,
    required this.onLongPress,
  });

  final LzFile file;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color:
          selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.surface
                          : scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      selected ? Icons.check_circle : iconForFile(file.name),
                      size: 21,
                      color: selected ? scheme.primary : scheme.secondary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    tooltip: context.l10n.fileActions,
                    onPressed: onMenu,
                    icon: const Icon(Icons.more_vert),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (file.hasPwd)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.lock_outline, size: 14),
                ),
              Text(
                prettyLzSize(file.size),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// MD3E 列表项：用留白分隔而不是分割线；图标放在圆角色块里；
/// 选中时整行填充主色容器，圆角与图标块同步做形状过渡。
class _DriveRow extends StatelessWidget {
  const _DriveRow({
    required this.icon,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.menuTooltip,
    required this.onTap,
    required this.onMenu,
    required this.onLongPress,
    this.folder = false,
    this.locked = false,
  });

  final IconData icon;
  final bool selected;
  final String title;
  final String subtitle;
  final String menuTooltip;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final VoidCallback onLongPress;

  /// 文件夹用主色图标块，文件用中性色。
  final bool folder;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      // 选中时圆角跟着做形状过渡（shape morph）
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 18, end: selected ? 14 : 18),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, radius, child) => Material(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.surface
                        : folder
                            ? scheme.secondaryContainer
                            : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(selected ? 14 : 12),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      selected ? Icons.check_circle : icon,
                      key: ValueKey(selected),
                      size: 22,
                      color: selected
                          ? scheme.primary
                          : folder
                              ? scheme.onSecondaryContainer
                              : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge,
                      ),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.outline),
                          ),
                        ),
                    ],
                  ),
                ),
                if (locked)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: scheme.outline,
                    ),
                  ),
                IconButton(
                  tooltip: menuTooltip,
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  color: selected ? scheme.onPrimaryContainer : null,
                  icon: const Icon(Icons.more_vert),
                  onPressed: onMenu,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.selected,
    required this.onTap,
    required this.onMenu,
    required this.onLongPress,
  });

  final LzFolder folder;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return _DriveRow(
      icon: Icons.folder_outlined,
      folder: true,
      selected: selected,
      title: folder.name,
      subtitle: folder.desc,
      locked: folder.hasPwd,
      menuTooltip: context.l10n.folderActions,
      onTap: onTap,
      onMenu: onMenu,
      onLongPress: onLongPress,
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.selected,
    required this.onTap,
    required this.onMenu,
    required this.onLongPress,
  });

  final LzFile file;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return _DriveRow(
      icon: iconForFile(file.name),
      selected: selected,
      title: file.name,
      subtitle: [
        prettyLzSize(file.size),
        if (file.time.isNotEmpty) file.time,
      ].where((e) => e.isNotEmpty).join(' · '),
      locked: file.hasPwd,
      menuTooltip: context.l10n.fileActions,
      onTap: onTap,
      onMenu: onMenu,
      onLongPress: onLongPress,
    );
  }
}

/// 文件夹属性弹窗：先展示缓存/占位内容，后台拉取完整简介与统计后渐入更新。
class _FolderInfoSheet extends StatefulWidget {
  const _FolderInfoSheet({
    required this.folder,
    required this.page,
  });

  final LzFolder folder;
  final _DrivePageState page;

  @override
  State<_FolderInfoSheet> createState() => _FolderInfoSheetState();
}

class _FolderInfoSheetState extends State<_FolderInfoSheet> {
  late String _name = widget.folder.name;
  String? _desc;
  String? _stats;
  bool _loading = false;
  bool _pinned = false;

  @override
  void initState() {
    super.initState();
    _desc = widget.page._folderDescCache[widget.folder.id];
    _stats = widget.page._folderSizeCache[widget.folder.id];
    final needDesc = !widget.page._folderDescCache.containsKey(widget.folder.id);
    final needStats =
        !widget.page._folderSizeCache.containsKey(widget.folder.id);
    _loading = needDesc || needStats;
    context
        .read<AppController>()
        .db
        .isPinned(
          context.read<AppController>().activeUid ?? '',
          widget.folder.id,
        )
        .then((value) {
      if (mounted) setState(() => _pinned = value);
    });
    _fetch();
  }

  Future<void> _toggleQuickAccess() async {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    if (_pinned) {
      await app.db.removePin(widget.folder.id);
      if (mounted) setState(() => _pinned = false);
    } else {
      // 当前目录查看属性时，自身的名字已经在路径里，避免重复拼一次
      final ancestors = widget.page._path;
      final isCurrent = ancestors.isNotEmpty &&
          ancestors.last.id == widget.folder.id;
      await app.db.addPin(
        account: app.activeUid ?? '',
        name: widget.folder.name,
        ref: widget.folder.id,
        path: [
          l10n.root,
          ...ancestors.map((node) => node.name),
          if (!isCurrent) widget.folder.name,
        ].join('/'),
      );
      if (mounted) setState(() => _pinned = true);
    }
  }

  LzFolder get _folder => LzFolder(
    id: widget.folder.id,
    name: _name,
    desc: _desc ?? widget.folder.desc,
    hasPwd: widget.folder.hasPwd,
  );

  Future<void> _editInfo() async {
    final updated = await widget.page._editFolderInfo(_folder);
    if (updated == null || !mounted) return;
    setState(() {
      _name = updated.name;
      _desc = updated.desc;
    });
  }

  Future<void> _editPassword() => widget.page._setFolderPasswd(_folder);

  Future<void> _fetch() async {
    final l10n = context.l10n;
    final id = widget.folder.id;
    final needDesc = !widget.page._folderDescCache.containsKey(id);
    final needStats = !widget.page._folderSizeCache.containsKey(id);
    if (!needDesc && !needStats) return;
    final client = context.read<AppController>().client;
    if (needDesc) {
      try {
        final info = await client?.shareInfoOfFolder(id);
        if (info != null && info.desc.isNotEmpty) {
          widget.page._folderDescCache[id] = info.desc;
          if (mounted) setState(() => _desc = info.desc);
        }
      } catch (_) {}
    }
    if (needStats) {
      try {
        final stats = await client?.folderStats(id);
        if (stats != null) {
          if (stats.desc.isNotEmpty) {
            widget.page._folderDescCache[id] = stats.desc;
            if (mounted) setState(() => _desc = stats.desc);
          }
          if (stats.size.isNotEmpty || stats.count > 0) {
            final text = [
              if (stats.size.isNotEmpty) stats.size,
              if (stats.count > 0) l10n.fileCount(stats.count),
            ].join(' · ');
            widget.page._folderSizeCache[id] = text;
            if (mounted) setState(() => _stats = text);
          }
        } else {
          final files = client == null
              ? const <LzFile>[]
              : await client.listFiles(id);
          if (files.isNotEmpty) {
            final total = files.fold<int>(
              0,
              (sum, file) => sum + lzSizeToBytes(file.size),
            );
            final text = [
              formatBytes(total),
              l10n.fileCount(files.length),
            ].join(' · ');
            widget.page._folderSizeCache[id] = text;
            if (mounted) setState(() => _stats = text);
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final folder = widget.folder;
    final page = widget.page;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PropertyHeaderCard(
            icon: Icons.folder,
            title: _name,
            subtitle: [
              context.l10n.folder,
              ?_stats,
            ].join(' · '),
            desc: _desc ?? folder.desc,
            loading: _loading,
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(context.l10n.folderInfo),
            subtitle: Text(context.l10n.folderInfoSubtitle),
            onTap: _editInfo,
          ),
          ListTile(
            leading: const Icon(Icons.password),
            title: Text(context.l10n.accessPassword),
            subtitle: Text(context.l10n.accessPasswordSubtitle),
            onTap: _editPassword,
          ),
          ListTile(
            enabled: !_loading,
            leading: const Icon(Icons.link_outlined),
            title: Text(context.l10n.copyLink),
            onTap: _loading
                ? null
                : () {
                    Navigator.of(context).pop();
                    page._copyFolderShareLink(_folder);
                  },
          ),
          ListTile(
            enabled: !_loading,
            leading: const Icon(Icons.open_in_new),
            title: Text(context.l10n.openLink),
            onTap: _loading
                ? null
                : () {
                    Navigator.of(context).pop();
                    page._openFolderShareInBrowser(_folder);
                  },
          ),
          ListTile(
            enabled: !_loading,
            leading: const Icon(Icons.qr_code),
            title: Text(context.l10n.showQr),
            onTap: _loading
                ? null
                : () {
                    Navigator.of(context).pop();
                    page._showFolderQr(_folder);
                  },
          ),
          ListTile(
            leading: Icon(
              _pinned ? Icons.push_pin : Icons.push_pin_outlined,
            ),
            title: Text(
              _pinned
                  ? context.l10n.removeFromQuickAccess
                  : context.l10n.addToQuickAccess,
            ),
            onTap: _toggleQuickAccess,
          ),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: Text(context.l10n.addFavorite),
            onTap: () {
              Navigator.of(context).pop();
              page._favoriteFolder(_folder);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(context.l10n.delete),
            onTap: () {
              Navigator.of(context).pop();
              page._deleteFolder(_folder);
            },
          ),
        ],
      ),
    );
  }
}

class FolderPickResult {
  const FolderPickResult(this.folderId, this.name, {this.fileName});

  final String folderId;
  final String name;
  final String? fileName;
}

/// 目标文件夹选择弹窗（移动 / 上传共用）。
Future<FolderPickResult?> showFolderPicker(
  BuildContext context, {
  required LanzouClient client,
  Set<String> excludeIds = const {},
  String? confirmLabel,
  String? initialName,
}) {
  return showDialog<FolderPickResult>(
    context: context,
    builder: (_) => FolderPickerDialog(
      client: client,
      excludeIds: excludeIds,
      confirmLabel: confirmLabel,
      initialName: initialName,
    ),
  );
}

/// 目标文件夹选择弹窗：路径栏可横滑点击，支持新建文件夹；
/// 上传模式下顶部可修改文件名。
class FolderPickerDialog extends StatefulWidget {
  const FolderPickerDialog({
    super.key,
    required this.client,
    required this.excludeIds,
    this.confirmLabel,
    this.initialName,
  });

  final LanzouClient client;

  /// 需要排除的条目 id（避免把文件夹移进它自己）。
  final Set<String> excludeIds;
  final String? confirmLabel;

  /// 上传时预填的文件名；为 null 表示移动模式，不显示名称输入框。
  final String? initialName;

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  String _folderId = '-1';
  List<LzFolder> _folders = [];
  List<PathNode> _path = [];
  bool _loading = true;
  String? _error;
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialName ?? '');

  @override
  void initState() {
    super.initState();
    _load('-1');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load(String folderId) async {
    setState(() {
      _folderId = folderId;
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.client.listFolders(folderId);
      if (!mounted) return;
      setState(() {
        _folders = result.folders;
        _path = result.path;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _jumpTo(int index) {
    final newPath = index < 0 ? <PathNode>[] : _path.sublist(0, index + 1);
    _load(newPath.isEmpty ? '-1' : newPath.last.id);
  }

  Future<void> _mkdir() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.newFolder),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: context.l10n.nameRequired),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(context.l10n.create),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await widget.client.mkdir(_folderId, name);
      await _load(_folderId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  String _targetName(AppLocalizations l10n) =>
      _path.isEmpty ? l10n.root : _path.last.name;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible =
        _folders.where((f) => !widget.excludeIds.contains(f.id)).toList();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(l10n.chooseTargetFolder),
      content: SizedBox(
        width: 360,
        height: math.min(440.0, MediaQuery.sizeOf(context).height * 0.55),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.initialName != null) ...[
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  labelText: l10n.nameRequired,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = -1; i < _path.length; i++) ...[
                          if (i >= 0)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: scheme.outline,
                              ),
                            ),
                          PathChip(
                            label: i < 0 ? l10n.root : _path[i].name,
                            current: i == _path.length - 1,
                            onTap: () => _jumpTo(i),
                            verticalPadding: 4,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: l10n.newFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  onPressed: _loading ? null : _mkdir,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              l10n.loadFailed(_error!),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : visible.isEmpty
                          ? Center(
                              child: Text(
                                l10n.noSubfolders,
                                style: TextStyle(color: scheme.outline),
                              ),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: visible.length,
                              itemBuilder: (context, index) =>
                                  _folderRow(visible[index]),
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _loading
              ? null
              : () {
                  final edited = _nameController.text.trim();
                  Navigator.of(context).pop(
                    FolderPickResult(
                      _folderId,
                      _targetName(l10n),
                      fileName: widget.initialName == null
                          ? null
                          : (edited.isEmpty ? widget.initialName : edited),
                    ),
                  );
                },
          child: Text(widget.confirmLabel ?? l10n.moveHere),
        ),
      ],
    );
  }

  /// MD3E 目录行：圆角图标块 + 名称 + 进入箭头。
  Widget _folderRow(LzFolder folder) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _load(folder.id),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.folder_outlined,
                    size: 19,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
