import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';

/// 应用只需要认这一个入口：把用到的 MD3E 组件从 m3e_core 透出来。
export 'package:m3e_core/m3e_core.dart'
    show
        M3EBottomSheet,
        M3EBottomSheetStyle,
        M3EBottomSheetTheme,
        M3EButtonGroupDensity,
        M3EButtonGroupOverflow,
        M3EButtonGroupType,
        M3EButtonShape,
        M3EButtonSize,
        M3EButtonStyle,
        M3EContainedLoadingIndicator,
        M3ECircularProgressIndicator,
        M3ECircularWavyProgressIndicator,
        M3ELinearProgressIndicator,
        M3ELinearWavyProgressIndicator,
        M3ELoadingIndicator,
        M3EMotion,
        M3EPullToRefreshController,
        M3EPullToRefreshIndicator,
        M3EPullToRefreshStyle,
        M3EToggleButton,
        M3EToggleButtonDecoration,
        M3EToggleButtonGroup,
        M3EToggleButtonGroupAction,
        M3ETypography,
        Shapes,
        showM3EModalBottomSheet;

/// ────────────────────────────── M3E 排版 ──────────────────────────────

/// 依据 M3E 规范计算「强调排版」：字号 / 行高与基线一致，只加粗字重。
///
/// 强调排版不是用来整体替换基线排版的——它标记的是**例外**：选中项、
/// 主要操作、标题这类需要拉出层级的地方（见 M3E 排版指南）。
///
/// **参考 M3E 规范**：emphasis 后的字重（display/headline/titleLarge/body 为
/// w500，titleMedium/titleSmall/label 为 w700）与可变字体 `wght` 轴取自
/// `M3ETypography.emphasized`。
/// **本应用的设计决定（非 M3 规范）**：字号、行高、字距、字体仍用应用主题
/// 里那一份——它已经带上了中文（dense 脚本）的几何与 Windows 字体兜底，
/// 整体替换会让中文排版尺寸/基线跟着 M3E 的拉丁数值走。
///
/// 传入的 [base] 必须来自 `Theme.of(context).textTheme`（已合并脚本几何），
/// 而不是 `ThemeData.textTheme`（可能只有字体、没有字号）。
TextTheme m3eEmphasizedTextTheme(
  TextTheme base, {
  double rond = 0,
  double? bodyRond,
}) {
  final canon = M3ETypography.emphasized(base, rond: rond, bodyRond: bodyRond);
  TextStyle? weigh(TextStyle? b, TextStyle? c) =>
      b?.copyWith(fontWeight: c?.fontWeight, fontVariations: c?.fontVariations);
  return TextTheme(
    displayLarge: weigh(base.displayLarge, canon.displayLarge),
    displayMedium: weigh(base.displayMedium, canon.displayMedium),
    displaySmall: weigh(base.displaySmall, canon.displaySmall),
    headlineLarge: weigh(base.headlineLarge, canon.headlineLarge),
    headlineMedium: weigh(base.headlineMedium, canon.headlineMedium),
    headlineSmall: weigh(base.headlineSmall, canon.headlineSmall),
    titleLarge: weigh(base.titleLarge, canon.titleLarge),
    titleMedium: weigh(base.titleMedium, canon.titleMedium),
    titleSmall: weigh(base.titleSmall, canon.titleSmall),
    bodyLarge: weigh(base.bodyLarge, canon.bodyLarge),
    bodyMedium: weigh(base.bodyMedium, canon.bodyMedium),
    bodySmall: weigh(base.bodySmall, canon.bodySmall),
    labelLarge: weigh(base.labelLarge, canon.labelLarge),
    labelMedium: weigh(base.labelMedium, canon.labelMedium),
    labelSmall: weigh(base.labelSmall, canon.labelSmall),
  );
}

/// 取 M3E 强调排版：`context.m3eEmphasizedTheme.titleLarge`。
///
/// （不用 `emphasizedTextTheme` 这个名字：m3e_core 自带的同扩展成员会撞名。）
extension M3eThemeX on BuildContext {
  /// 当前主题的强调排版（基于已合并脚本几何的基线排版派生）。
  TextTheme get m3eEmphasizedTheme =>
      m3eEmphasizedTextTheme(Theme.of(this).textTheme);
}

/// 把强调排版落到**组件级**样式上：顶栏标题、弹窗标题、主要按钮、
/// 导航栏 / 导航轨的选中项。
///
/// 这些主题字段必须是完整 TextStyle，而字号要等 `Theme.of` 合并脚本几何之后
/// 才有，所以只能在拿到 context 之后再套一层 [Theme]（见 app.dart 的
/// MaterialApp.builder）。没被点名的角色（正文、次要按钮、未选中项……）继续
/// 用基线排版——M3E 强调排版是标记例外，不是整份替换。
class M3eComponentStyles extends StatelessWidget {
  const M3eComponentStyles({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme;
    final emph = context.m3eEmphasizedTheme;
    return Theme(
      data: theme.copyWith(
        // 顶栏标题 → title（M3 文档角色分配）；标题 / 头条属于强调排版主场。
        appBarTheme: theme.appBarTheme.copyWith(
          titleTextStyle: emph.titleLarge,
        ),
        // 弹窗标题 → headline。
        dialogTheme: theme.dialogTheme.copyWith(
          titleTextStyle: emph.headlineSmall,
        ),
        // 主要操作按钮 → label large 的强调版本（次要按钮保持基线）。
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            textStyle: WidgetStatePropertyAll<TextStyle?>(emph.labelLarge),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            textStyle: WidgetStatePropertyAll<TextStyle?>(emph.labelLarge),
          ),
        ),
        // 导航栏：只有选中项用强调排版（选中状态是 M3E 点名的用法）。
        navigationBarTheme: theme.navigationBarTheme.copyWith(
          labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
            (states) => states.contains(WidgetState.selected)
                ? emph.labelMedium
                : base.labelMedium,
          ),
        ),
        navigationRailTheme: theme.navigationRailTheme.copyWith(
          selectedLabelTextStyle: emph.labelMedium,
          unselectedLabelTextStyle: base.labelMedium,
        ),
      ),
      child: child,
    );
  }
}

/// ────────────────────────────── 进度 / 加载指示器 ──────────────────────────────
///
/// M3 的等待时间规则：< 200ms 不显示指示器；200ms–5s 用 Loading indicator；
/// > 5s 用 Progress indicator（确定进度优先）。

/// MD3E Loading indicator：形状形变的循环动画，替代绝大多数
/// `CircularProgressIndicator`（不确定进度的中短等待）。
class M3eLoadingIndicator extends StatelessWidget {
  const M3eLoadingIndicator({
    super.key,
    this.size = 48,
    this.color,
    this.semanticsLabel,
    this.semanticsValue,
    this.shapes,
  });

  /// 边长（M3 允许 24–240dp，默认 48dp）。
  final double size;
  final Color? color;
  final String? semanticsLabel;
  final String? semanticsValue;

  /// 自定义形变序列（至少两个形状）；默认用 M3E 自带的七个形状。
  final List<Shapes>? shapes;

  @override
  Widget build(BuildContext context) => M3ELoadingIndicator(
    color: color,
    shapes: shapes,
    constraints: BoxConstraints.tightFor(width: size, height: size),
    semanticsLabel: semanticsLabel,
    semanticsValue: semanticsValue,
  );
}

/// 带容器的 MD3E Loading indicator：浮在内容之上时用，容器提供额外对比。
class M3eContainedLoadingIndicator extends StatelessWidget {
  const M3eContainedLoadingIndicator({
    super.key,
    this.size = 48,
    this.padding = const EdgeInsets.all(8),
    this.containerColor,
    this.indicatorColor,
    this.semanticsLabel,
    this.shapes,
  });

  /// 指示器本体边长（不含外层 [padding]）。
  final double size;
  final EdgeInsetsGeometry padding;
  final Color? containerColor;
  final Color? indicatorColor;
  final String? semanticsLabel;
  final List<Shapes>? shapes;

  @override
  Widget build(BuildContext context) => M3EContainedLoadingIndicator(
    padding: padding,
    containerColor: containerColor,
    indicatorColor: indicatorColor,
    semanticsLabel: semanticsLabel,
    shapes: shapes,
    width: size + padding.horizontal,
    height: size + padding.vertical,
  );
}

/// MD3E 线性进度条。[wavy] 为真时使用波浪形态——适合「时间长、想少一点
/// 静态感」的过程（例如文件传输），否则用标准平直形态。
class M3eLinearProgressIndicator extends StatelessWidget {
  const M3eLinearProgressIndicator({
    super.key,
    this.value,
    this.width = double.infinity,
    this.height,
    this.color,
    this.backgroundColor,
    this.wavy = false,
  });

  /// 0.0–1.0 的确定进度；为空表示不确定进度。
  final double? value;
  final double width;
  final double? height;
  final Color? color;
  final Color? backgroundColor;
  final bool wavy;

  @override
  Widget build(BuildContext context) {
    if (!wavy) {
      return M3ELinearProgressIndicator(
        value: value,
        width: width,
        minHeight: height ?? 4,
        color: color,
        backgroundColor: backgroundColor,
      );
    }
    return M3ELinearWavyProgressIndicator(
      value: value,
      width: width,
      // m3e_core 的默认容器高度：10dp（波浪会抬高整体高度）。
      height: height ?? 10,
      color: color,
      backgroundColor: backgroundColor,
    );
  }
}

/// MD3E 环形进度条（确定进度；不确定进度请用 [M3eLoadingIndicator]）。
class M3eCircularProgressIndicator extends StatelessWidget {
  const M3eCircularProgressIndicator({
    super.key,
    this.value,
    this.size = 48,
    this.strokeWidth = 4,
    this.color,
    this.backgroundColor,
  });

  final double? value;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) => M3ECircularProgressIndicator(
    value: value,
    size: size,
    strokeWidth: strokeWidth,
    color: color,
    backgroundColor: backgroundColor,
  );
}

/// MD3E 下拉刷新：拖拽跟手、触发阈值、回弹与形状形变都由 m3e_core 内部处理。
///
/// 相比 m3e_core 原版补两件事：
/// - [enabled]：原版没有开关，这里用 `notificationPredicate` 实现「不响应下拉」；
/// - 语义文案用传入的本地化字符串（原版把 `semanticsLabel` 硬编码成英文）。
///
/// 手感参数按网盘页调过（m3e 默认 80 / 0.55 要手指走约 180dp 才触发，偏费力；
/// 现在 60 / 0.75 约 100dp）。`dragResistance` 越大越「轻」，说明见字段注释。
class M3ePullToRefresh extends StatelessWidget {
  const M3ePullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.controller,
    this.enabled = true,
    this.edgeOffset = 0,
    this.semanticsLabel,
    this.triggerDistance = 60,
    this.dragResistance = 0.75,
    this.maxDragMultiplier,
  });

  /// 刷新回调；Future 完成前指示器一直转。
  final Future<void> Function() onRefresh;

  /// 通常是 `CustomScrollView` / `ListView`。
  final Widget child;

  /// 可选控制器：物理层要靠它读「小球收没收完」
  /// （见 `PullToRefreshScrollPhysics.holdsPull`）。
  final M3EPullToRefreshController? controller;

  /// 为 false 时不响应下拉（页面自己正在加载时用，避免两个指示器同时出现）。
  final bool enabled;

  /// 顶部浮层（顶栏 / 路径栏）高度：指示器从它下缘开始出现。
  final double edgeOffset;

  /// 读屏名称，一般是 `MaterialLocalizations.refreshIndicatorSemanticLabel`。
  final String? semanticsLabel;

  /// 触发刷新所需的「内部拖拽距离」（dp）：手指实际要走
  /// `triggerDistance / dragResistance`。
  final double triggerDistance;

  /// 拖拽阻尼（0–1）：越小越沉、越大越轻（m3e 默认 0.55）。
  final double dragResistance;

  /// 最大拖拽距离 = triggerDistance × 该倍数，为空时用 m3e 默认的 1.8。
  final double? maxDragMultiplier;

  @override
  Widget build(BuildContext context) => M3EPullToRefreshIndicator(
    onRefresh: onRefresh,
    controller: controller,
    edgeOffset: edgeOffset,
    triggerDistance: triggerDistance,
    dragResistance: dragResistance,
    maxDragMultiplier: maxDragMultiplier,
    notificationPredicate: (notification) =>
        enabled && defaultScrollNotificationPredicate(notification),
    // 默认实现把语义文案写死成英文，这里换成调用方给的本地化文案。
    indicatorBuilder: (context, progress, isRefreshing) =>
        M3EContainedLoadingIndicator(
          // 跟手阶段给确定进度（弧长跟着手指长），松手后转形变循环。
          progress: isRefreshing ? null : progress.clamp(0.0, 1.0),
          semanticsLabel: semanticsLabel,
        ),
    // m3e 组件只认「overscroll < 0」的下拉与「scrollDelta > 0」的列表滚动，
    // 回拉产生的正 overscroll 它直接忽略。这里把回拉这段被夹住的位移翻译成
    // 它认识的 ScrollUpdateNotification：小球先收回去，列表原地不动
    // （对应的位移物理层已经吃掉了，见 PullToRefreshScrollPhysics）。
    child: Builder(
      builder: (notificationContext) =>
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is OverscrollNotification &&
                  notification.overscroll > 0) {
                ScrollUpdateNotification(
                  metrics: notification.metrics,
                  context: notificationContext,
                  scrollDelta: notification.overscroll,
                  dragDetails: notification.dragDetails,
                ).dispatch(notificationContext);
              }
              return false;
            },
            child: child,
          ),
    ),
  );
}

/// ────────────────────────────── 按钮组 ──────────────────────────────

/// MD3E 连接式切换按钮组（Connected button group）：
/// 把 [M3EToggleButtonGroup] 的索引选择映射回业务值。
///
/// 按钮是否带图标由调用方决定（[iconOf] 传空即纯文字），沿用原来的图标设置。
///
/// 用 `filled` 配色：未选中是 surface container 底、选中是 primary 底
/// （on primary 文字），M3 按钮组规范里 filled 的切换配色就是这个映射。
class M3eConnectedButtonGroup<T> extends StatelessWidget {
  const M3eConnectedButtonGroup({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
    required this.labelOf,
    this.iconOf,
    this.size = M3EButtonSize.sm,
    this.expand = true,
    this.semanticLabel,
  });

  /// 每个按钮对应的业务值，顺序即显示顺序。
  final List<T> values;

  /// 当前选中的业务值（必须在 [values] 里）。
  final T selected;

  /// 选中项变化时回调；重复点已选中项不会触发。
  final ValueChanged<T> onSelected;

  /// 按钮文字。
  final Widget Function(T value) labelOf;

  /// 按钮图标；为 null 时是纯文字按钮（与原实现保持一致）。
  final Widget Function(T value)? iconOf;

  /// 尺寸（sm=40dp、md=56dp）。默认 sm。
  final M3EButtonSize size;

  /// 是否让按钮等分整行宽度（整行切换条、弹窗里的一行选项）。
  final bool expand;

  /// 整组的读屏名称。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = values.indexOf(selected);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 连接式按钮组在相邻按钮之间固定留 2dp 间隙（m3e_core 的
        // ButtonGroupTokens.kConnectedGap），等分时要把它一起减掉，
        // 否则整行会超出可用宽度。
        final count = values.length;
        final width = expand && constraints.maxWidth.isFinite && count > 0
            ? (constraints.maxWidth - 2.0 * (count - 1)) / count
            : null;
        return M3EToggleButtonGroup(
          type: M3EButtonGroupType.connected,
          shape: M3EButtonShape.round,
          size: size,
          style: M3EButtonStyle.filled,
          overflow: M3EButtonGroupOverflow.none,
          semanticLabel: semanticLabel,
          selectedIndex: selectedIndex < 0 ? null : selectedIndex,
          onSelectedIndexChanged: (index) {
            // 单选段不接受「再点一次取消选中」：忽略 null 即可保持原选中项。
            if (index == null) return;
            onSelected(values[index]);
          },
          actions: [
            for (final value in values)
              M3EToggleButtonGroupAction(
                icon: iconOf?.call(value),
                label: labelOf(value),
                width: width,
              ),
          ],
        );
      },
    );
  }
}
