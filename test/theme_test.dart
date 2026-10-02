import 'package:flutter/material.dart';
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
}
