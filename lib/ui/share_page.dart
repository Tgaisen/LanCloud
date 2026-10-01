import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/api/lanzou_client.dart';
import '../core/api/models.dart';
import '../core/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'share_folder_page.dart';
import 'share_file_sheet.dart';

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
    });
    final client = context.read<AppController>().publicClient;
    try {
      if (_looksLikeFolder) {
        final folder = await client.resolveFolderShare(link, pwd: pwd);
        if (!mounted) return;
        await _saveRecent('shareFolder', folder.name, link, pwd);
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ShareFolderPage(
              folder: folder,
              link: link,
              pwd: pwd,
            ),
          ),
        );
      } else {
        try {
          final file = await client.resolveFileShare(link, pwd: pwd);
          if (!mounted) return;
          setState(() => _file = file);
          await _saveRecent('shareFile', file.name, link, pwd);
        } on LanzouException {
          final folder = await client.resolveFolderShare(link, pwd: pwd);
          if (!mounted) return;
          await _saveRecent('shareFolder', folder.name, link, pwd);
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ShareFolderPage(
                folder: folder,
                link: link,
                pwd: pwd,
              ),
            ),
          );
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
              pwd: _pwdController.text.trim(),
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
    required this.pwd,
  });

  final DirectFile file;
  final String link;
  final String pwd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(iconForFile(file.name), size: 30),
        title: Text(
          file.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: file.size.isEmpty
            ? null
            : Text(l10n.sizeLabel(prettyLzSize(file.size))),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => ShareFileInfoSheet(
            name: file.name,
            url: link,
            pwd: pwd,
            size: file.size,
          ),
        ),
      ),
    );
  }
}

