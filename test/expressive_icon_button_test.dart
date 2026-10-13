import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  testWidgets('首页快捷操作按钮：按下从胶囊形变到 12dp 圆角，松开弹回', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Center(
            child: ExpressiveIconButton(
              icon: Icons.open_in_new,
              label: '打开链接',
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    double radius() {
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(ExpressiveIconButton),
              matching: find.byType(Material),
            )
            .first,
      );
      final shape = material.shape! as RoundedRectangleBorder;
      return shape.borderRadius.resolve(TextDirection.ltr).topLeft.x;
    }

    // 静止 = 胶囊形（半径取半高：56 / 2）
    expect(radius(), 28);

    final gesture = await tester.press(find.byType(ExpressiveIconButton));
    // onHighlightChanged 要等手势仲裁的 100ms 截止线，之后再让弹簧跑一会
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 120));
    expect(radius(), lessThan(28));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(radius(), moreOrLessEquals(28, epsilon: 0.5));
  });
}
