import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api/lanzou_client.dart';
import '../core/api/models.dart';
import '../core/app_controller.dart';
import '../l10n/l10n.dart';
import 'common.dart';

class SharePage extends StatefulWidget {
  const SharePage({super.key, this.initialLink, this.initialPwd});

  final String? initialLink;
  final String? initialPwd;

  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  late final TextEditingController _linkController =
      TextEditingController(text: widget.initialLink ?? '');
  late final TextEditingController _pwdController =
      TextEditingController(text: widget.initialPwd ?? '');
  bool _loading = false;
  String? _error;
  DirectFile? _file;
  FolderShareDetail? _folder;

  @override
  void initState() {
    super.initState();
    if (widget.initialLink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _parse());
    }
  }

  @override
  void dispose() {
    _linkController.dispose();
    _pwdController.dispose();
    super.dispose();
  }

  bool get _looksLikeFolder {
    final link = _linkController.text.trim();
    return RegExp(r'lanzou[a-z]*\.com/(s/)?b[a-zA-Z0-9]{7,}').hasMatch(link);
  }

  Future<void> _parse() async {
    final link = _linkController.text.trim();
    final pwd = _pwdController.text.trim();
    if (link.isEmpty) {
      setState(() => _error = context.l10n.pleasePasteShareLink);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _file = null;
      _folder = null;
    });
    final client = context.read<AppController>().publicClient;
    try {
      if (_looksLikeFolder) {
        final folder = await client.resolveFolderShare(link, pwd: pwd);
        if (!mounted) return;
        setState(() => _folder = folder);
        await _saveRecent('shareFolder', folder.name, link, pwd);
      } else {
        try {
          final file = await client.resolveFileShare(link, pwd: pwd);
          if (!mounted) return;
          setState(() => _file = file);
          await _saveRecent('shareFile', file.name, link, pwd);
        } on LanzouException {
          final folder = await client.resolveFolderShare(link, pwd: pwd);
          if (!mounted) return;
          setState(() => _folder = folder);
          await _saveRecent('shareFolder', folder.name, link, pwd);
        }
      }
    } on NeedPasswordException catch (e) {
      setState(() => _error = e.message);
    } on LanzouException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = context.l10n.resolveFailed('$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveRecent(String kind, String name, String link, String pwd) async {
    final app = context.read<AppController>();
    await app.db.addRecent(
      account: app.activeUid ?? '',
      kind: kind,
      name: name,
      ref: link,
      pwd: pwd,
    );
  }

  Future<void> _favorite() async {
    final app = context.read<AppController>();
    final link = _linkController.text.trim();
    final pwd = _pwdController.text.trim();
    if (_file != null) {
      await app.db.addFavorite(
        kind: 'shareFile',
        name: _file!.name,
        ref: link,
        pwd: pwd,
        size: _file!.size,
      );
    } else if (_folder != null) {
      await app.db.addFavorite(
        kind: 'shareFolder',
        name: _folder!.name,
        ref: link,
        pwd: pwd,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.addedToFavorites)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.openShare)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _linkController,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: l10n.shareLink,
              hintText: l10n.shareLinkHint,
              prefixIcon: const Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pwdController,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: l10n.passwordOptional,
              prefixIcon: const Icon(Icons.password),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _parse,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(_loading ? l10n.resolving : l10n.resolve),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_error!),
              ),
            ),
          ],
          if (_file != null) ...[
            const SizedBox(height: 16),
            _FileResultCard(
              file: _file!,
              link: _linkController.text.trim(),
              onDownload: () => downloadShareFile(
                context,
                url: _linkController.text.trim(),
                pwd: _pwdController.text.trim(),
                fallbackName: _file!.name,
              ),
              onFavorite: _favorite,
            ),
          ],
          if (_folder != null) ...[
            const SizedBox(height: 16),
            _FolderResultView(
              folder: _folder!,
              link: _linkController.text.trim(),
              pwd: _pwdController.text.trim(),
              onFavorite: _favorite,
            ),
          ],
        ],
      ),
    );
  }
}

class _FileResultCard extends StatelessWidget {
  const _FileResultCard({
    required this.file,
    required this.link,
    required this.onDownload,
    required this.onFavorite,
  });

  final DirectFile file;
  final String link;
  final VoidCallback onDownload;
  final Future<void> Function() onFavorite;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(iconForFile(file.name), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    file.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (file.size.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(l10n.sizeLabel(prettyLzSize(file.size))),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download),
                    label: Text(l10n.download),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: l10n.favorite,
                  onPressed: onFavorite,
                  icon: const Icon(Icons.star_outline),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: l10n.copyLink,
                  onPressed: () => copyText(context, link),
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderResultView extends StatelessWidget {
  const _FolderResultView({
    required this.folder,
    required this.link,
    required this.pwd,
    required this.onFavorite,
  });

  final FolderShareDetail folder;
  final String link;
  final String pwd;
  final Future<void> Function() onFavorite;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_outlined, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    folder.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: l10n.favorite,
                  onPressed: onFavorite,
                  icon: const Icon(Icons.star_outline),
                ),
                IconButton(
                  tooltip: l10n.copyLink,
                  onPressed: () => copyText(context, link),
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            if (folder.desc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 6),
                child: Text(folder.desc),
              ),
            if (folder.folders.isNotEmpty) ...[
              const Divider(),
              for (final sub in folder.folders)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(sub.name),
                  subtitle: sub.desc.isEmpty ? null : Text(sub.desc),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SharePage(initialLink: sub.url, initialPwd: pwd),
                    ),
                  ),
                ),
            ],
            if (folder.files.isNotEmpty) ...[
              const Divider(),
              for (final file in folder.files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(iconForFile(file.name)),
                  title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      prettyLzSize(file.size),
                      if (file.time.isNotEmpty) file.time,
                    ].where((e) => e.isNotEmpty).join(' · '),
                  ),
                  trailing: const Icon(Icons.download_outlined),
                  onTap: () => downloadShareFile(
                    context,
                    url: file.url,
                    pwd: pwd,
                    fallbackName: file.name,
                  ),
                ),
            ],
            if (folder.files.isEmpty && folder.folders.isEmpty)
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(l10n.shareEmpty),
              ),
          ],
        ),
      ),
    );
  }
}
