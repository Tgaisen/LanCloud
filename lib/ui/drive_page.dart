import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/api/lanzou_client.dart';
import '../core/api/models.dart';
import '../core/app_controller.dart';
import '../core/drive_cache.dart';
import '../core/transfer/transfer_manager.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'web_page.dart';

const int kFreeUploadLimit = 100 * 1024 * 1024;

class DrivePage extends StatefulWidget {
  const DrivePage({super.key, this.initialFolderId = '-1', this.initialName});

  final String initialFolderId;
  final String? initialName;

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const _anim = Duration(milliseconds: 200);

  @override
  bool get wantKeepAlive => true;

  late final AnimationController _selAnim = AnimationController(
    vsync: this,
    duration: _anim,
  );

  /// 顶栏滚动变色（离开顶部 -> 50ms 过渡到实色）
  late final AnimationController _appBarAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 50),
  );

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
  String _sortMode = 'name';
  final Map<String, double> _folderOffsets = {};
  bool _selecting = false;
  final Set<String> _selectedFiles = {};
  final Set<String> _selectedFolders = {};
  Set<String> _downloaded = {};
  final Map<String, String> _fileDescCache = {};
  final Map<String, String> _folderDescCache = {};
  final Map<String, String> _folderSizeCache = {};
  late AppController _app;

  @override
  void initState() {
    super.initState();
    if (widget.initialName != null) {
      _path = [PathNode(id: widget.initialFolderId, name: widget.initialName!)];
    }
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    if (widget.initialFolderId == '-1' && widget.initialName == null) {
      _app.onDriveBack = null;
    }
    if (_selecting) {
      _app.setSelectionMode(false);
      _app.onRequestExitSelection = null;
    }
    _selAnim.dispose();
    _appBarAnim.dispose();
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = context.read<AppController>();
    if (widget.initialFolderId == '-1' && widget.initialName == null) {
      _app.onDriveBack = _handleDriveBack;
    }
  }

  /// 返回键：多选 > 上一级目录 > 交给外壳处理
  Future<bool> _handleDriveBack() async {
    if (_selecting) {
      _exitSelection();
      return true;
    }
    if (_path.isNotEmpty) {
      await _jumpTo(_path.length - 2);
      return true;
    }
    return false;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pixels = _scroll.position.pixels;
    if (pixels > 0) {
      _appBarAnim.forward();
    } else {
      _appBarAnim.reverse();
    }
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

  Future<void> _load({bool force = false}) async {
    final app = context.read<AppController>();
    final client = app.client;
    if (client == null) return;

    final cached = app.settings.cacheFolders
        ? app.driveCache.get(_folderId)
        : null;
    if (!force && cached != null) {
      setState(() {
        _folders = cached.folders;
        _files = cached.files;
        _path = cached.path.isEmpty ? _path : cached.path;
        _page = cached.page;
        _hasMore = cached.hasMore;
        _loading = false;
        _error = null;
      });
      _refreshDownloaded();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final foldersResult = await client.listFolders(_folderId);
      final firstPage = await client.listFilesPage(_folderId, 1);
      var files = firstPage.files;
      var hasMore = firstPage.hasMore;
      var page = 1;
      if (app.settings.loadAllPages) {
        while (hasMore && page < 60) {
          page += 1;
          final next = await client.listFilesPage(_folderId, page);
          files = [...files, ...next.files];
          hasMore = next.hasMore;
        }
      }
      if (!mounted) return;
      setState(() {
        _folders = foldersResult.folders;
        _path = foldersResult.path.isEmpty && _path.isEmpty
            ? _path
            : (foldersResult.path.isEmpty ? _path : foldersResult.path);
        _files = files;
        _page = page;
        _hasMore = hasMore;
        _loading = false;
        _selectedFiles.clear();
        _selectedFolders.clear();
      });
      if (app.settings.cacheFolders) {
        app.driveCache.put(_folderId, _snapshot());
      }
      _refreshDownloaded();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _filter.isNotEmpty) return;
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

  Future<void> _refreshDownloaded() async {
    final app = context.read<AppController>();
    final prefix = '${app.activeUid ?? ''}:';
    final refs = await app.db.downloadedRefs();
    if (!mounted) return;
    setState(() {
      // 已下载标记按账号区分，避免不同账号的文件 ID 撞号
      _downloaded = refs
          .where((ref) => ref.startsWith(prefix))
          .map((ref) => ref.substring(prefix.length))
          .toSet();
    });
  }

  Future<void> _reloadAfterChange() async {
    context.read<AppController>().driveCache.clear();
    await _load(force: true);
  }

  List<LzFolder> get _visibleFolders {
    final query = _filter.toLowerCase();
    return _folders
        .where((f) => query.isEmpty || f.name.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

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
      case 'time':
        list.sort((a, b) => b.time.compareTo(a.time));
      default:
        list.sort((a, b) => a.name.compareTo(b.name));
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
    final app = context.read<AppController>();
    await app.db.addRecent(
      account: app.activeUid ?? '',
      kind: 'folder',
      name: folder.name,
      ref: folder.id,
    );
    // 进入新目录时若顶/底栏处于收起状态，先恢复显示，
    // 否则目录内容较少无法滚动时底栏就唤不出来。
    app.barsHide.value = 0;
    _rememberFolderOffset();
    setState(() {
      _folderId = folder.id;
      _path = [..._path, PathNode(id: folder.id, name: folder.name)];
      _filter = '';
      _searchController.clear();
    });
    await _load();
    _restoreFolderOffset(folder.id);
  }

  Future<void> _jumpTo(int index) async {
    final app = context.read<AppController>();
    app.barsHide.value = 0;
    final newPath = index < 0 ? <PathNode>[] : _path.sublist(0, index + 1);
    _rememberFolderOffset();
    setState(() {
      _path = newPath;
      _folderId = newPath.isEmpty ? '-1' : newPath.last.id;
      _filter = '';
      _searchController.clear();
    });
    await _load();
    _restoreFolderOffset(_folderId);
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
        _scroll.jumpTo(target.clamp(0.0, max));
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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Column(
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
                      child: SegmentedButton<String>(
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
                      child: SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'name',
                            label: Text(context.l10n.sortName),
                          ),
                          ButtonSegment(
                            value: 'size',
                            label: Text(context.l10n.sortSize),
                          ),
                          ButtonSegment(
                            value: 'time',
                            label: Text(context.l10n.sortTime),
                          ),
                        ],
                        selected: {sort},
                        onSelectionChanged: (values) {
                          setSheetState(() => sort = values.first);
                          setState(() => _sortMode = values.first);
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
                    Navigator.of(sheetContext).pop();
                    _enterSelection();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: Text(context.l10n.refresh),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _reloadAfterChange();
                  },
                ),
                if (!isRoot)
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(context.l10n.folderProperties),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (_) => _FolderInfoSheet(
                          folder: LzFolder(
                            id: _folderId,
                            name: _path.last.name,
                            desc: '',
                          ),
                          page: this,
                          showOpen: false,
                        ),
                      );
                    },
                  ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(context.l10n.newFolder),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _mkdir();
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: Text(context.l10n.uploadFile),
              subtitle: Text(context.l10n.uploadFileSubtitle),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _upload();
              },
            ),
          ],
        ),
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
      await _reloadAfterChange();
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
    try {
      for (final id in fileIds) {
        await client.deleteItem(id: id, isFile: true);
      }
      for (final id in _selectedFolders) {
        await client.deleteItem(id: id, isFile: false);
      }
      await app.db.removeDownloaded([
        for (final id in fileIds) '${app.activeUid ?? ''}:$id',
      ]);
      if (!mounted) return;
      _exitSelection();
      await _reloadAfterChange();
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
    var failed = 0;
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.batchDownload),
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(context.l10n.resolvingBatch(ids.length)),
            ),
          ],
        ),
      ),
    );
    try {
      for (final id in ids) {
        final file = _files.firstWhere((f) => f.id == id);
        try {
          final info = await app.client!.shareInfoOfFile(id);
          final direct = await app.publicClient.resolveFileShare(
            info.url,
            pwd: info.pwd,
          );
          transfers.addDownload(
            url: direct.url,
            name: direct.name.isEmpty ? file.name : direct.name,
            referer: info.url,
            via: app.publicClient,
            refId: '${app.activeUid ?? ''}:$id',
          );
        } catch (_) {
          failed += 1;
        }
      }
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
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
    for (final id in fileIds) {
      try {
        final info = await app.client!.shareInfoOfFile(id);
        final file = _files.firstWhere((f) => f.id == id);
        lines.add(
          info.pwd.isEmpty
              ? '${file.name} ${info.url}'
              : l10n.linkWithPassword(
                  '${file.name} ${info.url}',
                  info.pwd,
                ),
        );
      } catch (_) {}
    }
    for (final id in folderIds) {
      try {
        final info = await app.client!.shareInfoOfFolder(id);
        final folder = _folders.firstWhere((f) => f.id == id);
        final name = info.name.isEmpty ? folder.name : info.name;
        lines.add(
          info.pwd.isEmpty
              ? '$name ${info.url}'
              : l10n.linkWithPassword('$name ${info.url}', info.pwd),
        );
      } catch (_) {}
    }
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
      for (final id in fileIds) {
        try {
          final file = _files.firstWhere((f) => f.id == id);
          final info = await client.shareInfoOfFile(id);
          await app.db.addFavorite(
            kind: 'shareFile',
            name: file.name,
            ref: info.url,
            pwd: info.pwd,
            size: file.size,
            sharer: sharer,
          );
          count += 1;
        } catch (_) {
          failed += 1;
        }
      }
      for (final id in folderIds) {
        try {
          final folder = _folders.firstWhere((f) => f.id == id);
          final info = await client.shareInfoOfFolder(id);
          await app.db.addFavorite(
            kind: 'shareFolder',
            name: folder.name,
            ref: info.url,
            pwd: info.pwd,
            sharer: sharer,
          );
          count += 1;
        } catch (_) {
          failed += 1;
        }
      }
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
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(context.l10n.move),
              subtitle: Text(context.l10n.moveSubtitle),
              onTap: () => Navigator.of(sheetContext).pop('move'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(context.l10n.editDesc),
              subtitle: Text(context.l10n.editDescBatchSubtitle),
              onTap: () => Navigator.of(sheetContext).pop('desc'),
            ),
            ListTile(
              leading: const Icon(Icons.password),
              title: Text(context.l10n.setPassword),
              subtitle: Text(context.l10n.setPasswordSubtitle),
              onTap: () => Navigator.of(sheetContext).pop('pwd'),
            ),
          ],
        ),
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
    final target = await showDialog<_MoveTarget>(
      context: context,
      builder: (_) => _MoveDialog(
        client: client,
        excludeIds: {...fileIds, ...folderIds},
      ),
    );
    if (target == null || !mounted) return;
    var failed = 0;
    for (final id in fileIds) {
      try {
        await client.moveFile(id, target.folderId);
      } catch (_) {
        failed += 1;
      }
    }
    for (final id in folderIds) {
      try {
        await client.moveFolder(id, target.folderId);
      } catch (_) {
        failed += 1;
      }
    }
    final count = fileIds.length + folderIds.length;
    _exitSelection();
    await _reloadAfterChange();
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
    var failed = 0;
    for (final id in fileIds) {
      try {
        await client.setDesc(id, controller.text.trim());
      } catch (_) {
        failed += 1;
      }
    }
    for (final id in folderIds) {
      try {
        await client.setFolderDesc(id, controller.text.trim());
      } catch (_) {
        failed += 1;
      }
    }
    final count = fileIds.length + folderIds.length;
    _exitSelection();
    _fileDescCache.clear();
    _folderDescCache.clear();
    await _reloadAfterChange();
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
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.setPassword),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 6,
          decoration: InputDecoration(hintText: context.l10n.pwdHint),
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
    final pwd = controller.text.trim();
    if (pwd.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.pwdTooShort)),
      );
      return;
    }
    final client = context.read<AppController>().client;
    if (client == null) return;
    final fileIds = _selectedFiles.toList();
    final folderIds = _selectedFolders.toList();
    var failed = 0;
    for (final id in fileIds) {
      try {
        await client.setPasswd(id, pwd);
      } catch (_) {
        failed += 1;
      }
    }
    for (final id in folderIds) {
      try {
        await client.setFolderPasswd(id, pwd);
      } catch (_) {
        failed += 1;
      }
    }
    final count = fileIds.length + folderIds.length;
    _exitSelection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? context.l10n.passwordSetCount(count)
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
    await showModalBottomSheet<void>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          builder: (sheetCtx, scrollController) => ListView(
            controller: scrollController,
            children: [
            _PropertyHeader(
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
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(context.l10n.download),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _downloadOwnFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: Text(context.l10n.copyLink),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _copyShareLink(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(context.l10n.openLink),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openShareInBrowser(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code),
              title: Text(context.l10n.showQr),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showFileQr(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: Text(context.l10n.addFavorite),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _favoriteFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(context.l10n.delete),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _deleteFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.more_horiz),
              title: Text(context.l10n.moreActions),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _fileMenuSheet(file);
              },
            ),
          ],
          ),
        ),
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
              onTap: () {
                Navigator.of(sheetContext).pop();
                _downloadOwnFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(context.l10n.editDesc),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _singleSetDesc(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.password),
              title: Text(context.l10n.setPassword),
              subtitle: Text(context.l10n.freeAccountPasswordNote),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _singleSetPasswd(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(context.l10n.delete),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _deleteFile(file);
              },
            ),
          ],
        ),
      ),
    );
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
      await _reloadAfterChange();
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
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.setPassword),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 6,
          decoration: InputDecoration(hintText: context.l10n.pwdHint),
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
    final pwd = controller.text.trim();
    if (pwd.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.pwdTooShort)),
      );
      return;
    }
    try {
      await context.read<AppController>().client?.setPasswd(file.id, pwd);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.passwordSet)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _folderActions(LzFolder folder) async {
    if (_selecting) {
      setState(() {
        if (!_selectedFolders.remove(folder.id)) _selectedFolders.add(folder.id);
      });
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _FolderInfoSheet(folder: folder, page: this),
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
      await _reloadAfterChange();
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
      await _reloadAfterChange();
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
    final hideTopBar = app.settings.hideTopBar;
    final selectedCount = _selectedFiles.length + _selectedFolders.length;

    return AnimatedBuilder(
      animation: Listenable.merge([_selAnim, _appBarAnim]),
      builder: (context, _) {
        return Scaffold(
          body: Stack(
            children: [
              _buildBody(grid, hideTopBar: hideTopBar),
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
                      child: _selectionAppBar(selectedCount),
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
                    // 紧贴按钮内容，避免固定高度带来的上下留白遮挡列表
                    child: Material(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _BatchAction(
                                icon: Icons.delete_outline,
                                label: context.l10n.delete,
                                onPressed: selectedCount == 0
                                    ? null
                                    : _deleteSelected,
                              ),
                              _BatchAction(
                                icon: Icons.download_outlined,
                                label: context.l10n.download,
                                onPressed: _selectedFiles.isEmpty
                                    ? null
                                    : _batchDownload,
                              ),
                              _BatchAction(
                                icon: Icons.share_outlined,
                                label: context.l10n.share,
                                onPressed: selectedCount == 0
                                    ? null
                                    : _batchShare,
                              ),
                              _BatchAction(
                                icon: Icons.star_outline,
                                label: context.l10n.favorite,
                                onPressed: selectedCount == 0
                                    ? null
                                    : _batchFavorite,
                              ),
                              _BatchAction(
                                icon: Icons.more_horiz,
                                label: context.l10n.more,
                                onPressed: selectedCount == 0
                                    ? null
                                    : _batchMore,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
      floatingActionButton: ValueListenableBuilder<double>(
        valueListenable: app.barsHide,
        builder: (context, hide, child) => Padding(
          padding: EdgeInsets.only(
            bottom: app.settings.floatingNavBar ? 76 : 0,
          ),
          child: AnimatedScale(
            scale: (_selecting ||
                    ((app.settings.hideTopBar ||
                            app.settings.hideBottomBar) &&
                        hide >= 1))
                ? 0
                : 1,
            duration: _anim,
            curve: Curves.easeOut,
            child: child,
          ),
        ),
        child: FloatingActionButton.extended(
          onPressed: _showAddMenu,
          icon: const Icon(Icons.add),
          label: Text(context.l10n.add),
        ),
      ),
        );
      },
    );
  }

  /// 顶栏是第一个 sliver，路径栏作为它的 bottom 组成一个整体：
  /// 和其它视图相比只是更高、多了一行路径，浮动/钉住逻辑完全一致。
  Widget _buildBody(bool grid, {required bool hideTopBar}) {
    return RefreshIndicator(
      onRefresh: _reloadAfterChange,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            // floating：向上滚动立刻开始出现；pinned 只由设置决定
            floating: hideTopBar,
            snap: false,
            pinned: !hideTopBar,
            backgroundColor: Color.lerp(
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceContainerHighest,
              _appBarAnim.value,
            ),
            scrolledUnderElevation: 0,
            leading: Navigator.of(context).canPop()
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null,
            title: _searching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: context.l10n.searchCurrentFolder,
                      border: InputBorder.none,
                    ),
                    onChanged: (value) =>
                        setState(() => _filter = value.trim()),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _scrollToTop,
                    child: Text(context.l10n.tabDrive),
                  ),
            actions: _searching
                ? [
                    IconButton(
                      tooltip: context.l10n.closeSearch,
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _searching = false;
                        _filter = '';
                        _searchController.clear();
                      }),
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
              preferredSize: const Size.fromHeight(46),
              // 多选期间禁用路径切换，但路径栏保持可见
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
          ..._contentSlivers(grid),
        ],
      ),
    );
  }

  Widget _pathBar() {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (var i = -1; i < _path.length; i++)
          Row(
            children: [
              TextButton(
                onPressed: () => _jumpTo(i),
                child: Text(
                  i < 0 ? context.l10n.root : _path[i].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (i < _path.length - 1)
                const Icon(Icons.chevron_right, size: 18),
            ],
          ),
      ],
    );
  }

  /// 顶栏与路径栏之外的剩余 slivers，按加载状态切换。
  List<Widget> _contentSlivers(bool grid) {
    if (_loading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
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
      ];
    }
    final folders = _visibleFolders;
    final files = _visibleFiles;
    if (folders.isEmpty && files.isEmpty && !_loadingMore) {
      return [
        SliverList(
          delegate: SliverChildListDelegate([
            if (_filter.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(context.l10n.noMatchContent(_filter)),
              ),
            EmptyHint(
              icon: Icons.folder_open,
              text: context.l10n.emptyFolder,
            ),
          ]),
        ),
      ];
    }
    final showFolders = _filter.isEmpty || folders.isNotEmpty;
    final animate =
        context.read<AppController>().settings.transitionAnimations;
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
              itemBuilder: (context, index) {
                final folder = folders[index];
                return _AnimatedListItem(
                  key: ValueKey('$_folderId-f-$index'),
                  index: index,
                  enabled: animate,
                  child: _FolderTile(
                    folder: folder,
                    selected: _selectedFolders.contains(folder.id),
                    onTap: () => _openFolder(folder),
                    onMenu: () => _folderActions(folder),
                    onLongPress: () => _enterSelection(folderId: folder.id),
                  ),
                );
              },
            ),
          )
        else
          SliverList.builder(
            itemCount: folders.length,
            itemBuilder: (context, index) {
              final folder = folders[index];
              return _AnimatedListItem(
                key: ValueKey('$_folderId-f-$index'),
                index: index,
                enabled: animate,
                child: _FolderRow(
                  folder: folder,
                  selected: _selectedFolders.contains(folder.id),
                  onTap: () => _openFolder(folder),
                  onMenu: () => _folderActions(folder),
                  onLongPress: () => _enterSelection(folderId: folder.id),
                ),
              );
            },
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
              itemBuilder: (context, index) {
                final file = files[index];
                return _AnimatedListItem(
                  key: ValueKey('$_folderId-l-$index'),
                  index: index,
                  enabled: animate,
                  child: _FileTile(
                    file: file,
                    selected: _selectedFiles.contains(file.id),
                    downloaded: _downloaded.contains(file.id),
                    onTap: () => _fileActions(file),
                    onMenu: () => _fileMenuSheet(file),
                    onLongPress: () => _enterSelection(fileId: file.id),
                  ),
                );
              },
            ),
          )
        else
          SliverList.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              return _AnimatedListItem(
                key: ValueKey('$_folderId-l-$index'),
                index: index,
                enabled: animate,
                child: _FileRow(
                  file: file,
                  selected: _selectedFiles.contains(file.id),
                  downloaded: _downloaded.contains(file.id),
                  onTap: () => _fileActions(file),
                  onMenu: () => _fileMenuSheet(file),
                  onLongPress: () => _enterSelection(fileId: file.id),
                ),
              );
            },
          ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
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
    ];
  }
}

/// 列表出现动画：按 index 错峰淡入并轻微上移；开关关闭时直接渲染。
class _AnimatedListItem extends StatelessWidget {
  const _AnimatedListItem({
    super.key,
    required this.index,
    required this.enabled,
    required this.child,
  });

  final int index;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    const total = 440.0;
    final delay = (index.clamp(0, 8) * 26).toDouble();
    final begin = (delay / total).clamp(0.0, 1.0);
    final end = ((delay + 232) / total).clamp(begin, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 440),
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
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
      color: selected ? scheme.primaryContainer : null,
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
                  Icon(
                    selected ? Icons.check_circle : Icons.folder,
                    size: 30,
                    color: selected
                        ? scheme.primary
                        : scheme.primary.withValues(alpha: 0.85),
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
    required this.downloaded,
    required this.onTap,
    required this.onMenu,
    required this.onLongPress,
  });

  final LzFile file;
  final bool selected;
  final bool downloaded;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? scheme.primaryContainer : null,
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
                  Icon(
                    selected ? Icons.check_circle : iconForFile(file.name),
                    size: 30,
                    color: selected ? scheme.primary : scheme.secondary,
                  ),
                  const Spacer(),
                  if (downloaded)
                    Icon(Icons.download_done, size: 16, color: scheme.primary),
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
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        selected ? Icons.check_circle : Icons.folder_outlined,
        color: selected ? scheme.primary : null,
      ),
      title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: folder.desc.isEmpty ? null : Text(folder.desc, maxLines: 1),
      trailing: IconButton(
        tooltip: context.l10n.folderActions,
        icon: const Icon(Icons.more_vert),
        onPressed: onMenu,
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.selected,
    required this.downloaded,
    required this.onTap,
    required this.onMenu,
    required this.onLongPress,
  });

  final LzFile file;
  final bool selected;
  final bool downloaded;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        selected ? Icons.check_circle : iconForFile(file.name),
        color: selected ? scheme.primary : null,
      ),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          prettyLzSize(file.size),
          if (file.time.isNotEmpty) file.time,
          if (downloaded) context.l10n.downloaded,
        ].where((e) => e.isNotEmpty).join(' · '),
      ),
      trailing: IconButton(
        tooltip: context.l10n.fileActions,
        icon: const Icon(Icons.more_vert),
        onPressed: onMenu,
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// 文件夹属性弹窗：先展示缓存/占位内容，后台拉取完整简介与统计后渐入更新。
class _FolderInfoSheet extends StatefulWidget {
  const _FolderInfoSheet({
    required this.folder,
    required this.page,
    this.showOpen = true,
  });

  final LzFolder folder;
  final _DrivePageState page;
  /// 当前目录查看属性时隐藏“打开文件夹”（自己打开自己没有意义）。
  final bool showOpen;

  @override
  State<_FolderInfoSheet> createState() => _FolderInfoSheetState();
}

class _FolderInfoSheetState extends State<_FolderInfoSheet> {
  String? _desc;
  String? _stats;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _desc = widget.page._folderDescCache[widget.folder.id];
    _stats = widget.page._folderSizeCache[widget.folder.id];
    final needDesc = !widget.page._folderDescCache.containsKey(widget.folder.id);
    final needStats =
        !widget.page._folderSizeCache.containsKey(widget.folder.id);
    _loading = needDesc || needStats;
    _fetch();
  }

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
          _PropertyHeader(
            icon: Icons.folder,
            title: folder.name,
            subtitle: [
              context.l10n.folder,
              ?_stats,
            ].join(' · '),
            desc: _desc ?? folder.desc,
            loading: _loading,
          ),
          const Divider(height: 1),
          if (widget.showOpen)
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text(context.l10n.openFolder),
              onTap: () {
                Navigator.of(context).pop();
                page._openFolder(folder);
              },
            ),
          ListTile(
            enabled: !_loading,
            leading: const Icon(Icons.link_outlined),
            title: Text(context.l10n.copyLink),
            onTap: _loading
                ? null
                : () {
                    Navigator.of(context).pop();
                    page._copyFolderShareLink(folder);
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
                    page._openFolderShareInBrowser(folder);
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
                    page._showFolderQr(folder);
                  },
          ),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: Text(context.l10n.addFavorite),
            onTap: () {
              Navigator.of(context).pop();
              page._favoriteFolder(folder);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(context.l10n.delete),
            onTap: () {
              Navigator.of(context).pop();
              page._deleteFolder(folder);
            },
          ),
        ],
      ),
    );
  }
}

class _PropertyHeader extends StatelessWidget {
  const _PropertyHeader({
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.desc = '',
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String desc;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Icon(icon, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: Text(
                      subtitle,
                      key: ValueKey(subtitle),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: Text(
                      desc,
                      key: ValueKey(desc),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchAction extends StatelessWidget {
  const _BatchAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.outline;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

class _MoveTarget {
  const _MoveTarget(this.folderId, this.name);

  final String folderId;
  final String name;
}

/// 移动目标文件夹选择弹窗：逐级浏览，点“移动到这里”确认。
class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.client, required this.excludeIds});

  final LanzouClient client;

  /// 正在被移动的条目 id（避免把文件夹移进它自己）。
  final Set<String> excludeIds;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  String _folderId = '-1';
  List<LzFolder> _folders = [];
  List<PathNode> _path = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load('-1');
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

  String get _parentId =>
      _path.length >= 2 ? _path[_path.length - 2].id : '-1';

  String _targetName(AppLocalizations l10n) =>
      _path.isEmpty ? l10n.root : _path.last.name;

  String _targetPath(AppLocalizations l10n) => _path.isEmpty
      ? l10n.root
      : _path.map((p) => p.name).join(' / ');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final visible =
        _folders.where((f) => !widget.excludeIds.contains(f.id)).toList();
    return AlertDialog(
      title: Text(l10n.chooseTargetFolder),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: l10n.parentFolder,
                  onPressed: _path.isEmpty ? null : () => _load(_parentId),
                  icon: const Icon(Icons.arrow_upward),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _targetName(l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(l10n.moveHere),
              subtitle: Text(
                _targetPath(l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(context)
                  .pop(_MoveTarget(_folderId, _targetName(l10n))),
            ),
            const Divider(height: 1),
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
                          ? Center(child: Text(l10n.noSubfolders))
                          : ListView.builder(
                              itemCount: visible.length,
                              itemBuilder: (context, index) {
                                final folder = visible[index];
                                return ListTile(
                                  leading: const Icon(Icons.folder_outlined),
                                  title: Text(
                                    folder.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _load(folder.id),
                                );
                              },
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
      ],
    );
  }
}
