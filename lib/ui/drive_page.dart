import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api/models.dart';
import '../core/app_controller.dart';
import '../core/drive_cache.dart';
import '../core/transfer/transfer_manager.dart';
import 'common.dart';

const int kFreeUploadLimit = 100 * 1024 * 1024;

class DrivePage extends StatefulWidget {
  const DrivePage({super.key, this.initialFolderId = '-1', this.initialName});

  final String initialFolderId;
  final String? initialName;

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage>
    with SingleTickerProviderStateMixin {
  static const _anim = Duration(milliseconds: 200);

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
    if (_scroll.position.pixels > 0) {
      _appBarAnim.forward();
    } else {
      _appBarAnim.reverse();
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 320) {
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
    return _files
        .where((f) => query.isEmpty || f.name.toLowerCase().contains(query))
        .toList();
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
      tooltip: '退出多选',
      icon: const Icon(Icons.close),
      onPressed: _exitSelection,
    ),
    title: Text('已选择 $count 项'),
    actions: [
      IconButton(
        tooltip: '全选',
        icon: const Icon(Icons.select_all),
        onPressed: _selectAll,
      ),
      IconButton(
        tooltip: '反选',
        icon: const Icon(Icons.flip_to_front),
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
    setState(() {
      _folderId = folder.id;
      _path = [..._path, PathNode(id: folder.id, name: folder.name)];
      _filter = '';
      _searchController.clear();
    });
    await _load();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _jumpTo(int index) async {
    final newPath = index < 0 ? <PathNode>[] : _path.sublist(0, index + 1);
    setState(() {
      _path = newPath;
      _folderId = newPath.isEmpty ? '-1' : newPath.last.id;
      _filter = '';
      _searchController.clear();
    });
    await _load();
    if (_scroll.hasClients) _scroll.jumpTo(0);
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
              title: const Text('新建文件夹'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _mkdir();
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('上传文件'),
              subtitle: const Text('从本机或其他应用中选择文件'),
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
              ? '已加入 $added 个上传任务，跳过 $skipped 个超过 100MB 的文件'
              : '已加入 $added 个上传任务',
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
        title: const Text('新建文件夹'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '名称（必填）'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: '简介（选填）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (result != true || !mounted) return;
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('文件夹名称不能为空')));
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
        title: const Text('删除确认'),
        content: Text('将把选中的 $count 个条目移入回收站，继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
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
    final ids = _selectedFiles.toList();
    var failed = 0;
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('批量下载'),
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text('正在解析并加入下载队列（共 ${ids.length} 个）')),
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
              ? '已加入 ${ids.length} 个下载任务'
              : '已加入 ${ids.length - failed} 个下载任务，$failed 个解析失败',
        ),
      ),
    );
  }

  Future<void> _batchShare() async {
    final ids = _selectedFiles.toList();
    if (ids.isEmpty) return;
    final app = context.read<AppController>();
    final lines = <String>[];
    for (final id in ids) {
      try {
        final info = await app.client!.shareInfoOfFile(id);
        final file = _files.firstWhere((f) => f.id == id);
        lines.add(
          info.pwd.isEmpty
              ? '${file.name} ${info.url}'
              : '${file.name} ${info.url} 提取码：${info.pwd}',
        );
      } catch (_) {}
    }
    if (!mounted) return;
    _exitSelection();
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有可复制的分享链接')));
      return;
    }
    await copyText(context, lines.join('\n'));
  }

  Future<void> _batchFavorite() async {
    final app = context.read<AppController>();
    final ids = _selectedFiles.toList();
    for (final id in ids) {
      final file = _files.firstWhere((f) => f.id == id);
      await app.db.addFavorite(kind: 'file', name: file.name, ref: id);
    }
    if (mounted) _exitSelection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已收藏 ${ids.length} 个文件')),
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
              leading: const Icon(Icons.edit_note),
              title: const Text('修改简介'),
              subtitle: const Text('批量设置选中的文件简介'),
              onTap: () => Navigator.of(sheetContext).pop('desc'),
            ),
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('设置访问密码'),
              subtitle: const Text('2-6 位；免费账号只能设置不能关闭'),
              onTap: () => Navigator.of(sheetContext).pop('pwd'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'desc') await _batchSetDesc();
    if (action == 'pwd') await _batchSetPasswd();
  }

  Future<void> _batchSetDesc() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改简介'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新的简介'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final client = context.read<AppController>().client;
    if (client == null) return;
    final ids = _selectedFiles.toList();
    var failed = 0;
    for (final id in ids) {
      try {
        await client.setDesc(id, controller.text.trim());
      } catch (_) {
        failed += 1;
      }
    }
    _exitSelection();
    _fileDescCache.clear();
    _folderDescCache.clear();
    await _reloadAfterChange();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? '已修改 ${ids.length} 个文件的简介'
              : '已修改 ${ids.length - failed} 个，$failed 个失败',
        ),
      ),
    );
  }

  Future<void> _batchSetPasswd() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('设置访问密码'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 6,
          decoration: const InputDecoration(
            hintText: '2-6 位提取码',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final pwd = controller.text.trim();
    if (pwd.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提取码至少 2 位')),
      );
      return;
    }
    final client = context.read<AppController>().client;
    if (client == null) return;
    final ids = _selectedFiles.toList();
    var failed = 0;
    for (final id in ids) {
      try {
        await client.setPasswd(id, pwd);
      } catch (_) {
        failed += 1;
      }
    }
    _exitSelection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? '已为 ${ids.length} 个文件设置提取码'
              : '已设置 ${ids.length - failed} 个，$failed 个失败',
        ),
      ),
    );
  }

  Future<void> _openShareInBrowser(LzFile file) async {
    final client = context.read<AppController>().client;
    if (client == null) return;
    try {
      final info = await client.shareInfoOfFile(file.id);
      await launchUrl(
        Uri.parse(info.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openFolderShareInBrowser(LzFolder folder) async {
    final client = context.read<AppController>().client;
    if (client == null) return;
    try {
      final info = await client.shareInfoOfFolder(folder.id);
      await launchUrl(
        Uri.parse(info.url),
        mode: LaunchMode.externalApplication,
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
              Text('提取码：$pwd'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              copyText(context, url);
            },
            child: const Text('复制链接'),
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
                if (file.downs > 0) '下载 ${file.downs}',
                if (file.hasPwd) '有提取码',
              ].join(' · '),
              desc: _fileDescCache[file.id] ?? '',
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('下载'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _downloadOwnFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('复制链接'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _copyShareLink(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('打开链接'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openShareInBrowser(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('显示二维码'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showFileQr(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('添加收藏'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _favoriteFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _deleteFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.more_horiz),
              title: const Text('更多操作'),
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
              title: const Text('下载'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _downloadOwnFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('修改简介'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _singleSetDesc(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('设置访问密码'),
              subtitle: const Text('免费账号只能设置不能关闭'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _singleSetPasswd(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
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
        title: const Text('修改简介'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新的简介'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确定'),
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
        const SnackBar(content: Text('简介已更新')),
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
        title: const Text('设置访问密码'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 6,
          decoration: const InputDecoration(hintText: '2-6 位提取码'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final pwd = controller.text.trim();
    if (pwd.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提取码至少 2 位')),
      );
      return;
    }
    try {
      await context.read<AppController>().client?.setPasswd(file.id, pwd);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已设置提取码')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _folderActions(LzFolder folder) async {
    // 已统计过就直接显示
    if (_selecting) {
      setState(() {
        if (!_selectedFolders.remove(folder.id)) _selectedFolders.add(folder.id);
      });
      return;
    }
    // 列表接口返回的简介是截断的，这里按需拉取完整内容
    if (!_folderDescCache.containsKey(folder.id)) {
      try {
        final client = context.read<AppController>().client;
        final info = await client?.shareInfoOfFolder(folder.id);
        if (info != null && info.desc.isNotEmpty) {
          _folderDescCache[folder.id] = info.desc;
        }
      } catch (_) {}
      if (!mounted) return;
    }
    if (!_folderSizeCache.containsKey(folder.id)) {
      try {
        final stats = await context.read<AppController>().client?.folderStats(folder.id);
        if (stats != null) {
          if (stats.desc.isNotEmpty) _folderDescCache[folder.id] = stats.desc;
          if (stats.size.isNotEmpty || stats.count > 0) {
            _folderSizeCache[folder.id] = [
              if (stats.size.isNotEmpty) stats.size,
              if (stats.count > 0) '${stats.count} 个文件',
            ].join(' · ');
          }
        }
      } catch (_) {}
      if (!mounted) return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PropertyHeader(
              icon: Icons.folder,
              title: folder.name,
              subtitle: [
                '文件夹',
                if (_folderSizeCache[folder.id] != null)
                  _folderSizeCache[folder.id]!,
              ].join(' · '),
              desc: _folderDescCache[folder.id] ?? folder.desc,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('打开文件夹'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openFolder(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('复制链接'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _copyFolderShareLink(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('打开链接'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openFolderShareInBrowser(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('显示二维码'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showFolderQr(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('添加收藏'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _favoriteFolder(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _deleteFolder(folder);
              },
            ),
          ],
        ),
      ),
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
          .showSnackBar(const SnackBar(content: Text('已加入下载队列')));
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
        info.pwd.isEmpty ? info.url : '${info.url} 提取码：${info.pwd}',
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
        info.pwd.isEmpty ? info.url : '${info.url} 提取码：${info.pwd}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _favoriteFile(LzFile file) async {
    final app = context.read<AppController>();
    await app.db.addFavorite(
      kind: 'file',
      name: file.name,
      ref: file.id,
      size: file.size,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已收藏')));
  }

  Future<void> _favoriteFolder(LzFolder folder) async {
    final app = context.read<AppController>();
    await app.db.addFavorite(kind: 'folder', name: folder.name, ref: folder.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已收藏')));
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
    final app = context.watch<AppController>();
    final grid = app.settings.gridView;
    final selectedCount = _selectedFiles.length + _selectedFolders.length;

    return AnimatedBuilder(
      animation: Listenable.merge([_selAnim, _appBarAnim]),
      builder: (context, _) {
        final pathHeight = 46 * (1 - _selAnim.value);
        return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight + pathHeight),
        child: AnimatedSwitcher(
          duration: _anim,
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: _selecting
              ? _selectionAppBar(selectedCount)
              : AppBar(
                  key: const ValueKey('normal-appbar'),
                  scrolledUnderElevation: 0,
                  backgroundColor: Color.lerp(
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                    _appBarAnim.value,
                  ),
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
                          decoration: const InputDecoration(
                            hintText: '搜索当前目录',
                            border: InputBorder.none,
                          ),
                          onChanged: (value) =>
                              setState(() => _filter = value.trim()),
                        )
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _scrollToTop,
                          child: const Text('网盘'),
                        ),
                  actions: _searching
                      ? [
                          IconButton(
                            tooltip: '关闭搜索',
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
                            tooltip: '搜索',
                            icon: const Icon(Icons.search),
                            onPressed: () => setState(() => _searching = true),
                          ),
                          PopupMenuButton<String>(
                            tooltip: '菜单',
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) {
                              switch (value) {
                                case 'sort-name':
                                  setState(
                                    () => _files.sort(
                                      (a, b) => a.name.compareTo(b.name),
                                    ),
                                  );
                                case 'sort-size':
                                  setState(
                                    () => _files.sort(
                                      (a, b) =>
                                          lzSizeToBytes(b.size)
                                              .compareTo(lzSizeToBytes(a.size)),
                                    ),
                                  );
                                case 'sort-time':
                                  setState(
                                    () => _files.sort(
                                      (a, b) => b.time.compareTo(a.time),
                                    ),
                                  );
                                case 'view':
                                  app.setGridView(!grid);
                                case 'select':
                                  _enterSelection();
                                case 'refresh':
                                  _reloadAfterChange();
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'sort-name',
                                child: Text('按名称排序'),
                              ),
                              PopupMenuItem(
                                value: 'sort-size',
                                child: Text('按大小排序'),
                              ),
                              PopupMenuItem(
                                value: 'sort-time',
                                child: Text('按时间排序'),
                              ),
                              PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'view',
                                child: Text('切换布局样式'),
                              ),
                              PopupMenuItem(value: 'select', child: Text('多选')),
                              PopupMenuItem(
                                value: 'refresh',
                                child: Text('刷新'),
                              ),
                            ],
                          ),
                        ],
                  bottom: PreferredSize(
                    preferredSize: Size.fromHeight(pathHeight),
                    child: ClipRect(
                      child: SizedBox(
                        height: pathHeight,
                        child: Opacity(
                          opacity: 1 - _selAnim.value,
                          child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          for (var i = -1; i < _path.length; i++)
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () => _jumpTo(i),
                                  child: Text(
                                    i < 0 ? '根目录' : _path[i].name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (i < _path.length - 1)
                                  const Icon(Icons.chevron_right, size: 18),
                              ],
                            ),
                        ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ),
        ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: app.settings.floatingNavBar ? 76 : 0,
        ),
        child: AnimatedScale(
        scale: (_selecting ||
                ((app.settings.hideTopBar || app.settings.hideBottomBar) && app.barsHidden))
            ? 0
            : 1,
        duration: _anim,
        curve: Curves.easeOut,
        child: FloatingActionButton.extended(
          onPressed: _showAddMenu,
          icon: const Icon(Icons.add),
          label: const Text('添加'),
        ),
      ),
      ),
      body: Stack(
        children: [
          _buildBody(grid),
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
                child: BottomAppBar(
                  height: 72,
                  padding: EdgeInsets.zero,
                  child: SafeArea(
                    top: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _BatchAction(
                          icon: Icons.delete_outline,
                          label: '删除',
                          onPressed:
                              selectedCount == 0 ? null : _deleteSelected,
                        ),
                        _BatchAction(
                          icon: Icons.download_outlined,
                          label: '下载',
                          onPressed: _selectedFiles.isEmpty
                              ? null
                              : _batchDownload,
                        ),
                        _BatchAction(
                          icon: Icons.share_outlined,
                          label: '分享',
                          onPressed:
                              _selectedFiles.isEmpty ? null : _batchShare,
                        ),
                        _BatchAction(
                          icon: Icons.star_outline,
                          label: '收藏',
                          onPressed: _selectedFiles.isEmpty
                              ? null
                              : _batchFavorite,
                        ),
                        _BatchAction(
                          icon: Icons.more_horiz,
                          label: '更多',
                          onPressed:
                              _selectedFiles.isEmpty ? null : _batchMore,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
        );
      },
    );
  }

  Widget _buildBody(bool grid) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
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
              Text('加载失败：$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _load(force: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final folders = _visibleFolders;
    final files = _visibleFiles;
    if (folders.isEmpty && files.isEmpty && !_loadingMore) {
      return RefreshIndicator(
        onRefresh: _reloadAfterChange,
        child: ListView(
          children: [
            if (_filter.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('没有匹配「$_filter」的内容'),
              ),
            const EmptyHint(icon: Icons.folder_open, text: '这个文件夹是空的'),
          ],
        ),
      );
    }
    final showFolders = _filter.isEmpty || folders.isNotEmpty;
    final folderSlivers = <Widget>[
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
                return _FolderTile(
                  folder: folder,
                  selected: _selectedFolders.contains(folder.id),
                  onTap: () => _openFolder(folder),
                  onMenu: () => _folderActions(folder),
                  onLongPress: () => _enterSelection(folderId: folder.id),
                );
              },
            ),
          )
        else
          SliverList.builder(
            itemCount: folders.length,
            itemBuilder: (context, index) {
              final folder = folders[index];
              return _FolderRow(
                folder: folder,
                selected: _selectedFolders.contains(folder.id),
                onTap: () => _openFolder(folder),
                onMenu: () => _folderActions(folder),
                onLongPress: () => _enterSelection(folderId: folder.id),
              );
            },
          ),
    ];
    final fileSlivers = <Widget>[
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
                return _FileTile(
                  file: file,
                  selected: _selectedFiles.contains(file.id),
                  downloaded: _downloaded.contains(file.id),
                  onTap: () => _fileActions(file),
                  onMenu: () => _fileMenuSheet(file),
                  onLongPress: () => _enterSelection(fileId: file.id),
                );
              },
            ),
          )
        else
          SliverList.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              return _FileRow(
                file: file,
                selected: _selectedFiles.contains(file.id),
                downloaded: _downloaded.contains(file.id),
                onTap: () => _fileActions(file),
                onMenu: () => _fileMenuSheet(file),
                onLongPress: () => _enterSelection(fileId: file.id),
              );
            },
          ),
    ];
    return RefreshIndicator(
      onRefresh: _reloadAfterChange,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          ...folderSlivers,
          ...fileSlivers,
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
                            : (_filter.isEmpty ? '已经到底了' : '筛选结果'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
            ),
          ),
        ],
      ),
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
                    tooltip: '文件夹操作',
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
                    tooltip: '文件操作',
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
        tooltip: '文件夹操作',
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
          if (downloaded) '已下载',
        ].where((e) => e.isNotEmpty).join(' · '),
      ),
      trailing: IconButton(
        tooltip: '文件操作',
        icon: const Icon(Icons.more_vert),
        onPressed: onMenu,
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

class _PropertyHeader extends StatelessWidget {
  const _PropertyHeader({
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.desc = '',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String desc;

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
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(desc, style: Theme.of(context).textTheme.bodyMedium),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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