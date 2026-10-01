import 'package:flutter/material.dart' hide Icons;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
  showLoadingDialog(context, context.l10n.resolvingDownload);
  try {
    final direct = await app.publicClient.resolveFileShare(url, pwd: pwd);
    if (context.mounted) Navigator.of(context).pop();
    transfers.addDownload(
      url: direct.url,
      name: direct.name.isEmpty ? (fallbackName ?? 'download') : direct.name,
      referer: url,
      via: app.publicClient,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.addedToQueue)),
      );
    }
    return true;
  } on NeedPasswordException {
    if (context.mounted) Navigator.of(context).pop();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.shareNeedsPassword)),
      );
    }
    return false;
  } on LanzouException catch (e) {
    if (context.mounted) Navigator.of(context).pop();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  } catch (e) {
    if (context.mounted) Navigator.of(context).pop();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.resolveFailed('$e'))),
      );
    }
    return false;
  }
}
