import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/login_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('登录页：标题为「登录」，两个入口，Cookie 输入在弹窗内', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const LoginPage(firstRun: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('网页登录'), findsOneWidget);
    expect(find.text('Cookie 登录'), findsOneWidget);
    // 页面上不再直接显示 Cookie 输入框与获取步骤
    expect(find.byType(TextField), findsNothing);
    expect(find.text('如何获取 Cookie'), findsNothing);

    await tester.tap(find.text('Cookie 登录'));
    await tester.pumpAndSettle();
    expect(find.text('如何获取 Cookie'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    app.dispose();
  });
}
