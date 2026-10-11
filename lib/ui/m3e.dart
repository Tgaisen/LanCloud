import 'package:m3e_core/m3e_core.dart' as core;
import 'package:material_3_expressive/material_3_expressive.dart' as m3ex;
import 'package:material_ui/material_ui.dart';

export 'm3e_pull_refresh.dart';

/// 应用只需要认这一个入口：把用到的 MD3E 组件透出来。
///
/// 现状（分支 codex/m3e-expressive-step1）：除了弹出菜单（`showM3eMenu`，
/// 用 material_3_expressive 的 M3EMenu），其余进度条 / 加载指示器 / 按钮组 /
/// 底部弹窗 / 强调排版 / 下拉刷新都在 m3e_core——新包这两类控件试迁过，但它
/// 多出来的参数每处调用都要重新对齐语义，收益不划算，已退回。
///
/// 两个包有 80+ 个同名类型，所以：新包只在本文件内部用（`m3ex.` 前缀），不往
/// 外透；业务代码只认本文件导出的名字。注意 `export` 不会让名字在本文件里
/// 可见：本文件自己用到的 m3e_core 类型要写 `core.` 前缀。
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
        M3EMotion,
        M3EToggleButton,
        M3EToggleButtonDecoration,
        M3EToggleButtonGroup,
        M3EToggleButtonGroupAction,
        M3ETypography,
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
  });

  /// 边长（M3 允许 24–240dp，默认 48dp）。
  final double size;
  final Color? color;
  final String? semanticsLabel;
  final String? semanticsValue;

  @override
  Widget build(BuildContext context) => core.M3ELoadingIndicator(
    color: color,
    constraints: BoxConstraints.tightFor(width: size, height: size),
    semanticsLabel: semanticsLabel,
    semanticsValue: semanticsValue,
  );
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
    if (!wavy) {
      return core.M3ELinearProgressIndicator(
        value: value,
        width: width,
        minHeight: height ?? 4,
        color: color,
        backgroundColor: backgroundColor,
      );
    }
    return core.M3ELinearWavyProgressIndicator(
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
  Widget build(BuildContext context) => core.M3ECircularProgressIndicator(
    value: value,
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
                icon: Icon(item.icon),
                checkedIcon: Icon(item.checkedIcon),
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

/// ────────────────────────────── 弹出菜单 ──────────────────────────────

/// [showM3eMenu] 里的一项：图标 + 文案 + 选中后返回的值。
class M3eMenuItem<T> {
  const M3eMenuItem({
    required this.value,
    required this.label,
    required this.icon,
  });

  /// 选中这一项时 [showM3eMenu] 返回的值。
  final T value;

  /// 菜单文案。
  final String label;

  /// 行首图标。
  final IconData icon;
}

/// 贴在被点控件下方弹出的 MD3E 菜单（material_3_expressive 的 `M3EMenu`）。
///
/// [anchor] 是被点控件的全局矩形：菜单贴它下方弹出（[items] 顺序即显示顺序），
/// 默认左缘对齐；[alignEnd] 为真时右缘对齐——贴右侧的 ⋯ 按钮用这个，菜单不会
/// 被屏幕右上角夹歪。上下 / 左右空间不够时由包自己翻转并夹到屏幕边缘。选中
/// 返回那一项的 [M3eMenuItem.value]，点别处收起返回 null。
///
/// 观感跟主题走：容器 surfaceContainerLow、16dp 圆角、项高 48dp、弹簧展开，
/// 颜色由 ambient `ColorScheme` 推出，所以深浅色切换跟着变。
Future<T?> showM3eMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required List<M3eMenuItem<T>> items,
  bool alignEnd = false,
}) {
  return m3ex.showM3EMenu<T>(
    context: context,
    anchor: anchor,
    position: alignEnd
        ? m3ex.M3EMenuAnchorPosition.bottomEnd
        : m3ex.M3EMenuAnchorPosition.bottomStart,
    children: [
      for (final item in items)
        m3ex.M3EMenuEntry(
          label: item.label,
          leading: Icon(item.icon),
          value: item.value,
        ),
    ],
  );
}

/// 取 [context] 对应渲染对象的全局矩形，给 [showM3eMenu] 当锚点。
///
/// 渲染对象还没布局（或已经卸载）时返回 null，调用方直接放弃这次弹菜单即可。
Rect? m3eMenuAnchorOf(BuildContext context) {
  final RenderBox? box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
