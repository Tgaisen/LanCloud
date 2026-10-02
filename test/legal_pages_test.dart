import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/app.dart';
import 'package:lancloud/core/agreements.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/first_run_terms.dart';
import 'package:lancloud/ui/legal_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpApp(WidgetTester tester, Widget child) async {
  final app = AppController();
  addTearDown(app.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('同意状态按版本记录', () async {
    expect(await Agreements.accepted(), isFalse);
    await Agreements.accept();
    expect(await Agreements.accepted(), isTrue);
  });

  testWidgets('首次启动显示同意页，同意后写入标记', (tester) async {
    var accepted = false;
    await pumpApp(tester, FirstRunTerms(onAccepted: () => accepted = true));

    expect(find.text('欢迎使用蓝云'), findsOneWidget);
    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('不同意并退出'), findsOneWidget);

    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();

    expect(accepted, isTrue);
    expect(await Agreements.accepted(), isTrue);
  });

  testWidgets('同意页可以打开用户协议与隐私政策全文', (tester) async {
    await pumpApp(tester, FirstRunTerms(onAccepted: () {}));

    await tester.tap(find.text('用户协议'));
    await tester.pumpAndSettle();
    expect(find.byType(LegalPage), findsOneWidget);
    expect(find.textContaining('非官方第三方客户端'), findsOneWidget);

    // 自定义 AppBar 的返回按钮（pageBack 依赖系统返回图标，这里直接点按钮）
    await tester.tap(find.byType(IconButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐私政策'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不收集、不上传任何个人信息'), findsOneWidget);
  });

  testWidgets('未同意条款时进入同意页而不是主界面', (tester) async {
    await pumpApp(tester, const AgreementGate());

    expect(find.text('欢迎使用蓝云'), findsOneWidget);
    expect(find.text('同意并继续'), findsOneWidget);
  });
}
