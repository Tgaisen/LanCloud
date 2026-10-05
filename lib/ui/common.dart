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
import 'scroll_tint.dart';

/// 大屏（平板 / 桌面）布局阈值：≥640dp 时用侧栏 + 圆角内容卡片。
const double kLargeLayoutBreakpoint = 640;

/// 网盘页路径栏高度（顶栏的 bottom 部分）。
const double kDrivePathBarHeight = 46;

/// 传输页上传 / 下载切换栏高度（顶栏的 bottom 部分）。
const double kTransfersTabBarHeight = 58;

/// MD3 模态底部弹窗的默认宽度上限：窗口比它宽时弹窗居中显示，
/// 两侧不会贴到屏幕边缘（也就用不到挖孔 / 导航栏的左右让位）。
const double kModalSheetMaxWidth = 640;

/// 是否是大屏布局（侧栏 + 圆角主视图）。
bool isLargeLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kLargeLayoutBreakpoint;

/// M3 窗口宽度档位（Window size classes）对应的列表列数：
/// Compact（<600dp）1 列、Medium（600–839dp）2 列、Expanded / Extra-large（≥840dp）3 列。
int adaptiveColumnsForWidth(double width) {
  if (width >= 840) return 3;
  if (width >= 600) return 2;
  return 1;
}

/// 当前窗口宽度对应的列表列数（[adaptiveColumnsForWidth] 的 BuildContext 版本）。
int adaptiveColumns(BuildContext context) =>
    adaptiveColumnsForWidth(MediaQuery.sizeOf(context).width);

/// 大屏外壳里的页面（侧栏布局的第一个路由），或外面套了 [Md3ePageFrame]
/// 的独立页面：背景由圆角卡片绘制，页面自己必须透明，否则会盖住卡片。
bool transparentPageBackground(BuildContext context) =>
    isLargeLayout(context) &&
    ((ModalRoute.of(context)?.isFirst ?? true) || Md3eFramedScope.of(context));

/// 顶栏底色：大屏布局固定用 surfaceContainer（导航区颜色，与侧栏一致），
/// 手机布局保持随滚动在 surface → surfaceContainer 之间过渡。
Color topBarBackgroundColor(BuildContext context, ColorScheme scheme) {
  if (isLargeLayout(context)) return scheme.surfaceContainer;
  return Color.lerp(
        scheme.surface,
        scheme.surfaceContainer,
        ScrollTint.of(context),
      ) ??
      scheme.surface;
}

/// 是否在标签外壳（第一个路由）里；push 出来的独立页面返回 false。
bool inRootShell(BuildContext context) =>
    ModalRoute.of(context)?.isFirst ?? true;

/// 页面底部被占住的高度：外壳里等于底栏的完整高度（内容 + 系统手势区），
/// 独立页面等于系统导航栏高度。滚动列表末尾留白、FAB 避让都用它。
///
/// 外壳的大屏（横屏 / 平板）布局里，正文卡片已经让开了系统导航栏
/// （8dp + inset），页面里不再重复补，返回 0；没有卡片的大屏页面
/// （例如独立打开的标签页）仍按系统导航栏高度补。
///
/// 必须在页面自己的上下文里读：Scaffold 会给正文、FAB 等槽位清掉底部内边距。
double bottomObstructionHeight(BuildContext context) {
  if (inRootShell(context) && isLargeLayout(context)) return 0;
  return MediaQuery.paddingOf(context).bottom;
}

/// 外壳底栏盖在正文上方时（外壳 Scaffold 开了 extendBody），滚动列表末尾
/// 需要补的留白＝底栏完整高度，最后一条内容才能完全滚到用户眼前，
/// 而不是永久压在底栏下面。
///
/// 悬浮底栏按设计浮在正文上方、内容从它后面穿过，外壳里不补；
/// push 出来的独立页面没有外壳底栏，按系统导航栏高度补。
double shellBottomBarInset(BuildContext context) {
  final app = context.watch<AppController>();
  if (inRootShell(context) && app.settings.floatingNavBar) return 0;
  return bottomObstructionHeight(context);
}

/// 悬浮底栏（胶囊浮在内容上方）时，列表末尾额外给胶囊留出的高度。
///
/// 只有"外壳 + 悬浮底栏"需要：普通底栏由 [shellBottomBarInset] 按底栏高度
/// 让位、独立页面按系统导航栏让位、大屏没有底栏，这几类都不该再叠这段留白
/// （否则「我的」等页面选项下方会多出一大截空白）。
double floatingNavTailInset(BuildContext context) {
  // 大屏（侧栏布局）没有底栏，不需要给胶囊留位
  if (isLargeLayout(context)) return 0;
  final app = context.watch<AppController>();
  if (!inRootShell(context) || !app.settings.floatingNavBar) return 0;
  return 96;
}

/// 大屏（横屏 / 平板）下的 MD3E 正文卡片：body area 用 surface 底色、
/// 四周 16dp 圆角，外圈留 8dp + 系统导航栏 inset；卡片外面（navigation area）
/// 由页面 Scaffold 的 surfaceContainer 底色负责。
///
/// 卡片顶边跟随顶栏一起收起（[hide] 是 0..1 的收起进度，[topBarHeight]
/// 含状态栏高度），和外壳里标签页的处理一致。
///
/// 小屏（手机竖屏 / 小尺寸窗口）没有卡片：正文区由页面自己用
/// [BodySideInset] 整体让开左右系统 inset，顶栏仍铺满整屏。
class Md3eBodyCard extends StatelessWidget {
  const Md3eBodyCard({
    super.key,
    this.topBarHeight = 0,
    this.hide,
    this.clipContent = false,
    required this.child,
  });

  /// 顶栏高度（含状态栏）：卡片顶边从这里开始，顶栏收起时一起上移。
  final double topBarHeight;

  /// 顶栏收起进度 0..1；不收起时传 null。
  final ValueListenable<double>? hide;

  /// 是否把内容裁进卡片圆角里：不透明内容（如 WebView）需要，
  /// 顶栏在内容里的页面不能开（否则顶栏会被裁掉）。
  final bool clipContent;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isLargeLayout(context)) return child;
    final listenable = hide;
    if (listenable == null) {
      return _build(context, 0);
    }
    return ValueListenableBuilder<double>(
      valueListenable: listenable,
      builder: (context, value, _) => _build(context, value.clamp(0.0, 1.0)),
    );
  }

  Widget _build(BuildContext context, double hidden) {
    final systemPadding = MediaQuery.paddingOf(context);
    final card = Positioned(
      // 左侧同样留 8dp + 系统 inset：横屏时挖孔可能在左边，不能贴边
      left: 8 + systemPadding.left,
      top: topBarHeight * (1 - hidden),
      right: 8 + systemPadding.right,
      bottom: 8 + systemPadding.bottom,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        // 与外壳里的标签页一致：跟随主题背景（OLED 纯黑时也是黑）
        child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
      ),
    );
    // 正文与卡片用同一组内边距，内容不会画到卡片外面
    final content = Positioned(
      left: 8 + systemPadding.left,
      top: 0,
      right: 8 + systemPadding.right,
      bottom: 8 + systemPadding.bottom,
      // 卡片已经按 left/right/bottom inset 让过位了，内容里不要再让一次：
      // AppBar / SafeArea / Scrollbar 都会读这些 padding，否则会二次留白。
      // 顶部保留：状态栏高度仍由页面自己的顶栏使用。
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: true,
        removeRight: true,
        removeBottom: true,
        child: clipContent
            ? ClipRRect(borderRadius: BorderRadius.circular(16), child: child)
            : child,
      ),
    );
    return Stack(children: [card, content]);
  }
}

/// 小屏（手机竖屏 / 小尺寸窗口）正文区的左右让位：把系统在屏幕左右两侧的
/// inset（挖孔 / 三键导航）交给正文区整体承担，页面里的控件不用再各自避让。
///
/// 与横屏大屏的 [Md3eBodyCard] 一致的是"整体让位"，不同的是小屏空间紧张：
/// 正文区直接铺满，不加 8dp 边距、也没有圆角，只把两侧的 inset 让出来。
class BodySideInset extends StatelessWidget {
  const BodySideInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    if (padding.left == 0 && padding.right == 0) return child;
    return ColoredBox(
      // 让位后露出的窄条用页面底色填上，避免透出底层的黑边
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: EdgeInsets.only(left: padding.left, right: padding.right),
        // 正文区已经让过位了，里面的控件不要再读这两个 inset（会二次留白）
        child: MediaQuery.removePadding(
          context: context,
          removeLeft: true,
          removeRight: true,
          child: child,
        ),
      ),
    );
  }
}

/// 标记：本页面外面已经有 MD3E 卡片（[Md3ePageFrame]），
/// 页面自己不要再铺底色，见 [transparentPageBackground]。
class Md3eFramedScope extends InheritedWidget {
  const Md3eFramedScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Md3eFramedScope>() != null;

  @override
  bool updateShouldNotify(Md3eFramedScope oldWidget) => false;
}

/// 大屏（横屏 / 平板）下把"独立打开的页面"（例如没进底栏的标签页）
/// 套成 MD3E 外壳：navigation area 用 surfaceContainer 底色，正文是
/// 圆角 surface 卡片；顶栏仍由页面自己画在卡片上方。
///
/// 小屏（手机竖屏 / 小尺寸窗口）没有卡片，正文区由被套的页面自己让位。
///
/// 独立打开的页面不在外壳里，没有外壳的 [ScrollTint] 提供滚动进度，
/// 顶栏就会一直是初始底色；这里补一层只负责进度的 [ScrollTint]，
/// 让顶栏的上滑变色和标签页里一致（收起底栏仍由页面自己的进度驱动）。
class Md3ePageFrame extends StatelessWidget {
  const Md3ePageFrame({
    super.key,
    this.topBarHeight = 0,
    this.hide,
    required this.child,
  });

  /// 页面顶栏高度（含状态栏），用于让卡片顶边跟着顶栏收起。
  final double topBarHeight;

  /// 顶栏收起进度 0..1；不收起时传 null。
  final ValueListenable<double>? hide;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isLargeLayout(context)) return ScrollTint(child: child);
    return Md3eFramedScope(
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        body: Md3eBodyCard(
          topBarHeight: topBarHeight,
          hide: hide,
          child: ScrollTint(child: child),
        ),
      ),
    );
  }
}

/// 页面 AppBar 左侧的「返回」按钮：位置、间距、水波纹区域都与原来的
/// IconButton 一致，只把按钮表面（Material，40dp 圆形）换成 tonal 底色。
/// 不传 [onPressed] 时按返回处理。
class AppBarBackButton extends StatelessWidget {
  const AppBarBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Center：AppBar 的 leading 会给 56dp 的紧约束，不居中就会被拉伸成
    // 整块 56dp 的底色（贴左边、圆底过大）；居中后按钮保持自身 48dp
    // 点击区，Material（含波纹）仍是 40dp。
    return Center(
      child: IconButton(
        onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
        style: IconButton.styleFrom(
          backgroundColor: scheme.secondaryContainer,
          foregroundColor: scheme.onSecondaryContainer,
        ),
        icon: const Icon(Icons.arrow_back),
      ),
    );
  }
}

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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.l10n.copiedToClipboard)));
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
    this.progress,
  });

  /// 顶栏完整高度（状态栏 + 工具栏 + bottom），用于计算滑出距离。
  final double height;

  /// 顶栏底色：和设置/关于页一样，只随滚动从 surface 过渡到
  /// surfaceContainer，不参与渐隐。页面里的 AppBar 用透明底。
  final Color background;

  /// 构建顶栏。位移与内容渐隐由本组件统一处理：标题、按钮、路径栏
  /// 1:1 跟随手指淡出，底色始终保持不透明。
  final WidgetBuilder builder;

  /// 收起进度来源；为空时用外壳的 [AppController.topBarHide]
  /// （底栏视图共用），独立页面传各自的进度，互不影响。
  final ValueListenable<double>? progress;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return ValueListenableBuilder<double>(
      // 顶栏用独立的收起进度（距离 = 顶栏自身高度，才能 1:1 跟手）
      valueListenable: progress ?? app.topBarHide,
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

/// 独立页面的顶栏脚手架（设置 / 高级 / 备份 / 关于 / 分享文件夹 / 登录页）：
/// 顶栏不占布局，上滑时内容 1:1 随手指渐隐并整体滑出，底色保持不透明
/// （手机布局只做 surface → surfaceContainer 过渡），与首页、网盘、传输、
/// 收藏、我的五个视图完全一致。
///
/// [slivers] 不需要自己留顶栏占位，本组件会在最前面插入等高的 spacer。
///
/// 新页面模板（可滚动内容 + 顶栏，复制后按需增删）：
///
/// ```dart
/// class FooPage extends StatelessWidget {
///   const FooPage({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     final l10n = context.l10n;
///     return TopBarOverlayScaffold(
///       // 顶栏：必须是透明底，底色由本组件统一绘制（含滚动过渡）
///       appBar: AppBar(
///         backgroundColor: Colors.transparent,
///         scrolledUnderElevation: 0,
///         leading: IconButton(
///           icon: const Icon(Icons.arrow_back),
///           onPressed: () => Navigator.of(context).pop(),
///         ),
///         title: Text(l10n.fooTitle),
///         actions: const [/* IconButton... */],
///       ),
///       // 内容：直接给 slivers，顶部不用自己留顶栏占位
///       slivers: [
///         SliverPadding(
///           padding: const EdgeInsets.all(16),
///           sliver: SliverList(
///             delegate: SliverChildListDelegate([
///               // ListTile / SegmentedList / Md3ListItem ...
///             ]),
///           ),
///         ),
///       ],
///     );
///   }
/// }
/// ```
///
/// 使用要点：
/// - 页面骨架就是本组件，不要再自己套 Scaffold；顶栏高度（含 AppBar.bottom）
///   由本组件按 `状态栏 + appBar.preferredSize.height` 自动计算；
/// - 需要底部操作栏（如多选栏）时传 [bottomNavigationBar]，需要自带滚动控制器
///   （如回到顶部按钮）时传 [controller]；
/// - 滚动驱动是自动的：内部 ScrollTint 监听滚动通知，滑动距离 = 顶栏高度时为
///   1:1 收起；效果与设置里的「顶栏收起」开关联动，关闭时顶栏固定不收起；
/// - 若内容滚动发生在原生侧（WebView、相机预览等拿不到 ScrollNotification），
///   本脚手架暂时接不了，需要用 [TopBarOverlay] 加 `progress` 自行驱动；
/// - 末尾会自动补一段等于系统导航栏高度的留白（[bottomSafeInset]），
///   页面内容自己用 SafeArea 让开导航栏时可关掉，避免多出一截滚动范围；
/// - 本组件用页面自己的收起进度，不会影响标签页共用的外壳进度。
class TopBarOverlayScaffold extends StatefulWidget {
  const TopBarOverlayScaffold({
    super.key,
    required this.appBar,
    required this.slivers,
    this.controller,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.bottomSafeInset = true,
  });

  /// 顶栏内容：请使用透明底色的 AppBar；高度（含 bottom）由本组件计算。
  final PreferredSizeWidget appBar;

  /// 页面内容 slivers。
  final List<Widget> slivers;

  final ScrollController? controller;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;

  /// 是否在 slivers 末尾补一段等于系统导航栏（手势区）高度的留白，
  /// 让最后一条内容能滚到导航栏上方。默认开；页面自己用 SafeArea
  /// 让开导航栏时（如登录页）关掉，否则会多出一截可滚动的空白。
  final bool bottomSafeInset;

  @override
  State<TopBarOverlayScaffold> createState() => _TopBarOverlayScaffoldState();
}

class _TopBarOverlayScaffoldState extends State<TopBarOverlayScaffold> {
  /// 页面自己的收起进度：不动外壳的 [AppController.topBarHide]，
  /// 否则返回标签页时会把它们的顶栏一起带走。
  final ValueNotifier<double> _hide = ValueNotifier<double>(0);

  @override
  void dispose() {
    _hide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final topInset =
        MediaQuery.paddingOf(context).top + widget.appBar.preferredSize.height;
    return ScrollTint(
      hideDistance: topInset,
      readBarsHidden: () => _hide.value,
      onBarsHidden: app.settings.hideTopBar
          ? (value) {
              _hide.value = value;
            }
          : null,
      child: Builder(
        builder: (context) => Scaffold(
          // 大屏外壳里的第一个路由：背景交给外壳的圆角卡片；
          // 其余大屏页面（横屏 / 平板的二级页）自己铺 navigation area 的
          // surfaceContainer 底色，正文再套一层圆角 surface 卡片
          backgroundColor:
              widget.backgroundColor ??
              (transparentPageBackground(context)
                  ? Colors.transparent
                  : isLargeLayout(context)
                  ? scheme.surfaceContainer
                  : null),
          resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
          body: Md3eBodyCard(
            topBarHeight: topInset,
            hide: _hide,
            child: Stack(
              children: [
                // 小屏：正文区整体让开左右挖孔 / 侧边导航栏；
                // 顶栏保持原样（铺满整屏，自己用 SafeArea 让位）
                BodySideInset(
                  child: CustomScrollView(
                    controller: widget.controller,
                    slivers: [
                      SliverToBoxAdapter(child: SizedBox(height: topInset)),
                      ...widget.slivers,
                      if (widget.bottomSafeInset)
                        const SliverToBoxAdapter(child: _BottomSystemInset()),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: TopBarOverlay(
                    height: topInset,
                    progress: _hide,
                    background: topBarBackgroundColor(context, scheme),
                    builder: (context) => widget.appBar,
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: widget.bottomNavigationBar,
        ),
      ),
    );
  }
}

/// 滚动内容末尾的系统导航栏（手势区）占位。
///
/// 只在 Scaffold 的 body 里构建：页面自带 [Scaffold.bottomNavigationBar] 时
/// 系统已经把它算进布局，Scaffold 会把 body 的底部 padding 清成 0，
/// 这里就自然不补；没有底栏的页面则按导航栏高度补足。
/// 本组件用于 [TopBarOverlayScaffold]：大屏下它自己就套了 [Md3eBodyCard]，
/// 由卡片统一让位，这里返回 0。
class _BottomSystemInset extends StatelessWidget {
  const _BottomSystemInset();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: isLargeLayout(context) ? 0 : MediaQuery.paddingOf(context).bottom,
  );
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
                // 用 QrPainter + CustomPaint 而不是 QrImageView：后者内部是
                // LayoutBuilder，放进 AlertDialog（用 IntrinsicWidth 量内容）会在
                // debug 下抛 "LayoutBuilder does not support returning intrinsic
                // dimensions"，弹窗只剩遮罩；CustomPaint 没有这个问题。
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: CustomPaint(
                    painter: QrPainter(data: url, version: QrVersions.auto),
                  ),
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
  final size = MediaQuery.sizeOf(context);
  final maxHeight = size.height * maxHeightRatio;
  // MD3 给模态底部弹窗 640dp 宽度上限：窗口更宽时弹窗居中、离屏幕两侧
  // 还有很远，这时不需要左右让位；只有弹窗真的通铺整屏（窗口不超过上限）
  // 时才要避开两侧的挖孔 / 导航栏。
  final fullWidthSheet = size.width <= kModalSheetMaxWidth;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // 通铺整屏时让「弹窗窗体」整体避开左右挖孔：useSafeArea 作用在弹窗
    // 面板外侧（路由层），弹窗被收窄，而不是面板照旧压住挖孔、只让内容
    // 缩进一截（那样有挖孔的一侧会多出留白）。
    useSafeArea: fullWidthSheet,
    // 面板内部只再让开底部导航栏；内容里若还有 SafeArea（不少弹窗内容
    // 自带）读不到 padding，不会再二次避让多留一截空白。
    // 左右由上面 useSafeArea 统一处理，这里不要默认值（默认 left/right 为 true）。
    builder: (_) => SafeArea(
      top: false,
      left: false,
      right: false,
      child: Builder(
        builder: (context) => MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeLeft: true,
          removeRight: true,
          removeBottom: true,
          child: MeasuredSheet(maxHeight: maxHeight, child: child),
        ),
      ),
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
    _settleTween = Tween<double>(
      begin: _pull,
      end: 0,
    ).animate(CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic));
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
    final shouldClose =
        velocity > 700 || (velocity > -700 && pull > _expandedHeight * 0.35);
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
                child: SizedBox(key: _contentKey, child: widget.child),
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
///
/// 动画与网盘列表同款：
/// - 挂载时淡入 + 轻微上移（[index] 控制错峰，只取前 8 项）；
/// - [removing] 置 true 时淡出并收起高度，播完再由外部真正删除；
/// - [pulse] 递增时做一次高亮闪烁（修改信息 / 密码后）。
class Md3ListItem extends StatefulWidget {
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
    this.index = 0,
    this.animateIn = true,
    this.removing = false,
    this.pulse = 0,
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

  /// 出现动画的错峰下标（列表里传当前下标即可）。
  final int index;

  /// 是否播放挂载时的淡入动画。
  final bool animateIn;

  /// 删除前置 true：淡出 + 收起高度，动画结束后外部再真正移除。
  final bool removing;

  /// 修改后 +1：触发一次高亮闪烁。
  final int pulse;

  @override
  State<Md3ListItem> createState() => _Md3ListItemState();
}

class _Md3ListItemState extends State<Md3ListItem>
    with TickerProviderStateMixin {
  static const _enterDuration = Duration(milliseconds: 260);
  static const _removeDuration = Duration(milliseconds: 200);
  static const _pulseDuration = Duration(milliseconds: 700);

  /// 与网盘列表一致的错峰步长（毫秒）。
  static const _enterStep = 26;

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: _enterDuration,
  );
  late final AnimationController _remove = AnimationController(
    vsync: this,
    duration: _removeDuration,
    value: widget.removing ? 1 : 0,
  );
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: _pulseDuration,
    // 1 表示这次高亮已经播完（透明度为 0）
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.animateIn) {
      _enter.value = 1;
    } else {
      final delay = widget.index.clamp(0, 8) * _enterStep;
      if (delay == 0) {
        _enter.forward();
      } else {
        Future<void>.delayed(Duration(milliseconds: delay), () {
          if (mounted) _enter.forward();
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant Md3ListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.removing != oldWidget.removing) {
      if (widget.removing) {
        _remove.forward();
      } else {
        _remove.reverse();
      }
    }
    if (widget.pulse > oldWidget.pulse) {
      _pulseCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _remove.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: ColoredBox(
          color: widget.selected ? scheme.primaryContainer : Colors.transparent,
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
                        color: widget.selected
                            ? scheme.surface
                            : widget.iconBoxColor ?? scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        widget.selected ? Icons.check_circle : widget.icon,
                        size: 22,
                        color: widget.selected
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
                            widget.title,
                            maxLines: widget.titleMaxLines,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge,
                          ),
                          if (widget.subtitle.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                widget.subtitle,
                                maxLines: widget.subtitleMaxLines,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: 4),
                      widget.trailing!,
                    ],
                  ],
                ),
                if (widget.bottom != null) ...[
                  const SizedBox(height: 10),
                  widget.bottom!,
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_enter, _remove, _pulseCtrl]),
      builder: (context, child) {
        final enterT = Curves.easeOutCubic.transform(_enter.value);
        final removeT = Curves.easeInCubic.transform(_remove.value);
        final pulseT = _pulseCtrl.value;
        // 多列（网格）时不收起高度：行高由同行其它条目决定，硬收会让卡片
        // 被压扁得很奇怪；与网盘网格一致，只做淡出 + 轻微缩小。
        final collapse = adaptiveColumns(context) <= 1;
        var result = child!;
        // 修改后的高亮闪烁（与网盘列表一致：主色 16% → 0）
        if (pulseT > 0 && pulseT < 1) {
          result = Stack(
            children: [
              result,
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: scheme.primary.withValues(
                      alpha: 0.16 * (1 - pulseT),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        result = Opacity(
          opacity: (enterT * (1 - removeT)).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 1 - 0.06 * removeT,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - enterT)),
              child: result,
            ),
          ),
        );
        // 删除时收起高度，让后面的条目平滑补位
        if (removeT > 0 && collapse) {
          result = Align(
            heightFactor: (1 - removeT).clamp(0.0, 1.0),
            alignment: Alignment.topCenter,
            child: result,
          );
        }
        return result;
      },
      child: item,
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
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
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

  /// 悬浮底栏槽位里的上留白：胶囊本身 80dp 高，槽位另有 16dp 顶留白，
  /// 多选条按整槽避让就会比贴着胶囊多出一截空白。
  static const double _floatingNavTopGap = 16;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 外壳开了 extendBody 后，底栏槽位高度会写进正文的 padding.bottom：
    // 普通底栏 = 80 + 系统手势区，悬浮底栏 = 108 + 系统手势区（含 16dp 顶留白）。
    // 按整槽避让时悬浮样式的多选条会离胶囊多出 16dp，这里回退成胶囊实际高度，
    // 两种样式的间距保持一致（都是 12dp）。
    final app = context.watch<AppController>();
    final floatingNavInShell =
        inRootShell(context) && app.settings.floatingNavBar;
    final bottomInset = math.max(
      0.0,
      MediaQuery.paddingOf(context).bottom -
          (floatingNavInShell ? _floatingNavTopGap : 0.0),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 12 + bottomInset),
      child: Material(
        // 与列表卡片区分：用最浅的容器色，不加阴影
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [for (final child in children) Expanded(child: child)],
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.outline,
                            ),
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

/// 行优先把 [children] 铺成自适应多列（列数见 [adaptiveColumns]）：
/// 行内等宽、顶部对齐，行间距 / 列间距为 [spacing]；单列时不额外包装，保持原样。
class AdaptiveListRows extends StatelessWidget {
  const AdaptiveListRows({super.key, required this.children, this.spacing = 8});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final columns = adaptiveColumns(context);
    if (columns <= 1 || children.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += columns) {
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: spacing,
          children: [
            for (var i = 0; i < columns; i++)
              Expanded(
                // 把条目的 key 提到格子这一层：数据增删时按 key 匹配元素，
                // 动画状态跟着条目走，而不是被同位置的下一条目复用
                key: start + i < children.length
                    ? children[start + i].key
                    : null,
                child: start + i < children.length
                    ? children[start + i]
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// [AdaptiveListRows] 的 sliver 版本：按行懒构建，只构建可见行。
class AdaptiveSliverRows extends StatelessWidget {
  const AdaptiveSliverRows({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.spacing = 8,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final columns = adaptiveColumns(context);
    if (columns <= 1) {
      return SliverList.builder(itemCount: itemCount, itemBuilder: itemBuilder);
    }
    final rowCount = (itemCount + columns - 1) ~/ columns;
    return SliverList.builder(
      itemCount: rowCount,
      itemBuilder: (context, row) => Padding(
        padding: EdgeInsets.only(bottom: row == rowCount - 1 ? 0 : spacing),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: spacing,
          children: [
            for (var i = 0; i < columns; i++)
              Expanded(
                child: row * columns + i < itemCount
                    ? itemBuilder(context, row * columns + i)
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
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
    this.adaptive = false,
    this.adaptiveSpacing = 8,
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

  /// 大窗口（≥600dp）时按 [adaptiveColumns] 把条目铺成 2–3 列，
  /// 每个条目独立成卡（组外侧圆角）；单列时保持原来的连接式整组样式。
  final bool adaptive;

  /// 多列时的行 / 列间距。
  final double adaptiveSpacing;

  @override
  State<SegmentedList> createState() => _SegmentedListState();
}

class _SegmentedListState extends State<SegmentedList> {
  int? _pressedIndex;

  void _setPressed(int? index) {
    if (_pressedIndex != index && mounted) {
      setState(() => _pressedIndex = index);
    }
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

  /// 独立成卡（多列）时的圆角：四周都是外侧圆角，按下时才整体放大到
  /// [SegmentedList.pressedRadius]。这里不能复用 [_radiusFor]：多列下每个条目
  /// 自成一组，但下标仍是列表里的真实下标，用整组的 index/count 去算会把
  /// 除第一个以外的条目当成“组内中间项”而给出内圆角。
  BorderRadius _standaloneRadius(int index) => BorderRadius.circular(
    _pressedIndex == index ? widget.pressedRadius : widget.outerRadius,
  );

  Widget _item(
    BuildContext context,
    ColorScheme scheme,
    int index,
    int count, {
    bool standalone = false,
  }) {
    return AnimatedContainer(
      // 把条目的 key 提到外层：单列时 Column 直接按 key 匹配，
      // 避免数据增删后元素（以及出现动画状态）被同位置的下一条目复用
      key: widget.children[index].key,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: widget.color ?? scheme.surfaceContainerLow,
        borderRadius: standalone
            ? _standaloneRadius(index)
            : _radiusFor(index, count),
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
    if (widget.adaptive && adaptiveColumns(context) > 1) {
      // 多列：每个条目独立成卡（四周都是外侧圆角，按下时整体放大），
      // 行优先铺开；条目自带的底色已经负责区分，不需要再套分组容器。
      return Padding(
        padding: widget.margin,
        child: AdaptiveListRows(
          spacing: widget.adaptiveSpacing,
          children: [
            for (var i = 0; i < count; i++)
              _item(context, scheme, i, 1, standalone: true),
          ],
        ),
      );
    }
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
    if (_pressedIndex != index && mounted) {
      setState(() => _pressedIndex = index);
    }
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
                Navigator.of(dialogContext)
                    .pop((enabled: isEnabled, pwd: isEnabled ? value : ''));
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
    messenger.showSnackBar(SnackBar(content: Text(l10n.addedToQueue)));
    return true;
  } on NeedPasswordException {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(l10n.shareNeedsPassword)));
    return false;
  } on LanzouException catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  } catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(l10n.resolveFailed('$e'))));
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
