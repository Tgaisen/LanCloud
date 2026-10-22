import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/backup/webdav_client.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/backup_page.dart';

import 'package:lancloud/l10n/delegates.dart';

/// 打开 WebDAV 账号弹窗，返回保存结果（取消 / 重置 / 保存都会完成它）。
Future<Future<List<String>?>> pumpDialog(
  WidgetTester tester, {
  String url = '',
  String username = '',
  String password = '',
  String path = '/LanCloud',
}) async {
  late Future<List<String>?> result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                result = showDialog<List<String>>(
                  context: context,
                  builder: (_) => WebdavAccountDialog(
                    url: url,
                    username: username,
                    password: password,
                    path: path,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  test('WebDAV 地址格式判定：允许省协议头与内网地址，拒绝空 / 无主机 / 带空格', () {
    expect(WebdavClient.isValidUrl('https://example.com/dav'), isTrue);
    expect(WebdavClient.isValidUrl('http://example.com/dav'), isTrue);
    // 省略协议头（normalizeBase 会补 https://）
    expect(WebdavClient.isValidUrl('example.com/dav'), isTrue);
    expect(WebdavClient.isValidUrl('192.168.1.5:8080/dav'), isTrue);
    expect(WebdavClient.isValidUrl('https://[::1]/dav'), isTrue);
    expect(WebdavClient.isValidUrl(''), isFalse);
    expect(WebdavClient.isValidUrl('http://'), isFalse);
    expect(WebdavClient.isValidUrl('https://a b.com/dav'), isFalse);
    expect(WebdavClient.isValidUrl('随便写的'), isFalse);
  });

  testWidgets('四项都为空点保存：每个输入框各自 error state，弹窗不关', (tester) async {
    await pumpDialog(tester, path: '');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('请输入 WebDAV 地址'), findsOneWidget);
    expect(find.text('请输入用户名'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
    expect(find.text('请输入路径'), findsOneWidget);
    // 四个输入框都带尾部红色 fill 风格 Error 图标
    expect(find.byIcon(Icons.error), findsNWidgets(4));
    expect(find.byType(WebdavAccountDialog), findsOneWidget);
  });

  testWidgets('地址格式不对：报「WebDAV 地址格式错误」，其它两项不报错', (tester) async {
    await pumpDialog(tester, url: '随便写的', username: 'u', password: 'p');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('WebDAV 地址格式错误'), findsOneWidget);
    expect(find.text('请输入用户名'), findsNothing);
    expect(find.text('请输入密码'), findsNothing);
    expect(find.byType(WebdavAccountDialog), findsOneWidget);
  });

  testWidgets('填好四项点保存：正常关闭并返回输入值（路径去掉首尾空白）', (tester) async {
    final result = await pumpDialog(
      tester,
      url: ' https://example.com/dav ',
      username: ' user ',
      password: 'pwd',
      path: ' /LanCloud ',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.byType(WebdavAccountDialog), findsNothing);
    expect(await result, [
      'https://example.com/dav',
      'user',
      'pwd',
      '/LanCloud',
    ]);
  });

  testWidgets('重置：清空配置，路径回到默认值', (tester) async {
    final result = await pumpDialog(
      tester,
      url: 'https://example.com/dav',
      username: 'u',
      password: 'p',
      path: '/Backups',
    );
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();

    expect(find.byType(WebdavAccountDialog), findsNothing);
    expect(await result, ['', '', '', '/LanCloud']);
  });

  testWidgets('首次填写密码可以显示或隐藏输入内容', (tester) async {
    await pumpDialog(tester);

    expect(find.byTooltip('显示密码'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).obscureText,
      isFalse,
    );
    expect(find.byTooltip('隐藏密码'), findsOneWidget);
  });

  testWidgets('已有密码再次打开时不提供显示密码入口', (tester) async {
    await pumpDialog(
      tester,
      url: 'https://example.com/dav',
      username: 'u',
      password: 'saved-password',
    );

    expect(find.byTooltip('显示密码'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).obscureText,
      isTrue,
    );
  });

  testWidgets('标题是「WebDAV 账号」，动作只有「重置 / 保存」两个', (tester) async {
    await pumpDialog(tester);

    expect(find.text('WebDAV 账号'), findsOneWidget);
    expect(find.text('路径'), findsOneWidget);
    expect(find.text('备份密码'), findsNothing);
    expect(find.text('重置'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    // 基本弹窗最多两个动作：取消已经去掉
    expect(find.text('取消'), findsNothing);
  });

  testWidgets('路径为空：保存时报「请输入路径」，其它项不报错', (tester) async {
    await pumpDialog(
      tester,
      url: 'https://example.com/dav',
      username: 'u',
      password: 'p',
      path: '   ',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('请输入路径'), findsOneWidget);
    expect(find.text('请输入 WebDAV 地址'), findsNothing);
    expect(find.text('请输入用户名'), findsNothing);
    expect(find.text('请输入密码'), findsNothing);
    expect(find.byType(WebdavAccountDialog), findsOneWidget);
  });
}
