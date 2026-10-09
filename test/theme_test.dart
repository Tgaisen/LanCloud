import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/app.dart';

void main() {
  test('主题保留默认图标颜色，避免深色模式下图标画成黑色', () {
    final dark = buildLanCloudTheme(
      brightness: Brightness.dark,
      seed: const Color(0xFF2E6BE6),
      oledDark: false,
    );

    // IconButton 依赖这里的颜色判断是否使用 M3 默认前景色；
    // 必须是主题默认的深色模式图标颜色（并且是同一个实例）。
    expect(dark.iconTheme.color, isNotNull);
    expect(identical(dark.iconTheme.color, kDefaultIconLightColor), isTrue);
  });

  test('Material Symbols 可变轴按设计设置：weight 400 / grade 0 / opsz 24', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final theme = buildLanCloudTheme(
        brightness: brightness,
        seed: const Color(0xFF2E6BE6),
        oledDark: false,
      );
      expect(theme.iconTheme.fill, 0);
      expect(theme.iconTheme.weight, 400);
      expect(theme.iconTheme.grade, 0);
      expect(theme.iconTheme.opticalSize, 24);
    }
  });

  test('动态取色也要补齐 surfaceContainer 等新角色（否则整屏一个颜色）', () {
    // 模拟 dynamic_color 插件返回的色板：只有旧版角色
    const dynamic = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF3B5F90),
      onPrimary: Colors.white,
      secondary: Color(0xFF565E71),
      onSecondary: Colors.white,
      error: Color(0xFFBA1A1A),
      onError: Colors.white,
      surface: Color(0xFFF9F9FF),
      onSurface: Color(0xFF191C20),
    );
    final theme = buildLanCloudTheme(
      brightness: Brightness.light,
      seed: const Color(0xFF2E6BE6),
      oledDark: false,
      dynamicScheme: dynamic,
    );
    final scheme = theme.colorScheme;
    expect(scheme.surfaceContainer, isNot(scheme.surface));
    expect(scheme.surfaceContainerHigh, isNot(scheme.surface));
    expect(scheme.surfaceContainerLowest, isNot(scheme.surface));
    // 仍然跟随动态取色的色相（蓝色系主色）
    expect(scheme.primary, isNot(const Color(0xFF3B5F90)));
  });

  test('系统栏样式：导航栏透明 + 不加系统遮罩，图标明暗随主题', () {
    final light = systemUiOverlayStyleFor(Brightness.light);
    expect(light.statusBarColor, Colors.transparent);
    expect(light.systemNavigationBarColor, Colors.transparent);
    // Android 15+ 导航栏强制透明，垫在后面的系统遮罩必须关掉
    expect(light.systemNavigationBarContrastEnforced, isFalse);
    // 浅色底 → 深色图标；深色底 → 浅色图标
    expect(light.systemNavigationBarIconBrightness, Brightness.dark);
    expect(light.statusBarIconBrightness, Brightness.dark);
    final dark = systemUiOverlayStyleFor(Brightness.dark);
    expect(dark.systemNavigationBarIconBrightness, Brightness.light);
    expect(dark.statusBarIconBrightness, Brightness.light);
  });
}
