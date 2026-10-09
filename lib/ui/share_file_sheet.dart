import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/api/lanzou_client.dart';
import '../core/api/models.dart';
import '../core/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'web_page.dart';

/// 分享文件属性弹窗：加载时显示小圆环，加载完展示简介与文件信息，
/// 提供下载、复制链接、浏览器打开、二维码与收藏。
class ShareFileInfoSheet extends StatefulWidget {
  const ShareFileInfoSheet({
    super.key,
    required this.name,
    required this.url,
    required this.pwd,
    this.size = '',
    this.time = '',
  });

  final String name;
  final String url;
  final String pwd;
  final String size;
  final String time;

  @override
  State<ShareFileInfoSheet> createState() => _ShareFileInfoSheetState();
}

class _ShareFileInfoSheetState extends State<ShareFileInfoSheet> {
  bool _loading = true;
  bool _invalid = false;
  DirectFile? _resolved;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final client = context.read<AppController>().publicClient;
    try {
      final resolved = await client.resolveFileShare(
        widget.url,
        pwd: widget.pwd,
      );
      if (mounted) setState(() => _resolved = resolved);
    } on LanzouException catch (e) {
      if (mounted) {
        setState(
          () =>
              _invalid = e.message.contains('不存在') || e.message.contains('取消'),
        );
      }
    } catch (_) {
      // 网络异常不视为失效，下载时会有明确提示。
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _name {
    final resolved = _resolved;
    if (resolved != null && resolved.name.isNotEmpty) return resolved.name;
    return widget.name;
  }

  String get _size {
    final resolved = _resolved;
    if (resolved != null && resolved.size.isNotEmpty) return resolved.size;
    return widget.size;
  }

  String get _desc => _resolved?.desc ?? '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final app = context.read<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PropertyHeaderCard(
            icon: iconForFile(_name),
            title: _name,
            subtitle: [
              if (_size.isNotEmpty) prettyLzSize(_size),
              if (widget.time.isNotEmpty) widget.time,
            ].join(' · '),
            desc: _desc,
            loading: _loading,
          ),
          if (_invalid)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: scheme.error),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l10n.shareInvalid)),
                ],
              ),
            ),
          ListTile(
            enabled: !_invalid,
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.download),
            onTap: () {
              navigator.pop();
              downloadShareFile(
                context,
                url: widget.url,
                pwd: widget.pwd,
                fallbackName: _name,
              );
            },
          ),
          ListTile(
            enabled: !_invalid,
            leading: const Icon(Icons.copy),
            title: Text(l10n.copyLink),
            onTap: () {
              navigator.pop();
              copyText(context, widget.url);
            },
          ),
          ListTile(
            enabled: !_invalid,
            leading: const Icon(Icons.open_in_new),
            title: Text(l10n.openLink),
            onTap: () {
              navigator.pop();
              navigator.push(
                MaterialPageRoute(
                  builder: (_) => WebPage(
                    title: _name,
                    url: widget.url,
                    cookie: app.activeAccount?.cookie,
                  ),
                ),
              );
            },
          ),
          ListTile(
            enabled: !_invalid,
            leading: const Icon(Icons.qr_code),
            title: Text(l10n.showQr),
            onTap: () {
              navigator.pop();
              showQrDialog(
                // 用 navigator 的 context：弹窗刚被 pop，原 context 已失效
                navigator.context,
                title: _name,
                url: widget.url,
                pwd: widget.pwd,
              );
            },
          ),
          ListTile(
            enabled: !_invalid,
            leading: const Icon(Icons.star_outline),
            title: Text(l10n.favorite),
            onTap: () async {
              navigator.pop();
              await app.db.addFavorite(
                kind: 'shareFile',
                name: _name,
                ref: widget.url,
                pwd: widget.pwd,
                size: _size,
                sharer: _resolved?.sharer ?? '',
              );
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.addedToFavorites)),
              );
            },
          ),
        ],
      ),
    );
  }
}
