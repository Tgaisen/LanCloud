import 'package:flutter/material.dart' hide Icons;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/api/lanzou_client.dart';
import '../core/app_controller.dart';
import '../core/transfer/transfer_manager.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
}

/// 时间戳 -> yyyy-MM-dd（用于收藏副标题）。
String formatDateShort(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final mm = date.month.toString().padLeft(2, '0');
  final dd = date.day.toString().padLeft(2, '0');
  return '${date.year}-$mm-$dd';
}

/// 蓝奏云接口返回的大小是 "1.2 M" 这类文本。
String prettyLzSize(String raw) {
  final text = raw.trim().replaceAll(' ', '');
  if (text.isEmpty) return '';
  final m = RegExp(r'^([\d.]+)([BKMG]?)$').firstMatch(text.toUpperCase());
  if (m == null) return raw;
  final value = double.tryParse(m.group(1)!) ?? 0;
  final unit = m.group(2) ?? '';
  switch (unit) {
    case 'B':
      return formatBytes(value.round());
    case 'K':
      return formatBytes((value * 1024).round());
    case 'G':
      return formatBytes((value * 1024 * 1024 * 1024).round());
    case 'M':
    default:
      return formatBytes((value * 1024 * 1024).round());
  }
}

int lzSizeToBytes(String raw) {
  final text = raw.trim().replaceAll(' ', '').toUpperCase();
  final m = RegExp(r'^([\d.]+)([BKMG]?)$').firstMatch(text);
  if (m == null) return 0;
  final value = double.tryParse(m.group(1)!) ?? 0;
  switch (m.group(2) ?? 'M') {
    case 'B':
      return value.round();
    case 'K':
      return (value * 1024).round();
    case 'G':
      return (value * 1024 * 1024 * 1024).round();
    default:
      return (value * 1024 * 1024).round();
  }
}

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.copiedToClipboard)),
    );
  }
}

IconData iconForFile(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'bmp':
      return Icons.image_outlined;
    case 'mp4':
    case 'mkv':
    case 'avi':
    case 'mov':
      return Icons.movie_outlined;
    case 'mp3':
    case 'flac':
    case 'wav':
    case 'm4a':
      return Icons.music_note_outlined;
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return Icons.folder_zip_outlined;
    case 'apk':
      return Icons.android_outlined;
    case 'exe':
    case 'msi':
      return Icons.window_outlined;
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'doc':
    case 'docx':
      return Icons.description_outlined;
    case 'xls':
    case 'xlsx':
      return Icons.table_chart_outlined;
    case 'ppt':
    case 'pptx':
      return Icons.slideshow_outlined;
    case 'txt':
    case 'md':
    case 'log':
      return Icons.article_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: scheme.outline),
            const SizedBox(height: 8),
            Text(text, style: TextStyle(color: scheme.outline)),
          ],
        ),
      ),
    );
  }
}

/// 本地生成二维码弹窗（不经过任何服务器）。
Future<void> showQrDialog(
  BuildContext context, {
  required String title,
  required String url,
  String pwd = '',
}) async {
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

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child:
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                ),
                ?trailing,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// MD3 Expressive 分段列表：
/// 圆角容器内整宽涟漪 + 条目间“带间距（With Gap）”分隔线，
/// 按下时容器圆角做 Shape Morphing 动画。
class SegmentedList extends StatefulWidget {
  const SegmentedList({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.all(4),
    this.padding = EdgeInsets.zero,
    this.color,
    this.restRadius = 16,
    this.pressedRadius = 28,
    this.dividerGap = 16,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double restRadius;
  final double pressedRadius;
  final double dividerGap;

  @override
  State<SegmentedList> createState() => _SegmentedListState();
}

class _SegmentedListState extends State<SegmentedList> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = _pressed ? widget.pressedRadius : widget.restRadius;
    return Padding(
      padding: widget.margin,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: widget.restRadius, end: radius),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, r, child) => Material(
          color: widget.color ?? scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(r),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
        child: Listener(
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: Padding(
            padding: widget.padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: widget.dividerGap,
                      endIndent: widget.dividerGap,
                    ),
                  widget.children[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showLoadingDialog(BuildContext context, String text) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

/// 解析分享链接并把文件加入下载队列。
Future<bool> downloadShareFile(
  BuildContext context, {
  required String url,
  String pwd = '',
  String? fallbackName,
}) async {
  final app = context.read<AppController>();
  final transfers = context.read<TransferManager>();
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  showLoadingDialog(context, l10n.resolvingDownload);
  try {
    final direct = await app.publicClient.resolveFileShare(url, pwd: pwd);
    navigator.pop();
    transfers.addDownload(
      url: direct.url,
      name: direct.name.isEmpty ? (fallbackName ?? 'download') : direct.name,
      referer: url,
      via: app.publicClient,
    );
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.addedToQueue)),
    );
    return true;
  } on NeedPasswordException {
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.shareNeedsPassword)),
    );
    return false;
  } on LanzouException catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  } catch (e) {
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.resolveFailed('$e'))),
    );
    return false;
  }
}

/// 批量解析分享文件并加入下载队列（分享文件夹多选用）。
Future<void> downloadShareFiles(
  BuildContext context, {
  required List<String> urls,
  required List<String> names,
  String pwd = '',
}) async {
  if (urls.isEmpty || urls.length != names.length) return;
  final app = context.read<AppController>();
  final transfers = context.read<TransferManager>();
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  showLoadingDialog(context, l10n.resolvingDownload);
  var added = 0;
  var failed = 0;
  for (var i = 0; i < urls.length; i++) {
    try {
      final direct = await app.publicClient.resolveFileShare(urls[i], pwd: pwd);
      transfers.addDownload(
        url: direct.url,
        name: direct.name.isEmpty ? names[i] : direct.name,
        referer: urls[i],
        via: app.publicClient,
      );
      added += 1;
    } catch (_) {
      failed += 1;
    }
  }
  navigator.pop();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        failed == 0
            ? l10n.addedDownloads(added)
            : l10n.addedDownloadsPartial(added, failed),
      ),
    ),
  );
}
