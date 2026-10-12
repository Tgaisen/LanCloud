import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;

void main() {
  // 码点与字体族要和 assets/fonts/remixicon_subset.ttf（U+F59A star-off-line）
  // 以及 pubspec 里声明的 family 保持一致，避免图标静默变成别的字形 / 空白。
  test('star_off_line 指向 Remix 子集字体里的 star-off-line', () {
    expect(app_icons.Icons.star_off_line.codePoint, 0xf59a);
    expect(app_icons.Icons.star_off_line.fontFamily, 'RemixIcon');
    expect(app_icons.Icons.star_off_line.fontPackage, isNull);
  });
}
