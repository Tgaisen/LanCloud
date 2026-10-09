import 'package:flutter/material.dart' as md;
import 'package:flutter/widgets.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart' as mui;

/// 应用只需要认这一个入口：把用到的 MD3E 组件从 m3e_core 透出来。
export 'package:m3e_core/m3e_core.dart'
    show
        M3EBottomSheet,
        M3EBottomSheetStyle,
        M3EBottomSheetTheme,
        M3EContainedLoadingIndicator,
        M3ECircularProgressIndicator,
        M3ECircularWavyProgressIndicator,
        M3ELinearProgressIndicator,
        M3ELinearWavyProgressIndicator,
        M3ELoadingIndicator,
        M3EMotion,
        M3ETypography,
        Shapes,
        showM3EModalBottomSheet;

/// ────────────────────────────── M3 Expressive 接入层 ──────────────────────────────
///
/// 应用主体仍使用 Flutter 框架自带的 `package:flutter/material.dart`，而
/// [m3e_core] 建立在拆分出来的 `package:material_ui` 之上：两套 ThemeData /
/// ColorScheme / MaterialLocalizations 是**不同的类型**，不会自动互相继承。
///
/// [M3eHost] 负责把两者接起来：
/// 1. 把当前页面的 ThemeData 映射成 material_ui 版本（色板、排版、字体兜底
///    全量同步），让 MD3E 控件的取色、取字与应用其它部分完全一致；
/// 2. 在子树里补上 material_ui 自己的 MaterialLocalizations
///    （`showM3EModalBottomSheet` 等控件会断言它存在）。
///
/// 因为它同时要覆盖由根 Navigator 打开的模态底部弹窗，所以必须挂在
/// `MaterialApp.builder` 上（Navigator 之上），而不是挂在某个页面里。

/// 把应用主题映射为 material_ui 主题，并补齐 MD3E 控件需要的本地化。
class M3eHost extends StatelessWidget {
  const M3eHost({super.key, required this.child});

  /// 子树（通常是 Navigator）。
  final Widget child;

  /// 把框架主题映射成 material_ui 主题（供测试与调试直接取用）。
  static mui.ThemeData themeDataOf(md.ThemeData source) =>
      _mapThemeData(source);

  @override
  Widget build(BuildContext context) {
    final theme = md.Theme.of(context);
    return mui.Theme(
      data: themeDataOf(theme),
      child: mui.Localizations.override(
        context: context,
        delegates: mui.GlobalMaterialLocalizations.delegates,
        child: child,
      ),
    );
  }

  static mui.ThemeData _mapThemeData(md.ThemeData source) {
    final scheme = source.colorScheme;
    final body = source.textTheme.bodyMedium;
    return mui.ThemeData(
      useMaterial3: true,
      brightness: source.brightness,
      platform: source.platform,
      visualDensity: mui.VisualDensity(
        horizontal: source.visualDensity.horizontal,
        vertical: source.visualDensity.vertical,
      ),
      colorScheme: mui.ColorScheme(
        brightness: scheme.brightness,
        primary: scheme.primary,
        onPrimary: scheme.onPrimary,
        primaryContainer: scheme.primaryContainer,
        onPrimaryContainer: scheme.onPrimaryContainer,
        primaryFixed: scheme.primaryFixed,
        primaryFixedDim: scheme.primaryFixedDim,
        onPrimaryFixed: scheme.onPrimaryFixed,
        onPrimaryFixedVariant: scheme.onPrimaryFixedVariant,
        secondary: scheme.secondary,
        onSecondary: scheme.onSecondary,
        secondaryContainer: scheme.secondaryContainer,
        onSecondaryContainer: scheme.onSecondaryContainer,
        secondaryFixed: scheme.secondaryFixed,
        secondaryFixedDim: scheme.secondaryFixedDim,
        onSecondaryFixed: scheme.onSecondaryFixed,
        onSecondaryFixedVariant: scheme.onSecondaryFixedVariant,
        tertiary: scheme.tertiary,
        onTertiary: scheme.onTertiary,
        tertiaryContainer: scheme.tertiaryContainer,
        onTertiaryContainer: scheme.onTertiaryContainer,
        tertiaryFixed: scheme.tertiaryFixed,
        tertiaryFixedDim: scheme.tertiaryFixedDim,
        onTertiaryFixed: scheme.onTertiaryFixed,
        onTertiaryFixedVariant: scheme.onTertiaryFixedVariant,
        error: scheme.error,
        onError: scheme.onError,
        errorContainer: scheme.errorContainer,
        onErrorContainer: scheme.onErrorContainer,
        surface: scheme.surface,
        onSurface: scheme.onSurface,
        surfaceDim: scheme.surfaceDim,
        surfaceBright: scheme.surfaceBright,
        surfaceContainerLowest: scheme.surfaceContainerLowest,
        surfaceContainerLow: scheme.surfaceContainerLow,
        surfaceContainer: scheme.surfaceContainer,
        surfaceContainerHigh: scheme.surfaceContainerHigh,
        surfaceContainerHighest: scheme.surfaceContainerHighest,
        onSurfaceVariant: scheme.onSurfaceVariant,
        outline: scheme.outline,
        outlineVariant: scheme.outlineVariant,
        shadow: scheme.shadow,
        scrim: scheme.scrim,
        inverseSurface: scheme.inverseSurface,
        onInverseSurface: scheme.onInverseSurface,
        inversePrimary: scheme.inversePrimary,
        surfaceTint: scheme.surfaceTint,
      ),
      textTheme: muiTextThemeOf(source.textTheme),
      // Windows 上中文兜底字体（微软雅黑）也要跟着走，否则 MD3E 控件里的
      // 中文会掉到日文字形。
      fontFamily: body?.fontFamily,
      fontFamilyFallback: body?.fontFamilyFallback,
    );
  }
}

/// 把框架的 [md.TextTheme] 映射成 material_ui 的同名排版。
///
/// 两边都用框架 `package:flutter/painting.dart` 的 TextStyle，逐项搬即可。
mui.TextTheme muiTextThemeOf(md.TextTheme t) => mui.TextTheme(
  displayLarge: t.displayLarge,
  displayMedium: t.displayMedium,
  displaySmall: t.displaySmall,
  headlineLarge: t.headlineLarge,
  headlineMedium: t.headlineMedium,
  headlineSmall: t.headlineSmall,
  titleLarge: t.titleLarge,
  titleMedium: t.titleMedium,
  titleSmall: t.titleSmall,
  bodyLarge: t.bodyLarge,
  bodyMedium: t.bodyMedium,
  bodySmall: t.bodySmall,
  labelLarge: t.labelLarge,
  labelMedium: t.labelMedium,
  labelSmall: t.labelSmall,
);

/// [muiTextThemeOf] 的反向映射。
md.TextTheme frameworkTextThemeOf(mui.TextTheme t) => md.TextTheme(
  displayLarge: t.displayLarge,
  displayMedium: t.displayMedium,
  displaySmall: t.displaySmall,
  headlineLarge: t.headlineLarge,
  headlineMedium: t.headlineMedium,
  headlineSmall: t.headlineSmall,
  titleLarge: t.titleLarge,
  titleMedium: t.titleMedium,
  titleSmall: t.titleSmall,
  bodyLarge: t.bodyLarge,
  bodyMedium: t.bodyMedium,
  bodySmall: t.bodySmall,
  labelLarge: t.labelLarge,
  labelMedium: t.labelMedium,
  labelSmall: t.labelSmall,
);

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
md.TextTheme m3eEmphasizedTextTheme(
  md.TextTheme base, {
  double rond = 0,
  double? bodyRond,
}) {
  final canon = frameworkTextThemeOf(
    M3ETypography.emphasized(
      muiTextThemeOf(base),
      rond: rond,
      bodyRond: bodyRond,
    ),
  );
  md.TextStyle? weigh(md.TextStyle? b, md.TextStyle? c) =>
      b?.copyWith(fontWeight: c?.fontWeight, fontVariations: c?.fontVariations);
  return md.TextTheme(
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
/// （不用 `emphasizedTextTheme` 这个名字：m3e_core 自带的同扩展成员返回的是
/// material_ui 的 TextTheme，两边同时导入会撞名。）
extension M3eThemeX on md.BuildContext {
  /// 当前主题的强调排版（基于已合并脚本几何的基线排版派生）。
  md.TextTheme get m3eEmphasizedTheme =>
      m3eEmphasizedTextTheme(md.Theme.of(this).textTheme);
}

/// 把强调排版落到**组件级**样式上：顶栏标题、弹窗标题、主要按钮、
/// 导航栏 / 导航轨的选中项。
///
/// 这些主题字段必须是完整 TextStyle，而字号要等 `Theme.of` 合并脚本几何之后
/// 才有，所以只能在拿到 context 之后再套一层 [md.Theme]（见 app.dart 的
/// MaterialApp.builder）。没被点名的角色（正文、次要按钮、未选中项……）继续
/// 用基线排版——M3E 强调排版是标记例外，不是整份替换。
class M3eComponentStyles extends StatelessWidget {
  const M3eComponentStyles({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = md.Theme.of(context);
    final base = theme.textTheme;
    final emph = context.m3eEmphasizedTheme;
    return md.Theme(
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
        filledButtonTheme: md.FilledButtonThemeData(
          style: md.ButtonStyle(
            textStyle: md.WidgetStatePropertyAll<md.TextStyle?>(
              emph.labelLarge,
            ),
          ),
        ),
        elevatedButtonTheme: md.ElevatedButtonThemeData(
          style: md.ButtonStyle(
            textStyle: md.WidgetStatePropertyAll<md.TextStyle?>(
              emph.labelLarge,
            ),
          ),
        ),
        // 导航栏：只有选中项用强调排版（选中状态是 M3E 点名的用法）。
        navigationBarTheme: theme.navigationBarTheme.copyWith(
          labelTextStyle: md.WidgetStateProperty.resolveWith<md.TextStyle?>(
            (states) => states.contains(md.WidgetState.selected)
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

/// 应用（以及测试宿主）的 M3E 统一入口：强调排版的组件级样式 + material_ui 桥接。
///
/// 挂在 `MaterialApp.builder` 上，覆盖 Navigator 之上的整棵树——根 Navigator
/// 打开的模态弹窗、对话框里的 MD3E 控件都能取到同一套主题与本地化。
class M3eRoot extends StatelessWidget {
  const M3eRoot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      M3eComponentStyles(child: M3eHost(child: child));
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
