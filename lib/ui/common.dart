import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Icons;
import 'package:flutter/services.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
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

/// 系统身份验证弹窗（生物识别 / 锁屏密码）的本地化文案。
/// Android 取标题 + 副标题 + 取消按钮，iOS 只有取消按钮（其余用系统文案）。
List<AuthMessages> authMessagesFor(AppLocalizations l10n) => [
      AndroidAuthMessages(
        signInTitle: l10n.authVerifyTitle,
        signInHint: l10n.authVerifyHint,
        cancelButton: l10n.cancel,
      ),
      IOSAuthMessages(cancelButton: l10n.cancel),
    ];

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
    required this.background,
    required this.builder,
  });

  /// 顶栏完整高度（状态栏 + 工具栏 + bottom），用于计算滑出距离。
  final double height;

  /// 顶栏底色：和设置/关于页一样，只随滚动从 surface 过渡到
  /// surfaceContainer，不参与渐隐。页面里的 AppBar 用透明底。
  final Color background;

  /// 构建顶栏。位移与内容渐隐由本组件统一处理：标题、按钮、路径栏
  /// 1:1 跟随手指淡出，底色始终保持不透明。
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return ValueListenableBuilder<double>(
      // 顶栏用独立的收起进度（距离 = 顶栏自身高度，才能 1:1 跟手）
      valueListenable: app.topBarHide,
      builder: (context, hide, _) {
        // 只有开启「顶栏收起」时才跟随收起进度
        final t = app.settings.hideTopBar ? hide.clamp(0.0, 1.0) : 0.0;
        return IgnorePointer(
          ignoring: t >= 0.999,
          child: Transform.translate(
            offset: Offset(0, -height * t),
            child: Stack(
              children: [
                // 不透明底色（参数同设置/关于页），渐隐只作用于内容
                Positioned.fill(child: ColoredBox(color: background)),
                Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: builder(context),
                ),
              ],
            ),
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

/// 分组标题 + 数量 chip（传输、收藏等列表视图共用）。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
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
    final color = enabled
        ? scheme.onSurface
        : scheme.outline.withValues(alpha: 0.6);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

/// MD3E 标准列表项：圆角图标块 + 标题 / 副标题 + 尾部操作。
/// 首页（快速访问、最近使用）、传输、收藏共用，参数与网盘列表项一致：
/// 内边距 10/8、图标块 42dp（圆角 12）、标题 bodyLarge、副标题 bodyMedium。
class Md3ListItem extends StatelessWidget {
  const Md3ListItem({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.selected = false,
    this.iconBoxColor,
    this.bottom,
    this.titleMaxLines = 1,
    this.subtitleMaxLines = 1,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 尾部操作（⋯、重试、打开等）。
  final Widget? trailing;

  /// 多选选中态：整行填主色容器，圆角由外层分组控制。
  final bool selected;

  /// 图标块底色，默认 secondaryContainer。
  final Color? iconBoxColor;

  /// 标题行下方的附加内容（例如传输进度条）。
  final Widget? bottom;

  final int titleMaxLines;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ColoredBox(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.surface
                            : iconBoxColor ?? scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        selected ? Icons.check_circle : icon,
                        size: 22,
                        color: selected
                            ? scheme.primary
                            : scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: titleMaxLines,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge,
                          ),
                          if (subtitle.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                subtitle,
                                maxLines: subtitleMaxLines,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 4),
                      trailing!,
                    ],
                  ],
                ),
                if (bottom != null) ...[
                  const SizedBox(height: 10),
                  bottom!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// MD3E 中号宽版图标按钮：胶囊形容器（默认 surfaceContainerLow，与列表卡片同色）
/// + 24dp 图标，说明文字放在按钮下方。首页「打开链接 / 传输中心」使用。
class ExpressiveIconButton extends StatelessWidget {
  const ExpressiveIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badge,
    this.width = 72,
    this.height = 56,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// 角标文字（例如进行中的传输数量）。
  final String? badge;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iconWidget = Icon(icon, size: 24, color: scheme.onSurfaceVariant);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: scheme.surfaceContainerLow,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: width,
              height: height,
              child: Center(
                child: badge == null
                    ? iconWidget
                    : Badge(label: Text(badge!), child: iconWidget),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// MD3E 路径胶囊：当前项用主色容器强调，其余为中性容器。
/// 网盘路径栏与文件夹选择弹窗共用。
class PathChip extends StatelessWidget {
  const PathChip({
    super.key,
    required this.label,
    required this.current,
    required this.onTap,
    this.verticalPadding = 8,
  });

  final String label;
  final bool current;
  final VoidCallback onTap;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Material(
        // 只有当前目录带底色，上级目录保持透明
        color: current ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                color: current
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 多选底部操作栏（MD3E）：悬浮圆角容器，操作项均分整行。
/// 网盘、传输、收藏、分享浏览页共用，样式保持一致。
class BatchActionBar extends StatelessWidget {
  const BatchActionBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Material(
          // 与列表卡片区分：用最浅的容器色，不加阴影
          elevation: 0,
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                for (final child in children) Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// MD3E 分区标题：标题文字 + 右侧展开/折叠按钮（IconButton，带旋转动画），
/// 下方内容用 SegmentedList 分组承载。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.expanded = true,
    this.onToggle,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  /// 是否展开；只有提供 [onToggle] 时才可折叠。
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final header = Padding(
      // 与分组（SegmentedList 自带 4dp 外边距）左对齐
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?trailing,
          if (onToggle != null)
            IconButton(
              tooltip: expanded ? context.l10n.collapse : context.l10n.expand,
              style: IconButton.styleFrom(
                // 与分组卡片同底色，展开 / 收起按钮浮在标题行右侧
                backgroundColor: scheme.surfaceContainerLow,
                foregroundColor: scheme.onSurfaceVariant,
              ),
              onPressed: onToggle,
              icon: AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: const Icon(Icons.chevron_right),
              ),
            ),
        ],
      ),
    );
    // 底色与圆角交给分组本身，标题行保持透明
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 只有右侧 IconButton 能展开 / 收起，标题行本身不响应点击
          header,
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              // 展开时内容淡入 + 高度过渡，收起时高度收拢
              child: AnimatedOpacity(
                opacity: expanded ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: expanded
                    ? child
                    : const SizedBox(width: double.infinity, height: 0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 属性弹窗顶部信息卡（MD3E）：圆角容器 + 主色图标块 + 标题/信息/简介。
/// 文件、文件夹、分享文件属性弹窗共用。
class PropertyHeaderCard extends StatelessWidget {
  const PropertyHeaderCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.desc = '',
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String desc;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // 比 surfaceContainerHighest 浅一档，弹窗里更轻盈
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, size: 28, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (loading) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ],
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: Text(
                            subtitle,
                            key: ValueKey(subtitle),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.outline),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: Text(
                    desc,
                    key: ValueKey(desc),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ),
            ],
          ],
        ),
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

/// 访问密码编辑结果：enabled 为是否启用，pwd 为密码（关闭时为空）。
typedef PasswordEditResult = ({bool enabled, String pwd});

/// 访问密码弹窗：顶部「启用访问密码」开关 + 密码输入框。
/// 打开前应先取到当前是否启用与密码，用于预填开关和输入框；
/// 关闭开关后确认即表示关闭访问密码。
Future<PasswordEditResult?> showPasswordDialog(
  BuildContext context, {
  required bool enabled,
  required String pwd,
}) {
  final controller = TextEditingController(text: pwd);
  var isEnabled = enabled;
  String? error;
  // 注意：不在弹窗关闭时立即 dispose 控制器——退场动画期间组件仍会重建。
  return showDialog<PasswordEditResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final l10n = context.l10n;
        return AlertDialog(
          title: Text(l10n.accessPassword),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.enablePassword),
                value: isEnabled,
                onChanged: (value) => setDialogState(() {
                  isEnabled = value;
                  error = null;
                }),
              ),
              TextField(
                controller: controller,
                enabled: isEnabled,
                maxLength: 6,
                autofocus: isEnabled,
                decoration: InputDecoration(
                  hintText: l10n.pwdHint,
                  errorText: error,
                ),
                onChanged: (_) {
                  if (error != null) setDialogState(() => error = null);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (isEnabled && value.length < 2) {
                  setDialogState(() => error = l10n.pwdTooShort);
                  return;
                }
                Navigator.of(dialogContext).pop(
                  (enabled: isEnabled, pwd: isEnabled ? value : ''),
                );
              },
              child: Text(l10n.confirm),
            ),
          ],
        );
      },
    ),
  );
}

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
  final theme = Theme.of(context);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 24, 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 20),
            Flexible(child: Text(text, style: theme.textTheme.bodyLarge)),
          ],
        ),
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
