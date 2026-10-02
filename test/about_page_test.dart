import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/app_info.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/about_page.dart';
import 'package:lancloud/ui/legal_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('关于页显示版本、协议入口与免责声明', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const AboutPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('蓝云'), findsOneWidget);
    expect(find.text('版本 $appVersion（构建 $appBuild）'), findsOneWidget);
    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('开源许可'), findsOneWidget);
    expect(find.text('项目主页'), findsOneWidget);
    expect(find.text(projectUrl), findsOneWidget);
    expect(find.text('免责声明'), findsOneWidget);
    expect(find.textContaining('Apache License 2.0'), findsOneWidget);
    app.dispose();
  });

  testWidgets('关于页可以进入隐私政策全文', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const AboutPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('隐私政策'));
    await tester.pumpAndSettle();

    expect(find.byType(LegalPage), findsOneWidget);
    expect(find.textContaining('WebDAV'), findsWidgets);
    app.dispose();
  });
}
