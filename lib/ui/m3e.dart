import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:m3e_core/m3e_core.dart' as core;
import 'package:material_ui/material_ui.dart';

import 'reduce_motion.dart';

export 'm3e_pull_refresh.dart';

/// 应用只需要认这一个入口：把用到的 MD3E 组件透出来。
///
/// 组件（进度条 / 加载指示器 / 按钮组 / 底部弹窗 / 强调排版 / 下拉刷新）都来自
/// m3e_core；弹出菜单（`showM3eMenu`）是自己画的（见文件末尾的说明）。
///
/// 业务代码只认本文件导出的名字，不要直接 import m3e_core。注意 `export` 不会
/// 让名字在本文件里可见：本文件自己用到的 m3e_core 类型要写 `core.` 前缀。
export 'package:m3e_core/m3e_core.dart'
    show
        M3EButtonGroupDensity,
        M3EButtonGroupOverflow,
        M3EButtonGroupType,
        M3EBottomSheet,
        M3EBottomSheetStyle,
        M3EBottomSheetTheme,
        M3EButtonShape,
        M3EButtonSize,
        M3EButtonStyle,
        M3EClipper,
        M3EMotion,
        M3EToggleButton,
        M3EToggleButtonDecoration,
        M3EToggleButtonGroup,
        M3EToggleButtonGroupAction,
        M3ETypography,
        Shapes,
        showM3EModalBottomSheet;

/// ────────────────────────────── M3E 排版 ──────────────────────────────

/// MD3E 装饰形状外框里的图标：默认套 9 边「饼干」（Cookie9Sided）形状。
///
/// M3 形状库是给**纯视觉元素**用的（图像裁切、头像蒙版、装饰、加载指示器
/// 这类），空状态图标正属于这一类；形状本身不承载语义——M3 明确要求
/// 不把某个形状固定解释成某种含义，所以这里只当装饰外框。
///
/// **参考 M3 规范**：形状取自 M3 形状库的 `Cookie9Sided`；容器色用次级
/// 容器角色（装饰、不抢注意力），图标用配对的 on 角色。
/// **本应用的设计决定（非 M3 规范）**：默认 72dp 外框 / 36dp 图标。
class M3eShapedIcon extends StatelessWidget {
  const M3eShapedIcon({
    super.key,
    required this.icon,
    this.size = 72,
    this.iconSize = 36,
    this.shape = core.Shapes.c9SidedCookie,
    this.color,
    this.iconColor,
  });

  final IconData icon;

  /// 外框的边长（形状按正方形排版）。
  final double size;
  final double iconSize;

  /// M3 形状库里的形状。
  final core.Shapes shape;

  /// 外框底色；默认次级容器色。
  final Color? color;

  /// 图标颜色；默认与底色配对的 on 角色。
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipPath(
      clipper: core.M3EClipper(shape),
      child: Container(
        width: size,
        height: size,
        color: color ?? scheme.secondaryContainer,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: iconSize,
          color: iconColor ?? scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

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
  final canon = core.M3ETypography.emphasized(
    base,
    rond: rond,
    bodyRond: bodyRond,
  );
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
          // M3 basic dialog：宽度 280–560。默认只卡了下限，横屏 / 桌面上长文本
          // 弹窗（用户协议等）会一路撑到接近全屏。
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
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
///
/// 系统要求少动效（含读屏接管）时，下面三个指示器统一退化成**静态**形态：
/// 还在转的环 / 走的条本身就是大面积重复运动，前庭敏感的用户会被它晃到；
/// 保留一个静止的进度图形，既不丢「正在处理」的提示，也不再有运动。
/// （确定进度本来就是静态的，不受影响。）
const double _kStaticProgressValue = 0.75;

/// MD3E Loading indicator：形状形变的循环动画，替代绝大多数
/// `CircularProgressIndicator`（不确定进度的中短等待）。
class M3eLoadingIndicator extends StatelessWidget {
  const M3eLoadingIndicator({
    super.key,
    this.size = 48,
    this.color,
    this.semanticsLabel,
    this.semanticsValue,
  });

  /// 边长（M3 允许 24–240dp，默认 48dp）。
  final double size;
  final Color? color;
  final String? semanticsLabel;
  final String? semanticsValue;

  @override
  Widget build(BuildContext context) {
    if (reduceMotionOf(context)) {
      final ring = core.M3ECircularProgressIndicator(
        value: _kStaticProgressValue,
        size: size,
        strokeWidth: size / 12,
        color: color,
      );
      if (semanticsLabel == null && semanticsValue == null) return ring;
      // M3ECircularProgressIndicator 本身没有语义参数，这里补一层
      return Semantics(
        label: semanticsLabel,
        value: semanticsValue,
        child: ring,
      );
    }
    return core.M3ELoadingIndicator(
      color: color,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      semanticsLabel: semanticsLabel,
      semanticsValue: semanticsValue,
    );
  }
}

// 注：原先的 M3eContainedLoadingIndicator 一直没人用（下拉刷新小球用的是
// m3e_core 自带的那个），迁移时直接删掉；需要时用 core 的
// M3EContainedLoadingIndicator 即可。

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

  /// 平直形态下是轨道粗细，波浪形态下是「容器高度」（波浪会抬高整体高度）。
  ///
  /// 留空时用 m3e_core 的默认值：平直 4dp、波浪容器 10dp。
  final double? height;

  final Color? color;
  final Color? backgroundColor;
  final bool wavy;

  @override
  Widget build(BuildContext context) {
    // 不确定进度在少动效下换成静止的 75% 进度
    final effectiveValue =
        value ?? (reduceMotionOf(context) ? _kStaticProgressValue : null);
    if (!wavy) {
      return core.M3ELinearProgressIndicator(
        value: effectiveValue,
        width: width,
        minHeight: height ?? 4,
        color: color,
        backgroundColor: backgroundColor,
      );
    }
    return core.M3ELinearWavyProgressIndicator(
      value: effectiveValue,
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
  Widget build(BuildContext context) => core.M3ECircularProgressIndicator(
    value: value ?? (reduceMotionOf(context) ? _kStaticProgressValue : null),
    size: size,
    strokeWidth: strokeWidth,
    color: color,
    backgroundColor: backgroundColor,
  );
}

/// ────────────────────────────── 按钮组 ──────────────────────────────

/// MD3E 连接式切换按钮组（Connected button group）：
/// 把 [M3EToggleButtonGroup] 的索引选择映射回业务值。
///
/// 按钮是否带图标由调用方决定（[iconOf] 传空即纯文字），沿用原来的图标设置。
///
/// 默认用 `tonal` 配色：这是应用里切换条的统一观感——比 `filled` 低调，
/// 不与页面里的主要操作抢焦点（要更强调时显式传 [M3EButtonStyle.filled]）。
class M3eConnectedButtonGroup<T> extends StatelessWidget {
  const M3eConnectedButtonGroup({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
    required this.labelOf,
    this.iconOf,
    this.size = core.M3EButtonSize.sm,
    this.expand = true,
    this.style = core.M3EButtonStyle.tonal,
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
  final core.M3EButtonSize size;

  /// 是否让按钮等分整行宽度（整行切换条、弹窗里的一行选项）。
  final bool expand;

  /// 按钮配色。
  final core.M3EButtonStyle style;

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
        return core.M3EToggleButtonGroup(
          type: core.M3EButtonGroupType.connected,
          shape: core.M3EButtonShape.round,
          size: size,
          style: style,
          overflow: core.M3EButtonGroupOverflow.none,
          semanticLabel: semanticLabel,
          selectedIndex: selectedIndex < 0 ? null : selectedIndex,
          onSelectedIndexChanged: (index) {
            // 单选段不接受「再点一次取消选中」：忽略 null 即可保持原选中项。
            if (index == null) return;
            onSelected(values[index]);
          },
          actions: [
            for (final value in values)
              core.M3EToggleButtonGroupAction(
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

/// ──────────────────── 标准（spaced）图标按钮组 ────────────────────

/// 标准图标按钮组的默认按钮间距。
const double kM3EIconButtonSpacing = 6;

/// 标准图标按钮组里单个按钮的宽度：按可用宽度均分，夹在 [minWidth] 与
/// [maxWidth] 之间。
///
/// 调用方要算按钮几何时（例如把弹出菜单对准被点的那一段）用同一个函数，
/// 保证和组件内部算出来的宽度一致。
double m3eIconButtonWidth(
  double available,
  int count, {
  double spacing = kM3EIconButtonSpacing,
  double minWidth = 48,
  double maxWidth = 80,
}) {
  assert(count > 0);
  return ((available - spacing * (count - 1)) / count)
      .clamp(minWidth, maxWidth)
      .toDouble();
}

/// [M3EIconButtonGroup] 里的一个纯图标按钮。
class M3EIconAction<T> {
  const M3EIconAction({
    required this.value,
    required this.icon,
    required this.checkedIcon,
    required this.tooltip,
    this.checked = false,
    this.isToggle = false,
    this.enabled = true,
    this.iconWidget,
    this.checkedIconWidget,
  });

  /// 业务值，点击时回传给组的回调。
  final T value;

  /// 未选中时的图标（通常用 outlined 线框版）。
  final IconData icon;

  /// 选中时的图标（通常用实心版）。
  final IconData checkedIcon;

  /// 图标按钮没有可见文字，tooltip 同时充当读屏名称。
  final String tooltip;

  /// 当前是否选中；只对开关型按钮有意义，由调用方持有。
  final bool checked;

  /// 是否开关型按钮：点一下切换选中态并走 [M3EIconButtonGroup.onToggled]；
  /// 否则是普通动作按钮，点一下走 [M3EIconButtonGroup.onPressed]。
  final bool isToggle;

  /// 是否可以点。选中态还没加载出来时（例如收藏态要等一次请求）先置灰，
  /// 免得状态未知时点出错误的结果。
  final bool enabled;

  /// 图标位的自定义控件（例如下载进度环）；给了就用它取代 [icon]。
  final Widget? iconWidget;

  /// 选中态图标位的自定义控件；给了就用它取代 [checkedIcon]。
  final Widget? checkedIconWidget;
}

/// MD3E 标准按钮组（standard / spaced）：一行纯图标按钮。
///
/// 与 [M3eConnectedButtonGroup]（连接式，用于单选切换）不同，标准组按 M3
/// 规范在按钮之间留间距、不改变相邻按钮宽度，可以混放动作按钮和开关按钮，
/// 适合「属性弹窗里一排常用操作」这种场景。
///
/// 宽度：每段按可用宽度均分，上限 [maxWidth]（默认 80dp）、下限 [minWidth]
/// （默认 48dp，M3 要求组里每个按钮都有 48dp 触控目标）。一行放不下时交给组
/// 自己横向滚动——按钮组不换行（M3）。
class M3EIconButtonGroup<T> extends StatelessWidget {
  const M3EIconButtonGroup({
    super.key,
    required this.items,
    this.onPressed,
    this.onToggled,
    this.size = core.M3EButtonSize.md,
    this.style = core.M3EButtonStyle.tonal,
    this.spacing = 6,
    this.maxWidth = 80,
    this.minWidth = 48,
    this.semanticLabel,
  });

  /// 从左到右的按钮项。
  final List<M3EIconAction<T>> items;

  /// 普通动作按钮的点击回调。
  final ValueChanged<T>? onPressed;

  /// 开关型按钮的切换回调，第二个参数是切换后的选中态。
  final void Function(T value, bool checked)? onToggled;

  /// 按钮尺寸：默认 md（56dp 高）。
  final core.M3EButtonSize size;

  /// 配色。M3 规定按钮组用 filled / tonal / outlined / elevated，
  /// 不要用 standard 图标按钮或文字按钮（它们没有容器）；默认 tonal。
  final core.M3EButtonStyle style;

  /// 按钮之间的间距。
  final double spacing;

  /// 单个按钮的最大宽度。
  final double maxWidth;

  /// 单个按钮的最小宽度（触控目标下限）。
  final double minWidth;

  /// 整组的读屏名称。
  final String? semanticLabel;

  Set<int> get _checkedIndices => <int>{
    for (int i = 0; i < items.length; i++)
      if (items[i].checked) i,
  };

  void _handleSelectionChanged(Set<int> next) {
    final current = _checkedIndices;
    for (int i = 0; i < items.length; i++) {
      if (next.contains(i) == current.contains(i)) continue;
      final item = items[i];
      // 置灰的按钮不回调（组内按钮自己也点不动，这里再挡一层）
      if (!item.enabled) return;
      if (item.isToggle) {
        onToggled?.call(item.value, next.contains(i));
      } else {
        // 动作按钮：组是受控的，这里不回写 selectedIndices，
        // 按钮点完仍然保持未选中（只是普通点击）。
        onPressed?.call(item.value);
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int count = items.length;
        if (count == 0) return const SizedBox.shrink();
        final double gap = spacing * (count - 1);
        final double available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : maxWidth * count + gap;
        final double width = m3eIconButtonWidth(
          available,
          count,
          spacing: spacing,
          minWidth: minWidth,
          maxWidth: maxWidth,
        );
        // 窄窗口一行放不下时不换行，交给组横向滚动
        final bool scroll = width * count + gap > available + 0.5;
        return core.M3EToggleButtonGroup(
          type: core.M3EButtonGroupType.standard,
          shape: core.M3EButtonShape.round,
          size: size,
          style: style,
          spacing: spacing,
          overflow: scroll
              ? core.M3EButtonGroupOverflow.scroll
              : core.M3EButtonGroupOverflow.none,
          semanticLabel: semanticLabel,
          selectedIndices: _checkedIndices,
          onSelectedIndicesChanged: _handleSelectionChanged,
          actions: [
            for (final item in items)
              core.M3EToggleButtonGroupAction(
                icon: item.iconWidget ?? Icon(item.icon),
                // Material Symbols 是可变字体：选中态默认切到 FILL=1 的实心版，
                // 否则「已收藏 / 已设密码」这类开关图标和未选中长得一模一样。
                checkedIcon:
                    item.checkedIconWidget ?? Icon(item.checkedIcon, fill: 1),
                tooltip: item.tooltip,
                semanticLabel: item.tooltip,
                width: width,
                enabled: item.enabled,
              ),
          ],
        );
      },
    );
  }
}

/// ──────────────────── 列表行尾的标准图标按钮 ────────────────────

/// MD3E 按钮的形状过渡：进度 0 → 1（静止形状 → 目标形状）。
///
/// 形状类动效属于 spatial：用 expressive fast spatial 弹簧（和 M3E 图标
/// 按钮的按下形变同一套）；系统要求少动效时直接跳到终值。
///
/// 按下形变、选中形变各拿一个实例：插值时先按 [value] 算出当前静止形状，
/// 再叠按下那层——M3E 规定圆、方按钮的按下形状是同一个。
class M3eShapeMorph {
  M3eShapeMorph({required TickerProvider vsync, bool morphed = false})
    : controller = AnimationController.unbounded(
        vsync: vsync,
        value: morphed ? 1 : 0,
      );

  /// 状态变化进度（[AnimatedBuilder] 监听它重画形状）。
  final AnimationController controller;

  /// 0 = 静止形状，1 = 目标形状。
  double get value => controller.value.clamp(0.0, 1.0);

  void setMorphed(BuildContext context, bool morphed) {
    final double target = morphed ? 1 : 0;
    if (reduceMotionOf(context)) {
      controller.value = target;
      return;
    }
    final motion = core.M3EMotion.expressiveSpatialFast;
    controller.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: motion.stiffness,
          ratio: motion.damping,
        ),
        controller.value,
        target,
        controller.velocity,
      ),
    );
  }

  void dispose() => controller.dispose();
}

/// 按 [t]（0..1）在圆角 [from] → [to] 之间插值。
double m3eLerpRadius(double from, double to, double t) =>
    from + (to - from) * t.clamp(0.0, 1.0);

/// MD3E 标准（standard）图标按钮：列表行尾的 ⋯ / ✕、分区标题的展开 ⌄
/// 这类低强调操作统一用它。
///
/// 参数（M3E 图标按钮规格）：
/// - 尺寸 Small（默认档）：40dp 容器 + 24dp 图标，触控目标 48dp
///   （M3E 要求 ≥48dp，嵌套在列表项里也一样，且不要用密度压缩）；
/// - 形态：静止 = 圆（CornerFull）；[selected] 为真时换成方形档 12dp
///   ——M3E 开关型图标按钮「未选中圆 → 选中方」；按下统一 8dp（S 档）；
/// - 配色 standard：图标用 on surface variant，容器静止时不可见，只有状态层
///   （悬停 8%、聚焦 / 按下 10%）；需要可见容器时传 [containerColor]。
///
/// 按下 / 选中都是形状动画，用 expressive fast spatial 弹簧；系统要求少动效
/// 时直接跳到终值。
class M3eIconButton extends StatefulWidget {
  const M3eIconButton({
    super.key,
    this.icon,
    this.iconBuilder,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
    this.containerColor,
  }) : assert(
         icon != null || iconBuilder != null,
         'icon 和 iconBuilder 至少给一个',
       );

  /// 默认图标；用 [iconBuilder] 自定义时可以不传。
  final IconData? icon;

  /// 自定义图标：拿到按钮算好的颜色（含禁用态透明度）。用于需要额外动画的
  /// 图标，例如展开 / 收起的 ⌄（转 90°）。
  final Widget Function(BuildContext context, Color color)? iconBuilder;

  /// 悬停 / 长按提示，同时充当读屏名称（描述动作，不是图标名）。
  final String tooltip;

  /// null = 禁用：图标 38% 透明度，不响应点击。
  final VoidCallback? onPressed;

  /// 开关型按钮的选中态：静止形状从圆变方（M3E toggle icon button）。
  final bool selected;

  /// 容器底色；null = standard 风格（静止时容器不可见，只有状态层）。
  final Color? containerColor;

  @override
  State<M3eIconButton> createState() => _M3eIconButtonState();
}

class _M3eIconButtonState extends State<M3eIconButton>
    with TickerProviderStateMixin {
  /// Small 尺寸：40dp 容器 / 24dp 图标；触控目标 ≥48dp。
  static const double _container = 40;
  static const double _icon = 24;
  static const double _target = 48;

  /// 静止：圆 = CornerFull（半径取容器一半）；选中：方形档 12dp；
  /// 按下：两种形状统一 8dp（M3E 图标按钮尺寸表，S 档）。
  static const double _circleRadius = _container / 2;
  static const double _squareRadius = 12;
  static const double _pressedRadius = 8;

  /// 按下形变（0 = 静止，1 = 按下）与选中形变（0 = 圆，1 = 方）。
  late final M3eShapeMorph _press = M3eShapeMorph(vsync: this);
  late final M3eShapeMorph _selection = M3eShapeMorph(
    vsync: this,
    morphed: widget.selected,
  );
  late final Listenable _repaint = Listenable.merge([
    _press.controller,
    _selection.controller,
  ]);

  @override
  void didUpdateWidget(covariant M3eIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      _selection.setMorphed(context, widget.selected);
    }
  }

  @override
  void dispose() {
    _press.dispose();
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    final iconColor = scheme.onSurfaceVariant.withValues(
      alpha: enabled ? 1 : 0.38,
    );
    final layer = scheme.onSurfaceVariant;
    return Semantics(
      label: widget.tooltip,
      button: true,
      enabled: enabled,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.tooltip,
        child: SizedBox.square(
          dimension: _target,
          child: Center(
            child: AnimatedBuilder(
              animation: _repaint,
              builder: (BuildContext context, _) {
                // 先算当前静止形状（圆 ↔ 方），再叠按下那层
                final double rest = m3eLerpRadius(
                  _circleRadius,
                  _squareRadius,
                  _selection.value,
                );
                final shape = RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    m3eLerpRadius(rest, _pressedRadius, _press.value),
                  ),
                );
                return Material(
                  color: widget.containerColor ?? Colors.transparent,
                  shape: shape,
                  clipBehavior: Clip.antiAlias,
                  child: InkResponse(
                    onTap: widget.onPressed,
                    onHighlightChanged: (pressed) =>
                        _press.setMorphed(context, pressed),
                    containedInkWell: true,
                    customBorder: shape,
                    hoverColor: layer.withValues(alpha: 0.08),
                    focusColor: layer.withValues(alpha: 0.1),
                    highlightColor: layer.withValues(alpha: 0.1),
                    splashColor: layer.withValues(alpha: 0.1),
                    child: SizedBox.square(
                      dimension: _container,
                      child: Center(
                        child:
                            widget.iconBuilder?.call(context, iconColor) ??
                            Icon(widget.icon!, size: _icon, color: iconColor),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// ────────────────────────────── 弹出菜单 ──────────────────────────────

/// [showM3eMenu] 里的一项：图标 + 文案 + 选中后返回的值。
class M3eMenuItem<T> {
  const M3eMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.iconFill = 0,
    this.enabled = true,
  });

  /// 选中这一项时 [showM3eMenu] 返回的值。
  final T value;

  /// 菜单文案。
  final String label;

  /// 行首图标。
  final IconData icon;

  /// 行首图标的 FILL 轴（0 = 描边、1 = 实心）。
  ///
  /// Material Symbols 只有一套字形，实心 / 描边靠这条可变字体轴切：例如
  /// 「已收藏」用实心星、「收藏」用描边星。不支持的图标字体上无效果。
  final double iconFill;

  /// 是否可用：置灰的项仍显示（M3 规范：不可用的操作置灰而不是删掉），
  /// 但点不动。
  final bool enabled;
}

/// 贴在被点控件下方弹出的 MD3E 菜单。
///
/// [anchor] 是被点控件的全局矩形：菜单贴它下方弹出（[items] 顺序即显示顺序），
/// 默认左缘对齐；[alignEnd] 为真时右缘对齐——贴右侧的 ⋯ 按钮用这个，菜单不会
/// 被屏幕右上角夹歪。上下空间不够时翻到锚点上方；左右夹在屏幕边缘内。选中返回
/// 那一项的 [M3eMenuItem.value]，点别处 / 按返回收起返回 null。
///
/// 观感跟主题走：容器 surfaceContainerLow、16dp 圆角、项高 48dp、图标 24dp，
/// 颜色由 ambient `ColorScheme` 推出，所以深浅色切换跟着变。
///
/// 实现说明：没有继续用 material_3_expressive 的 `M3EMenu`——它一旦要滚动，就会
/// 把所有项并成**一张卡片**塞进 `ListView`：卡片跟着内容一起滚，圆角和阴影被视口
/// 裁掉；滚动条也是包里硬编码的常显 `RawScrollbar`（和应用里的 FastScrollbar 不是
/// 一套）。这里自绘弹层：卡片固定，超出高度只让里面的项目滚动，滚动条沿用应用同款
/// （6dp 圆角滑块、无轨道、滚动时出现）。
Future<T?> showM3eMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required List<M3eMenuItem<T>> items,
  bool alignEnd = false,
  Listenable? closeOn,
  bool Function()? closeWhen,
}) {
  // 少动效在这里就定下来：路由的时长是 getter，拿不到 context
  final bool reduceMotion = reduceMotionOf(context);
  return Navigator.of(context, rootNavigator: true).push<T>(
    _M3eMenuRoute<T>(
      anchor: anchor,
      items: items,
      alignEnd: alignEnd,
      reduceMotion: reduceMotion,
      closeOn: closeOn,
      closeWhen: closeWhen,
    ),
  );
}

/// 菜单里的一行：图标 + 文案。
///
/// 公开是为了让测试能断言「菜单里有哪些行」；业务代码不需要直接用。
class M3eMenuRow extends StatelessWidget {
  const M3eMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconFill = 0,
    this.enabled = true,
  });

  /// 行首图标。
  final IconData icon;

  /// 行首图标的 FILL 轴（0 = 描边、1 = 实心），见 [M3eMenuItem.iconFill]。
  final double iconFill;

  /// 行文案。
  final String label;

  /// 点这一行。
  final VoidCallback onTap;

  /// 置灰的项仍显示但点不动（M3 规范）。[MenuItemButton] 传 null 回调
  /// 即渲染成禁用态，颜色由主题负责。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // 用框架的 MenuItemButton 拿到它的默认度量（48dp 高、左右内边距 12dp、
    // 图标 24dp、labelLarge）和桌面端的悬停 / 焦点 / 键盘行为；圆角按 M3E 的
    // vertical menu 规格改：项目是卡片里的一块圆角块，圆角 12dp——卡片圆角 16、
    // 项目左右内缩 4dp，内圆角 = 16 − 4 = 12，符合嵌套规则。
    return MenuItemButton(
      onPressed: enabled ? onTap : null,
      // 菜单里的项目是竖排文案：必须显式指定 vertical，MenuItemButton 才会把
      // 文案放进 Expanded（+ClipRect）里约束住；默认的 horizontal 是给 MenuBar
      // 用的，文案会拿到无约束宽度、直接溢出卡片（长文案就是被卡片裁掉）。
      // 约束住之后，超出菜单最大宽度（280）的长文案按规范走省略号。
      overflowAxis: Axis.vertical,
      style: MenuItemButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      leadingIcon: Icon(icon, size: 24, fill: iconFill),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// [showM3eMenu] 的弹层：固定卡片 + 内部滚动。
class _M3eMenuRoute<T> extends PopupRoute<T> {
  _M3eMenuRoute({
    required this.anchor,
    required this.items,
    required this.alignEnd,
    required this.reduceMotion,
    this.closeOn,
    this.closeWhen,
  });

  final Rect anchor;
  final List<M3eMenuItem<T>> items;
  final bool alignEnd;
  final bool reduceMotion;

  /// 外部状态变化时自动收起菜单：监听 [closeOn]（应当是低频的通知源，
  /// 例如 [TransferManager.marksRevision]；别监听每次进度更新都会通知的对象），
  /// 且 [closeWhen] 为真（默认恒真）时收起。收起走正常 pop，返回 null。
  final Listenable? closeOn;
  final bool Function()? closeWhen;

  void _handleCloseOn() {
    if (!isActive) return;
    if (closeWhen != null && !closeWhen!()) return;
    // 只有菜单还在最上层时才关它；否则请等它回到最上层（这种情况极少）
    if (isCurrent) navigator?.pop();
  }

  @override
  void install() {
    super.install();
    closeOn?.addListener(_handleCloseOn);
  }

  /// M3 菜单：宽度 112–280、项高 48、上下内边距 8、离屏幕边缘 12。
  static const double _minWidth = 112;
  static const double _maxWidth = 280;
  static const double _maxHeight = 320;
  static const double _rowHeight = 48;

  /// 卡片上下内边距：和项目间隔一致，首 / 末项到卡片的距离 = 项目之间的距离。
  static const double _verticalPadding = _itemGap;

  /// 项目之间的间隔：M3E vertical menu 里每一项是各自独立的圆角块。
  static const double _itemGap = 4;

  /// 项目相对卡片的左右内缩；同时决定项目自己的圆角（16 − 4 = 12dp）。
  static const double _itemInset = 4;

  static const double _screenPadding = 12;
  static const double _anchorGap = 4;
  static const double _radius = 16;

  final ScrollController _scroll = ScrollController();

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Popup menu';

  /// MD3 默认的菜单动效：展开 400ms、收起 150ms；少动效时直接跳过。
  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 400);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 150);

  /// 错开占展开进度的比例：第一项从 0 开始，最后一项从 [_staggerSpan] 开始，
  /// 全部在动画结束时到位。
  static const double _staggerSpan = 0.35;

  /// 项目沿轴线的入场位移（dp）：从锚点那一侧滑到自己的位置。
  static const double _itemSlide = 8;

  /// 单个项目在当前进度下的「出现程度」：0 = 还没出现，1 = 到位。
  ///
  /// 展开时按索引错开；收起（150ms）不叠错开——整块一起走更利落。
  double _itemProgress(Animation<double> animation, int index) {
    if (reduceMotion || items.length <= 1) return animation.value;
    if (animation.status == AnimationStatus.reverse) return animation.value;
    final double start = _staggerSpan * index / (items.length - 1);
    final double t = ((animation.value - start) / (1 - _staggerSpan)).clamp(
      0.0,
      1.0,
    );
    return Curves.easeOutCubic.transform(t);
  }

  /// 菜单宽度按内容算（M3：112–280dp），不跟锚点宽度绑定：
  /// 逐项量「左右内边距 + 图标 + 图标与文案的间距 + 文案宽度」，取最宽的一项。
  /// 文案样式与 [MenuItemButton] 的默认一致（labelLarge）；量出来的宽度超过
  /// 280dp / 屏幕可用宽度时由行内省略号截断（见 [M3eMenuRow]）。
  double _contentWidth(BuildContext context, Size screen) {
    final theme = Theme.of(context);
    final density = theme.visualDensity;
    // MenuItemButton（M3 默认）的左右内边距：max(8, 12 + 视觉密度)。
    // 字号放大时框架会把内边距收窄到 8，这里保守取基础值，只多不少。
    final double padding = math.max(8, 12 + density.baseSizeAdjustment.dx);
    // 图标与文案之间的间距：max(4, 12 + 密度)。
    final double gap = math.max(4, 12 + density.horizontal * 2);
    final TextStyle? labelStyle = theme.textTheme.labelLarge;
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final TextDirection direction = Directionality.of(context);
    var widest = 0.0;
    for (final M3eMenuItem<T> item in items) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: item.label, style: labelStyle),
        maxLines: 1,
        textDirection: direction,
        textScaler: textScaler,
      )..layout();
      final double row = padding * 2 + 24 + gap + painter.width;
      if (row > widest) widest = row;
    }
    return (widest + _itemInset * 2).clamp(
      _minWidth,
      math.min(_maxWidth, screen.width - _screenPadding * 2),
    );
  }

  @override
  void dispose() {
    closeOn?.removeListener(_handleCloseOn);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final MediaQueryData media = MediaQuery.of(context);
    final Size screen = media.size;
    final EdgeInsets viewPadding = media.padding;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final double topLimit = viewPadding.top + _screenPadding;
    final double bottomLimit =
        screen.height - viewPadding.bottom - _screenPadding;
    // 行高按平台的实际密度算：桌面端 ThemeData.visualDensity 默认 compact，
    // MenuItemButton 的 48dp 最小高度会被压到 40dp。这里只用来判断「该朝哪边
    // 开」；卡片高度本身交给内容决定（见下面的 ConstrainedBox + shrinkWrap）。
    final double rowHeight =
        _rowHeight + Theme.of(context).visualDensity.baseSizeAdjustment.dy;
    final double contentHeight =
        items.length * rowHeight +
        (items.length - 1) * _itemGap +
        _verticalPadding * 2;
    final double below = bottomLimit - (anchor.bottom + _anchorGap);
    final double above = (anchor.top - _anchorGap) - topLimit;
    // 先试锚点下方；放不下且上方更宽敞时才翻到上方，避免菜单贴屏幕边
    final bool opensAbove = below < contentHeight && above > below;
    final double available = opensAbove ? above : below;
    // 卡片最高只能到「可用空间」和 M3 上限，具体多高由内容决定：放得下就贴着
    // 内容（不留多余空白），放不下才在里面滚。
    final double maxHeight = available.clamp(0.0, _maxHeight);
    final double width = _contentWidth(context, screen);
    final double left = (alignEnd ? anchor.right - width : anchor.left).clamp(
      _screenPadding,
      screen.width - _screenPadding - width,
    );
    // 贴住锚点那一侧：向上开时钉住底边、向下开时钉住顶边，卡片高度变化也不会
    // 和锚点之间飘出空隙
    final double? top = opensAbove ? null : anchor.bottom + _anchorGap;
    final double? bottom = opensAbove
        ? screen.height - anchor.top + _anchorGap
        : null;

    // 动画围绕锚点那一侧展开：菜单在锚点下方时顶端固定、向下长出来，反之亦然
    final Alignment anchorCorner = opensAbove
        ? (alignEnd ? Alignment.bottomRight : Alignment.bottomLeft)
        : (alignEnd ? Alignment.topRight : Alignment.topLeft);
    // 项目沿轴线滑入：在锚点下方时从「更靠近锚点」的位置滑下来
    final double itemSlide = opensAbove ? _itemSlide : -_itemSlide;
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          bottom: bottom,
          width: width,
          child: AnimatedBuilder(
            animation: animation,
            builder: (BuildContext context, Widget? child) {
              final double t = reduceMotion
                  ? 1
                  : Curves.easeOutCubic.transform(animation.value);
              return Opacity(
                opacity: t,
                // 轴向展开：只沿竖直方向长出来，横向不变
                child: Transform(
                  alignment: anchorCorner,
                  transform: Matrix4.diagonal3Values(1, 0.8 + 0.2 * t, 1),
                  child: child,
                ),
              );
            },
            child: Material(
              color: scheme.surfaceContainerLow,
              // M3 给菜单的是 elevation level 2；这里按需求用 3
              elevation: 3,
              surfaceTintColor: Colors.transparent,
              borderRadius: BorderRadius.circular(_radius),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                // 卡片固定，超出高度的部分在卡片里面滚：滚动条沿用应用同款
                // （6dp 圆角滑块、无轨道、滚动时才出现）
                //
                // 轨道默认会让开状态栏 / 挖孔（读 MediaQuery.padding），菜单是
                // 浮在屏幕中间的小卡片，用不上这些安全区——清零后滑块才贴着
                // 卡片的上边和右边（列表页 FastScrollbar 是反着用的：那里要把
                // 顶栏 / 底栏让出来）。
                child: MediaQuery(
                  data: media.copyWith(padding: EdgeInsets.zero),
                  child: ScrollbarTheme(
                    data: const ScrollbarThemeData(
                      trackColor: WidgetStatePropertyAll(Colors.transparent),
                    ),
                    child: Scrollbar(
                      controller: _scroll,
                      thickness: 6,
                      radius: const Radius.circular(3),
                      child: ListView(
                        controller: _scroll,
                        // 贴着内容：放得下时卡片刚好包住项目（不同平台的
                        // VisualDensity 会让行高在 40–48dp 之间变），放不下才滚
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                          vertical: _verticalPadding,
                          horizontal: _itemInset,
                        ),
                        children: [
                          for (int i = 0; i < items.length; i++) ...[
                            // 项目之间留间隔，头尾不额外留（M3E 的块状项目）
                            if (i > 0) const SizedBox(height: _itemGap),
                            AnimatedBuilder(
                              animation: animation,
                              builder: (BuildContext context, Widget? row) {
                                final double p = _itemProgress(animation, i);
                                return Opacity(
                                  opacity: p,
                                  child: Transform.translate(
                                    offset: Offset(0, itemSlide * (1 - p)),
                                    child: row,
                                  ),
                                );
                              },
                              child: M3eMenuRow(
                                icon: items[i].icon,
                                iconFill: items[i].iconFill,
                                label: items[i].label,
                                enabled: items[i].enabled,
                                onTap: () =>
                                    Navigator.of(context).pop(items[i].value),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 取 [context] 对应渲染对象的全局矩形，给 [showM3eMenu] 当锚点。
///
/// 渲染对象还没布局（或已经卸载）时返回 null，调用方直接放弃这次弹菜单即可。
Rect? m3eMenuAnchorOf(BuildContext context) {
  final RenderBox? box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
