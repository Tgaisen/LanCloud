import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/licenses_page.dart';
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

  // 许可正文页：同一个包里可能有多条许可（长正文 + 短补充），
  // 懒布局会拿长正文的高度去估算后面的条目，滑到底时 maxScrollExtent
  // 被修正 -> 滚动条滑块长度抖动。这里钉住「整块布局、范围恒定」。
  testWidgets('许可正文页滚动范围全程恒定（滚动条滑块不会抖动）', (tester) async {
    // 第一条很短、后面每条都很长：懒布局会先按短条目的高度估算剩余内容，
    // 滑动过程中长条目被构建出来，maxScrollExtent 被不断修正 -> 滑块抖动
    final longText = List.generate(
      40,
      (i) => '第 $i 行许可文本，用于把正文撑得足够长以便滚动。',
    ).join('\n');
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(<String>[
        'lancloud_license_test',
      ], '短许可补充');
      for (var i = 0; i < 10; i++) {
        yield LicenseEntryWithLineBreaks(<String>[
          'lancloud_license_test',
        ], longText);
      }
    });

    final app = AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const LicensesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('lancloud_license_test'));
    await tester.pumpAndSettle();

    // 顶层路由（正文页）自己的滚动视图
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
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
