import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
    case 'xml':
    case 'json':
    case 'yml':
    case 'yaml':
    case 'ini':
    case 'conf':
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

/// 顶栏浮层：和底栏共用同一套收起进度（[AppController.barsHide]），
/// 滚动向下时整体上滑隐藏、调出时（[AppController.animateBarsHide]）下滑显示。
///
/// 顶栏不参与列表布局，因此推动它不会改变页面的滚动位置；
/// 页面需要在列表顶部留出等高的占位（见各页面的 spacer sliver）。
class TopBarOverlay extends StatelessWidget {
  const TopBarOverlay({
    super.key,
    required this.height,
    required this.child,
  });

  /// 顶栏完整高度（状态栏 + 工具栏 + bottom），用于计算滑出距离。
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return ValueListenableBuilder<double>(
      // 顶栏用独立的收起进度（距离 = 顶栏自身高度，才能 1:1 跟手）
      valueListenable: app.topBarHide,
      child: child,
      builder: (context, hide, child) {
        // 只有开启「顶栏收起」时才跟随收起进度
        final t = app.settings.hideTopBar ? hide.clamp(0.0, 1.0) : 0.0;
        return IgnorePointer(
          ignoring: t >= 0.999,
          child: Transform.translate(
            offset: Offset(0, -height * t),
            child: child,
          ),
        );
      },
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

/// 多选操作栏里的单个操作（图标 + 文字，禁用时置灰）。
class BatchAction extends StatelessWidget {
  const BatchAction({
    super.key,
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
    final scheme = Theme.of(context).colorScheme;
    final color = enabled ? scheme.onSurface : scheme.outline;
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
            Text(label, style: TextStyle(fontSize: 12, color: color)),
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

/// 连接式分组的排布方向。
enum ConnectedAxis {
  /// 横向（按钮组）：相邻边在左右两侧。
  horizontal,

  /// 纵向（列表）：相邻边在上下两端。
  vertical,
}

/// MD3 Expressive 连接式分组的分角：
/// 组两端（外侧）用 [outer]，组内相邻处用 [inner]；
/// [axis] 决定“相邻边”在左右还是上下；
/// [pressedIndex] 命中时该条目整体放大到 [pressedRadius]，
/// 相邻条目的相邻角同步收圆到 [outer]（shape morphing）。
BorderRadius connectedItemRadius({
  required int index,
  required int count,
  required double outer,
  required double inner,
  ConnectedAxis axis = ConnectedAxis.vertical,
  int? pressedIndex,
  double? pressedRadius,
}) {
  final Radius outerRadius = Radius.circular(outer);
  final Radius innerRadius = Radius.circular(inner);
  final bool isFirst = index == 0;
  final bool isLast = index == count - 1;
  final bool horizontal = axis == ConnectedAxis.horizontal;
  // 横向：左右两端是外侧圆角；纵向：上下两端是外侧圆角
  Radius topLeft;
  Radius topRight;
  Radius bottomLeft;
  Radius bottomRight;
  if (horizontal) {
    topLeft = isFirst ? outerRadius : innerRadius;
    bottomLeft = isFirst ? outerRadius : innerRadius;
    topRight = isLast ? outerRadius : innerRadius;
    bottomRight = isLast ? outerRadius : innerRadius;
  } else {
    topLeft = isFirst ? outerRadius : innerRadius;
    topRight = isFirst ? outerRadius : innerRadius;
    bottomLeft = isLast ? outerRadius : innerRadius;
    bottomRight = isLast ? outerRadius : innerRadius;
  }

  if (pressedIndex == null || pressedRadius == null) {
    return BorderRadius.only(
      topLeft: topLeft,
      topRight: topRight,
      bottomLeft: bottomLeft,
      bottomRight: bottomRight,
    );
  }
  if (index == pressedIndex) return BorderRadius.circular(pressedRadius);
  if ((index - pressedIndex).abs() == 1) {
    if (horizontal) {
      if (index < pressedIndex) {
        topRight = outerRadius;
        bottomRight = outerRadius;
      } else {
        topLeft = outerRadius;
        bottomLeft = outerRadius;
      }
    } else if (index < pressedIndex) {
      bottomLeft = outerRadius;
      bottomRight = outerRadius;
    } else {
      topLeft = outerRadius;
      topRight = outerRadius;
    }
  }
  return BorderRadius.only(
    topLeft: topLeft,
    topRight: topRight,
    bottomLeft: bottomLeft,
    bottomRight: bottomRight,
  );
}

/// MD3 Expressive 连接式列表（Connected）：
/// - 组外侧圆角 [outerRadius]（默认 16dp），组内相邻处圆角 [innerRadius]（默认 4dp）
/// - 条目之间用空白间隔（[gap]）而不是分割线
/// - 按下时该条目圆角做 Shape Morphing（相邻条目的相邻角同步收圆）
class SegmentedList extends StatefulWidget {
  const SegmentedList({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.all(4),
    this.padding = EdgeInsets.zero,
    this.color,
    this.outerRadius = 16,
    this.innerRadius = 4,
    this.pressedRadius = 28,
    this.gap = 2,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final Color? color;
  /// 组两端（外侧）圆角。
  final double outerRadius;
  /// 组内相邻处的圆角。
  final double innerRadius;
  /// 按下时该条目的圆角。
  final double pressedRadius;
  /// 条目之间的空白间隔（替代分割线）。
  final double gap;

  @override
  State<SegmentedList> createState() => _SegmentedListState();
}

class _SegmentedListState extends State<SegmentedList> {
  int? _pressedIndex;

  void _setPressed(int? index) {
    if (_pressedIndex != index && mounted) setState(() => _pressedIndex = index);
  }

  /// 计算单个条目的圆角：组外侧 16dp、组内相邻处 4dp；
  /// 按下时整体放大，相邻条目的相邻角同步收圆。
  BorderRadius _radiusFor(int index, int count) => connectedItemRadius(
    index: index,
    count: count,
    outer: widget.outerRadius,
    inner: widget.innerRadius,
    pressedIndex: _pressedIndex,
    pressedRadius: widget.pressedRadius,
  );

  Widget _item(BuildContext context, ColorScheme scheme, int index, int count) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: widget.color ?? scheme.surfaceContainerLow,
        borderRadius: _radiusFor(index, count),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Listener(
          onPointerDown: (_) => _setPressed(index),
          onPointerUp: (_) => _setPressed(null),
          onPointerCancel: (_) => _setPressed(null),
          child: Padding(
            padding: widget.padding,
            child: widget.children[index],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = widget.children.length;
    return Padding(
      padding: widget.margin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) SizedBox(height: widget.gap),
            _item(context, scheme, i, count),
          ],
        ],
      ),
    );
  }
}

/// MD3 Expressive 连接式按钮组（Connected button group）：
/// 外侧 [outerRadius]（16dp）、组内相邻处 [innerRadius]（4dp），
/// 条目之间是空白间隔；选中项用主题色（secondaryContainer）强调，
/// 不把图标替换成对勾，按下时做 shape morphing。
///
/// 目前仅支持单选（[selected] 取第一个命中项，重复点选不取消）。
class ConnectedSegmentedButton<T> extends StatefulWidget {
  const ConnectedSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.margin = EdgeInsets.zero,
    this.outerRadius = 16,
    this.innerRadius = 4,
    this.pressedRadius = 28,
    this.gap = 2,
    this.expanded = true,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final EdgeInsetsGeometry margin;
  final double outerRadius;
  final double innerRadius;
  final double pressedRadius;
  final double gap;

  /// 是否让每个按钮等分整行宽度。
  final bool expanded;

  @override
  State<ConnectedSegmentedButton<T>> createState() =>
      _ConnectedSegmentedButtonState<T>();
}

class _ConnectedSegmentedButtonState<T>
    extends State<ConnectedSegmentedButton<T>> {
  int? _pressedIndex;

  void _setPressed(int? index) {
    if (_pressedIndex != index && mounted) setState(() => _pressedIndex = index);
  }

  void _select(T value) {
    final onChanged = widget.onSelectionChanged;
    if (onChanged == null || widget.selected.contains(value)) return;
    onChanged({value});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = widget.segments.length;
    return Padding(
      padding: widget.margin,
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) SizedBox(width: widget.gap),
            if (widget.expanded)
              Expanded(child: _segment(context, scheme, i, count))
            else
              _segment(context, scheme, i, count),
          ],
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    ColorScheme scheme,
    int index,
    int count,
  ) {
    final segment = widget.segments[index];
    final enabled = segment.enabled && widget.onSelectionChanged != null;
    final selected = widget.selected.contains(segment.value);
    final radius = connectedItemRadius(
      index: index,
      count: count,
      outer: widget.outerRadius,
      inner: widget.innerRadius,
      axis: ConnectedAxis.horizontal,
      pressedIndex: _pressedIndex,
      pressedRadius: widget.pressedRadius,
    );
    final Color foreground = !enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : selected
            ? scheme.onSecondaryContainer
            : scheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: radius,
        border: Border.all(
          color: selected ? Colors.transparent : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? () => _select(segment.value) : null,
          onHighlightChanged: (pressed) => _setPressed(pressed ? index : null),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (segment.icon != null) ...[
                  IconTheme.merge(
                    data: IconThemeData(size: 18, color: foreground),
                    child: segment.icon!,
                  ),
                  if (segment.label != null) const SizedBox(width: 8),
                ],
                if (segment.label != null)
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    child: segment.label!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 批量操作进度报告：current 为当前处理到第几项（从 1 起），detail 为当前项说明。
typedef BatchProgressReport = void Function(int current, String detail);

/// 批量操作进度弹窗（MD3E 风格，内容居中）：
/// 圆角进度条 + “1/20” 计数 + 当前处理项，[run] 完成后自动关闭。
/// 操作进行中不可用返回键关闭。
Future<void> runBatchWithProgress(
  BuildContext context, {
  required String title,
  required int total,
  required Future<void> Function(BatchProgressReport report) run,
}) async {
  final navigator = Navigator.of(context);
  final current = ValueNotifier<int>(1);
  final detail = ValueNotifier<String>('');
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BatchProgressDialog(
      title: title,
      total: total,
      current: current,
      detail: detail,
    ),
  );
  try {
    await run((value, text) {
      current.value = value.clamp(1, total);
      detail.value = text;
    });
  } finally {
    if (navigator.canPop()) navigator.pop();
  }
}

class _BatchProgressDialog extends StatelessWidget {
  const _BatchProgressDialog({
    required this.title,
    required this.total,
    required this.current,
    required this.detail,
  });

  final String title;
  final int total;
  final ValueListenable<int> current;
  final ValueListenable<String> detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title, textAlign: TextAlign.center),
        content: SizedBox(
          width: 240,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ValueListenableBuilder<int>(
                valueListenable: current,
                builder: (context, value, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total <= 0
                            ? null
                            : (value / total).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('$value/$total', style: textTheme.labelLarge),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              ValueListenableBuilder<String>(
                valueListenable: detail,
                builder: (context, text, _) => SizedBox(
                  width: double.infinity,
                  child: Text(
                    text.isEmpty ? ' ' : text,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
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
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  var added = 0;
  var failed = 0;
  await runBatchWithProgress(
    context,
    title: l10n.batchDownload,
    total: urls.length,
    run: (report) async {
      for (var i = 0; i < urls.length; i++) {
        report(i + 1, names[i]);
        try {
          final direct = await app.publicClient.resolveFileShare(
            urls[i],
            pwd: pwd,
          );
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
    },
  );
  if (!context.mounted) return;
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
