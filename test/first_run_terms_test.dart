import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/first_run_terms.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  testWidgets('欢迎页的导航栏也沉浸：透明、不加系统遮罩、图标随主题', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: FirstRunTerms(onAccepted: () {}),
      ),
    );
    await tester.pumpAndSettle();

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find
          .descendant(
            of: find.byType(FirstRunTerms),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          )
          .first,
    );
    // 和主界面同一份系统栏样式：状态栏 / 导航栏都透明
    expect(region.value.statusBarColor, Colors.transparent);
    expect(region.value.systemNavigationBarColor, Colors.transparent);
    expect(region.value.systemNavigationBarDividerColor, Colors.transparent);
    // Android 15+ 强制透明，垫在后面的系统遮罩必须关掉
    expect(region.value.systemNavigationBarContrastEnforced, isFalse);
    // 浅色主题 → 导航栏用深色图标
    expect(region.value.systemNavigationBarIconBrightness, Brightness.dark);
  });
}
