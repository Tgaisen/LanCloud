import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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
  const EmptyHint({
    super.key,
    required this.icon,
    required this.text,
    this.animate = true,
  });

  final IconData icon;
  final String text;
  /// 出现时是否淡入（提示类空状态的显隐渐变）。
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hint = Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: scheme.outline),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.outline),
          ),
        ],
      ),
    );
    return Center(child: animate ? FadeIn(child: hint) : hint);
  }
}

/// 出现时淡入：用于空状态、提示文案的显隐渐变。
class FadeIn extends StatelessWidget {
  const FadeIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 260),
    this.offset = 0,
  });

  final Widget child;
  final Duration duration;
  /// 相对位移（px），会随淡入一起归位。
  final double offset;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final faded = Opacity(opacity: t, child: child);
        if (offset == 0) return faded;
        return Transform.translate(
          offset: Offset(0, offset * (1 - t)),
          child: faded,
        );
      },
      child: child,
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

/// 统一的底部弹窗：自适应内容高度，内容超过上限时内部滚动；
/// 内容滚到顶部后继续下拉会带动整个弹窗下滑（等效 NestedScrolling），
/// 松手按拖动距离/速度决定关闭或弹回。
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget child,
  double maxHeightRatio = 0.8,
}) {
  final maxHeight = MediaQuery.sizeOf(context).height * maxHeightRatio;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: MeasuredSheet(maxHeight: maxHeight, child: child),
    ),
  );
}

/// 自适应内容高度的弹窗外壳：
/// - 先测量内容自然高度，再取 min(内容高度, 上限) 作为弹窗高度；
/// - 内容尺寸变化（例如弹出键盘）时自动重新测量；
/// - 内容滚到顶部后继续下拉，剩余位移会带动弹窗下滑（等效 Android 的
///   NestedScrolling），松手时按拖动距离与速度决定关闭或弹回。
class MeasuredSheet extends StatefulWidget {
  const MeasuredSheet({
    super.key,
    required this.child,
    required this.maxHeight,
  });

  final Widget child;
  final double maxHeight;

  @override
  State<MeasuredSheet> createState() => _MeasuredSheetState();
}

class _MeasuredSheetState extends State<MeasuredSheet>
    with SingleTickerProviderStateMixin {
  final GlobalKey _contentKey = GlobalKey();
  double? _contentHeight;

  /// 弹窗被向下拖出的距离（0 = 完全展开）。
  double _pull = 0;

  /// 松手后的弹回动画。
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Animation<double>? _settleTween;

  /// 指针速度采样：用于判断“快速下滑关闭”。
  VelocityTracker? _tracker;
  int? _pointer;

  @override
  void initState() {
    super.initState();
    _settle.addListener(_onSettleTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _onSettleTick() {
    final tween = _settleTween;
    if (tween == null) return;
    setState(() => _pull = tween.value);
  }

  void _measure() {
    if (!mounted) return;
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final height = box.size.height;
    if (height != _contentHeight) {
      setState(() => _contentHeight = height);
    }
  }

  /// 完全展开时的高度：内容自然高度，不超过上限。
  double get _expandedHeight => _contentHeight == null
      ? widget.maxHeight
      : math.min(widget.maxHeight, _contentHeight!);

  void _stopSettle() {
    if (_settle.isAnimating) _settle.stop();
    _settleTween = null;
  }

  void _springBack() {
    if (_pull <= 0) return;
    _settleTween = Tween<double>(begin: _pull, end: 0).animate(
      CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic),
    );
    _settle.forward(from: 0);
  }

  /// 手势位移分配（滚动坐标：正值 = 手指下拉）。
  /// 列表先滚到顶部，超出的位移带动弹窗下滑；反向拖动先还回弹窗。
  double _distributeDrag(double offset, ScrollMetrics position) {
    if (offset == 0) return 0;
    var remaining = offset;
    if (_pull > 0 && remaining < 0) {
      // 弹窗正被拖出时向上拖动：优先把弹窗还回去
      final back = math.min(_pull, -remaining);
      _stopSettle();
      setState(() => _pull -= back);
      remaining += back;
    }
    if (remaining <= 0) return remaining;
    final target = position.pixels - remaining;
    if (target >= position.minScrollExtent) return remaining;
    // 列表已经到顶：超出的位移交给弹窗（列表只走到顶部为止）
    final extra = position.minScrollExtent - target;
    final capacity = math.max(0.0, _expandedHeight - _pull);
    final used = math.min(extra, capacity);
    if (used > 0) {
      _stopSettle();
      setState(() => _pull += used);
    }
    return remaining - (extra - used);
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointer = event.pointer;
    _tracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _tracker?.addPosition(event.timeStamp, event.position);
  }

  void _onPointerEnd(PointerEvent event) {
    if (event.pointer != _pointer) return;
    final pull = _pull;
    final velocity = _tracker?.getVelocity().pixelsPerSecond.dy ?? 0.0;
    _pointer = null;
    _tracker = null;
    if (pull <= 0) return;
    // 快速下滑，或拖过弹窗高度的 35%：关闭弹窗，否则弹回
    final shouldClose = velocity > 700 ||
        (velocity > -700 && pull > _expandedHeight * 0.35);
    if (shouldClose) {
      Navigator.of(context).pop();
    } else {
      _springBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final measured = _contentHeight;
    final height = math.max(0.0, _expandedHeight - _pull);
    return Opacity(
      opacity: measured == null ? 0 : 1,
      child: SizedBox(
        height: height,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerEnd,
          onPointerCancel: _onPointerEnd,
          child: SingleChildScrollView(
            physics: _SheetDragPhysics(
              parent: const AlwaysScrollableScrollPhysics(),
              onOffset: _distributeDrag,
            ),
            child: NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (notification) {
                _measure();
                return false;
              },
              child: SizeChangedLayoutNotifier(
                child: SizedBox(
                  key: _contentKey,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹窗内部滚动用的物理：把“到顶后继续下拉”的位移交给弹窗（[onOffset]），
/// 列表只滚到顶部为止 —— 等效 Android 的 NestedScrolling。
class _SheetDragPhysics extends ClampingScrollPhysics {
  const _SheetDragPhysics({super.parent, required this.onOffset});

  /// 输入本次手势位移（滚动坐标：正值 = 手指下拉），
  /// 返回列表实际应用的位移。
  final double Function(double offset, ScrollMetrics position) onOffset;

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      onOffset(offset, position);

  @override
  _SheetDragPhysics applyTo(ScrollPhysics? ancestor) =>
      _SheetDragPhysics(parent: buildParent(ancestor), onOffset: onOffset);
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
