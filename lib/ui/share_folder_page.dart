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
  final Set<String> _selected = {};

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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                tooltip: l10n.exitSelection,
                icon: const Icon(Icons.close),
                onPressed: _toggleSelecting,
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: _selecting
            ? Text(l10n.selectedCount(_selected.length))
            : Text(folder.name),
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
            : [
                IconButton(
                  tooltip: l10n.multiSelect,
                  icon: const Icon(Icons.done_all),
                  onPressed: _toggleSelecting,
                ),
                IconButton(
                  tooltip: l10n.moreActions,
                  icon: const Icon(Icons.more_vert),
                  onPressed: _showMenu,
                ),
              ],
      ),
      body: ListView(
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
          if (folder.folders.isNotEmpty) ...[
            _SectionTitle(text: l10n.folder),
            SegmentedList(
              children: [
                for (final sub in folder.folders)
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
          if (folder.files.isNotEmpty) ...[
            _SectionTitle(text: l10n.files),
            SegmentedList(
              children: [
                for (final file in folder.files)
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
          if (folder.files.isEmpty && folder.folders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text(l10n.shareEmpty)),
            ),
        ],
      ),
      bottomNavigationBar: _selecting
          ? Material(
              color: scheme.surfaceContainer,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _BatchAction(
                        icon: Icons.download,
                        label: l10n.download,
                        onPressed:
                            _selected.isEmpty ? null : _downloadSelected,
                      ),
                      _BatchAction(
                        icon: Icons.copy,
                        label: l10n.copyLink,
                        onPressed:
                            _selected.isEmpty ? null : _copySelectedLinks,
                      ),
                      _BatchAction(
                        icon: Icons.star_outline,
                        label: l10n.favorite,
                        onPressed:
                            _selected.isEmpty ? null : _favoriteSelected,
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
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
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
