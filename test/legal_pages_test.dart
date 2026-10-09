import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/app.dart';
import 'package:lancloud/core/agreements.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/first_run_terms.dart';
import 'package:lancloud/ui/login_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'm3e_host.dart';

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
        builder: m3eTestBuilder,
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

  testWidgets('首次启动同意后弹出登录弹窗；关闭弹窗留在欢迎页', (tester) async {
    var accepted = false;
    await pumpApp(tester, FirstRunTerms(onAccepted: () => accepted = true));

    expect(find.text('欢迎使用蓝云'), findsOneWidget);
    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('不同意并退出'), findsOneWidget);

    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();

    // 同意已写入，但登录弹窗还没完成，仍留在欢迎页
    expect(await Agreements.accepted(), isTrue);
    expect(find.text('网页登录'), findsOneWidget);
    expect(find.text('Cookie 登录'), findsOneWidget);
    expect(accepted, isFalse);

    Navigator.of(tester.element(find.byType(LoginSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用蓝云'), findsOneWidget);
    expect(accepted, isFalse);
  });

  testWidgets('同意页可以打开用户协议与隐私政策弹窗', (tester) async {
    await pumpApp(tester, FirstRunTerms(onAccepted: () {}));

    await tester.tap(find.text('用户协议'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('非官方第三方客户端'), findsOneWidget);
    // 原第 7 条免责声明与前文（第 1、3 条）重复，已删去
    expect(find.textContaining('免责声明'), findsNothing);

    await tester.tap(find.text('关闭'));
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
