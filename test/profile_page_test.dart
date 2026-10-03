import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/profile_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('「我的」视图：显示账号、网页版、设置与关于', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('管理'), findsOneWidget);
    expect(find.text('显示 Cookie'), findsNothing);
    expect(find.text('网页版'), findsOneWidget);
    expect(find.text('回收站'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    app.dispose();
  });
}
