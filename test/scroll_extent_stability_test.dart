import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/settings_page.dart';
import 'package:provider/provider.dart';

import 'package:lancloud/l10n/delegates.dart';

/// 设置页各分组的条目高度差异很大（开关 / 二级入口 / 图标），
/// 如果用 SliverList 懒布局，maxScrollExtent 会随滑动不断被"平均高度"修正，
/// 滚动条滑块长度就会一抖一抖。这里钉住修复：滚动过程中滚动范围恒定。
void main() {
  testWidgets('设置页滚动范围全程恒定（滚动条滑块不会抖动）', (tester) async {
    final app = AppController();
    addTearDown(app.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;

    // 内容要真的能滚，否则测不出估算问题
    expect(position.maxScrollExtent, greaterThan(0));

    final atTop = position.maxScrollExtent;
    final samples = <double>[];
    for (var step = 1; step <= 4; step++) {
      position.jumpTo(position.maxScrollExtent * step / 5);
      await tester.pumpAndSettle();
      samples.add(position.maxScrollExtent);
    }
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    samples.add(position.maxScrollExtent);

    for (final value in samples) {
      expect(value, moreOrLessEquals(atTop, epsilon: 0.5));
    }
  });
}
