import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';

import 'package:lancloud/l10n/delegates.dart';

Future<BuildContext> host(WidgetTester tester) async {
  late BuildContext pageContext;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
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
      tester.widget<M3eSwitchTile>(find.byType(M3eSwitchTile)).value,
      isTrue,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1234',
    );

    // 关闭开关：密码框禁用
    await tester.tap(find.byType(M3eSwitchTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<M3eSwitchTile>(find.byType(M3eSwitchTile)).value,
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
      tester.widget<M3eSwitchTile>(find.byType(M3eSwitchTile)).value,
      isFalse,
    );

    // 打开开关后直接确定：提示密码过短，弹窗保持
    await tester.tap(find.byType(M3eSwitchTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('提取码至少 2 位'), findsOneWidget);
    final invalidField = tester.widget<TextField>(find.byType(TextField));
    expect(invalidField.decoration!.errorText, '提取码至少 2 位');
    // 与其它输入弹窗一致：尾部红色 fill 风格 Error 图标
    expect(find.byIcon(app_icons.Icons.error), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);

    // 输入合法密码后确定
    await tester.enterText(find.byType(TextField), 'ab12');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    final value = await result;
    expect(value, (enabled: true, pwd: 'ab12'));
  });

  testWidgets('文件夹提取码可到 12 位；免费账号提示关闭需会员；开关整行铺满弹窗', (tester) async {
    final context = await host(tester);
    final result = showPasswordDialog(
      context,
      enabled: false,
      pwd: '',
      maxLength: 12,
      freeTier: true,
    );
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 12);
    expect(find.text('2-12 位提取码'), findsOneWidget);
    // 免费账号：开关下面说明「关闭访问密码需要开通会员」
    expect(find.text('关闭访问密码需要开通会员'), findsOneWidget);
    // 开关行铺满列表组（内容宽度 = dialogFormWidth，组外边距为 0）
    expect(
      tester.getSize(find.byType(M3eSwitchTile)).width,
      dialogFormWidth(context),
    );

    // 12 位密码可以确认
    await tester.tap(find.byType(M3eSwitchTile));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc123456789');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(await result, (enabled: true, pwd: 'abc123456789'));
  });
}
