import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';

Future<BuildContext> host(WidgetTester tester) async {
  late BuildContext pageContext;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return pageContext;
}

void main() {
  testWidgets('密码弹窗预填开关与密码，关闭开关后确认表示清除密码', (tester) async {
    final context = await host(tester);
    final result = showPasswordDialog(context, enabled: true, pwd: '1234');
    await tester.pumpAndSettle();

    // 开关按当前状态预填为开启，密码框预填当前密码
    expect(find.text('启用访问密码'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1234',
    );

    // 关闭开关：密码框禁用
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    final value = await result;
    expect(value, (enabled: false, pwd: ''));
  });

  testWidgets('开启密码但过短时提示且不关闭弹窗', (tester) async {
    final context = await host(tester);
    final result = showPasswordDialog(context, enabled: false, pwd: '');
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );

    // 打开开关后直接确定：提示密码过短，弹窗保持
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('提取码至少 2 位'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);

    // 输入合法密码后确定
    await tester.enterText(find.byType(TextField), 'ab12');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    final value = await result;
    expect(value, (enabled: true, pwd: 'ab12'));
  });
}
