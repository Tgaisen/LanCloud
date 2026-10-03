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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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

  void _selectAll() {
    setState(() {
      if (_selected.length == widget.folder.files.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(widget.folder.files.map((f) => f.url));
      }
    });
  }

  void _invertSelection() {
    setState(() {
      for (final file in widget.folder.files) {
        if (!_selected.remove(file.url)) _selected.add(file.url);
      }
    });
  }

  Future<void> _downloadSelected() async {
    final files = widget.folder.files
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
    final files = widget.folder.files
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
    final files = widget.folder.files
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
        ? folder.files
        : folder.files
            .where((f) => f.name.toLowerCase().contains(query))
            .toList();
    final isEmpty =
        folder.files.isEmpty && folder.folders.isEmpty && folder.desc.isEmpty;
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
      child: Scaffold(
      appBar: AppBar(
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
                : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )),
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
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
              children: [
                for (final sub in folders)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      sub.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: sub.desc.isEmpty ? null : Text(sub.desc),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openSubfolder(sub),
                  ),
              ],
            ),
          ],
          if (files.isNotEmpty) ...[
            _SectionTitle(text: l10n.files),
            SegmentedList(
              children: [
                for (final file in files)
                  ListTile(
                    leading: _selecting
                        ? Checkbox(
                            value: _selected.contains(file.url),
                            onChanged: (_) => _toggleFile(file.url),
                          )
                        : Icon(iconForFile(file.name)),
                    title: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        prettyLzSize(file.size),
                        if (file.time.isNotEmpty) file.time,
                      ].where((e) => e.isNotEmpty).join(' · '),
                    ),
                    selected: _selecting && _selected.contains(file.url),
                    trailing: _selecting
                        ? null
                        : const Icon(Icons.chevron_right),
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
              ],
            ),
          // 空分享：提示整体居中显示（带淡入）
          if (isEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: EmptyHint(
                    icon: Icons.folder_open,
                    text: l10n.shareEmpty,
                  ),
                ),
              ),
            ),
        ],
      ),
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

