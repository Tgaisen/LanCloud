import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/login_page.dart';
import 'package:provider/provider.dart';

import 'package:lancloud/l10n/delegates.dart';

Widget host(Widget home) {
  return ChangeNotifierProvider<AppController>.value(
    value: AppController(),
    child: MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: home,
    ),
  );
}

void main() {
  testWidgets('登录弹窗：标题「登录」+ 两个入口，Cookie 输入在弹窗内', (tester) async {
    await tester.pumpWidget(
      host(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showLoginSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('网页登录'), findsOneWidget);
    expect(find.text('Cookie 登录'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Cookie 登录'));
    await tester.pumpAndSettle();
    expect(find.text('如何获取 Cookie'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('兜底登录页内容与弹窗一致（页面内没有 Cookie 输入框）', (tester) async {
    await tester.pumpWidget(host(const LoginPage(firstRun: true)));
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('网页登录'), findsOneWidget);
    expect(find.text('Cookie 登录'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
