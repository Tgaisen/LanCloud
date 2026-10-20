import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/app.dart';
import 'package:lancloud/core/agreements.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/first_run_terms.dart';
import 'package:lancloud/ui/login_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lancloud/l10n/delegates.dart';

Future<void> pumpApp(WidgetTester tester, Widget child) async {
  final app = AppController();
  addTearDown(app.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
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

  testWidgets('首次启动勾选协议后进入下一步，未登录弹窗不再叠在欢迎页', (tester) async {
    var accepted = false;
    await pumpApp(tester, FirstRunTerms(onAccepted: () => accepted = true));

    expect(find.text('欢迎使用蓝云'), findsOneWidget);
    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('不同意并退出'), findsOneWidget);

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    // 协议同意与登录解耦：这个回调负责让外壳切到下一步。
    expect(await Agreements.accepted(), isTrue);
    expect(accepted, isTrue);
    expect(find.byType(LoginSheet), findsNothing);
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
    expect(find.text('下一步'), findsOneWidget);
  });
}
