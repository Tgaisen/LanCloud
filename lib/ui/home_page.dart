import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/data/app_db.dart';
import '../core/transfer/transfer_manager.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'drive_page.dart';
import 'scroll_tint.dart';
import 'share_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  List<RecentItem> _recents = [];
  List<FavoriteItem> _favorites = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    final uid = app.activeUid ?? '';
    final recents = await app.db.recents(uid, limit: 6);
    final favorites = await app.db.favorites();
    if (!mounted) return;
    setState(() {
      _recents = recents;
      _favorites = favorites.take(6).toList();
      _loading = false;
    });
  }

  Future<void> _openItem(
    BuildContext context,
    String kind,
    String ref,
    String name,
    String pwd,
  ) async {
    switch (kind) {
      case 'folder':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DrivePage(initialFolderId: ref, initialName: name),
          ),
        );
      case 'file':
        await _showOwnFileActions(context, ref, name);
      case 'shareFile':
      case 'shareFolder':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SharePage(initialLink: ref, initialPwd: pwd),
          ),
        );
    }
    if (mounted) _load();
  }

  Future<void> _showOwnFileActions(
    BuildContext context,
    String fileId,
    String name,
  ) async {
    final app = context.read<AppController>();
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
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final client = app.client;
                if (client == null) return;
                try {
                  final info = await client.shareInfoOfFile(fileId);
                  if (!context.mounted) return;
                  await downloadShareFile(
                    context,
                    url: info.url,
                    pwd: info.pwd,
                    fallbackName: name,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: Text(context.l10n.copyLink),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final client = app.client;
                if (client == null) return;
                try {
                  final info = await client.shareInfoOfFile(fileId);
                  if (!context.mounted) return;
                  await copyText(
                    context,
                    info.pwd.isEmpty
                        ? info.url
                        : context.l10n.linkWithPassword(info.url, info.pwd),
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.watch<AppController>();
    final transfers = context.watch<TransferManager>();
    final l10n = context.l10n;
    final running = transfers.tasks
        .where((t) =>
            t.status == TransferStatus.running ||
            t.status == TransferStatus.queued)
        .length;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              // floating：向上滚动立刻开始出现；pinned 只由设置决定
              floating: app.settings.hideTopBar,
              snap: false,
              pinned: !app.settings.hideTopBar,
              backgroundColor: Color.lerp(
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surfaceContainerHighest,
                ScrollTint.of(context),
              ),
              scrolledUnderElevation: 0,
              title: const Text('LanCloud'),
              actions: [
                IconButton(
                  tooltip: l10n.openShareLink,
                  icon: const Icon(Icons.link),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SharePage()),
                  ),
                ),
                IconButton(
                  tooltip: l10n.scanComingSoonTooltip,
                  icon: const Icon(Icons.qr_code),
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.scanComingSoon)),
                  ),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SharePage(),
                            ),
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: Text(l10n.openShareLink),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: Text(
                            running > 0
                                ? l10n.transferringCount(running)
                                : l10n.transferCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: l10n.quickAccess,
                    child: EmptyHint(
                      icon: Icons.push_pin_outlined,
                      text: l10n.quickAccessHint,
                    ),
                  ),
                  SectionCard(
                    title: l10n.recent,
                    child: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : (_recents.isEmpty
                            ? EmptyHint(
                                icon: Icons.history,
                                text: l10n.noRecent,
                              )
                            : Column(
                                children: [
                                  for (final item in _recents)
                                    ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(horizontal: 16),
                                      leading: Icon(
                                        item.kind.contains('folder')
                                            ? Icons.folder_outlined
                                            : iconForFile(item.name),
                                      ),
                                      title: Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        item.kind.startsWith('share')
                                            ? l10n.sharedContent
                                            : l10n.myDrive,
                                      ),
                                      onTap: () => _openItem(
                                        context,
                                        item.kind,
                                        item.ref,
                                        item.name,
                                        item.pwd,
                                      ),
                                    ),
                                ],
                              )),
                  ),
                  SectionCard(
                    title: l10n.myFavorites,
                    child: _loading
                        ? const SizedBox.shrink()
                        : (_favorites.isEmpty
                            ? EmptyHint(
                                icon: Icons.star_border,
                                text: l10n.favoritesHint,
                              )
                            : Column(
                                children: [
                                  for (final item in _favorites)
                                    ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(horizontal: 16),
                                      leading: Icon(
                                        item.kind.contains('folder')
                                            ? Icons.folder_special_outlined
                                            : Icons.star_outline,
                                      ),
                                      title: Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        item.kind.startsWith('share')
                                            ? l10n.sharedContent
                                            : l10n.myDrive,
                                      ),
                                      onTap: () => _openItem(
                                        context,
                                        item.kind,
                                        item.ref,
                                        item.name,
                                        item.pwd,
                                      ),
                                      trailing: IconButton(
                                        tooltip: l10n.unfavorite,
                                        icon: const Icon(Icons.close),
                                        onPressed: () async {
                                          await app.db
                                              .removeFavorite(item.ref);
                                          _load();
                                        },
                                      ),
                                    ),
                                ],
                              )),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
