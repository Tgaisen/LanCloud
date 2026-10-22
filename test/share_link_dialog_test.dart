import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/share_page.dart';
import 'package:provider/provider.dart';

import 'package:lancloud/l10n/delegates.dart';

/// 解析分享时固定抛某个异常的假客户端。
class _FakeClient extends LanzouClient {
  _FakeClient(this.error, {this.gate}) : super(uid: '0');

  final LanzouException error;
  final Completer<void>? gate;

  /// 真正发出去的解析请求次数：用来验「格式不对根本不用请求」。
  int resolveCalls = 0;

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async {
    resolveCalls += 1;
    final pending = gate;
    if (pending != null) await pending.future;
    throw error;
  }

  @override
  Future<FolderShareDetail> resolveFolderShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async {
    resolveCalls += 1;
    final pending = gate;
    if (pending != null) await pending.future;
    throw error;
  }
}

class _FakeApp extends AppController {
  _FakeApp(this._client);

  final LanzouClient _client;

  @override
  LanzouClient get publicClient => _client;
}

Future<_FakeClient> _pumpDialog(
  WidgetTester tester,
  LanzouException error, {
  Completer<void>? gate,
}) async {
  final client = _FakeClient(error, gate: gate);
  final app = _FakeApp(client);
  addTearDown(app.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(body: ShareLinkDialog()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return client;
}

Future<void> parseWithWrongPwd(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.first, 'https://wwa.lanzoua.com/iabcdefg');
  await tester.enterText(fields.last, '0000');
  await tester.tap(find.text('解析'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('打开链接：解析中在按钮内显示 MD3E 加载指示器', (tester) async {
    final gate = Completer<void>();
    await _pumpDialog(tester, const NeedPasswordException(), gate: gate);
    await tester.enterText(
      find.byType(TextField).first,
      'https://wwa.lanzoua.com/iabcdefg',
    );
    await tester.tap(find.text('解析'));
    await tester.pump();

    final indicator = find.byType(M3eLoadingIndicator);
    expect(indicator, findsOneWidget);
    expect(tester.widget<M3eLoadingIndicator>(indicator).size, 18);
    expect(find.text('解析中'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(M3eLoadingIndicator), findsNothing);
  });

  testWidgets('打开链接：提取码错误标在提取码输入框上，不用红卡片', (tester) async {
    await _pumpDialog(tester, const WrongPasswordException());
    await parseWithWrongPwd(tester);

    expect(find.text('提取码错误'), findsOneWidget);
    // 与「该分享需要提取码」同一处（输入框 errorText），不是下面的错误卡片
    expect(find.byType(ErrorHintCard), findsNothing);
  });

  testWidgets('打开链接：该分享需要提取码同样是输入框 errorText', (tester) async {
    await _pumpDialog(tester, const NeedPasswordException());
    await parseWithWrongPwd(tester);

    expect(find.text('该分享需要提取码'), findsOneWidget);
    expect(find.byType(ErrorHintCard), findsNothing);
  });

  testWidgets('打开链接：其它解析错误也标在分享链接输入框上', (tester) async {
    await _pumpDialog(tester, const LanzouException('文件不存在或已取消分享'));
    await parseWithWrongPwd(tester);

    expect(find.text('文件不存在或已取消分享'), findsOneWidget);
    // 与提取码错误同一套 MD3E error state：错误文本挂在分享链接输入框上
    expect(find.byType(ErrorHintCard), findsNothing);
    final linkField = tester.widget<TextField>(find.byType(TextField).first);
    expect(linkField.decoration!.errorText, '文件不存在或已取消分享');
    final pwdField = tester.widget<TextField>(find.byType(TextField).last);
    expect(pwdField.decoration!.errorText, isNull);
    // 尾部红色 fill 风格 Error 图标
    expect(find.byIcon(app_icons.Icons.error), findsOneWidget);
  });

  testWidgets('打开链接：链接为空 → 请输入分享链接（弹窗不关）', (tester) async {
    final client = await _pumpDialog(tester, const LanzouException('不该走到这里'));
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();

    expect(find.text('请输入分享链接'), findsOneWidget);
    final linkField = tester.widget<TextField>(find.byType(TextField).first);
    expect(linkField.decoration!.errorText, '请输入分享链接');
    expect(find.byType(ShareLinkDialog), findsOneWidget);
    expect(client.resolveCalls, 0);
  });

  testWidgets('打开链接：不像网址 → 分享链接格式错误，且不发请求', (tester) async {
    final client = await _pumpDialog(tester, const LanzouException('不该走到这里'));
    await tester.enterText(find.byType(TextField).first, '淘口令 abcdefg');
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();

    expect(find.text('分享链接格式错误'), findsOneWidget);
    expect(find.byIcon(app_icons.Icons.error), findsOneWidget);
    expect(client.resolveCalls, 0);
    expect(find.byType(ShareLinkDialog), findsOneWidget);
  });

  testWidgets('打开链接：自定义域名（非 lanzou 域名）的链接也能正常解析', (tester) async {
    final client = await _pumpDialog(tester, const WrongPasswordException());
    await tester.enterText(
      find.byType(TextField).first,
      '视频 https://pan.example.com/iAbCdEf 密码: abcd',
    );
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();

    // 放进了解析请求（没被当成「格式错误」），并把链接里的提取码填进提取码框
    expect(find.text('分享链接格式错误'), findsNothing);
    expect(client.resolveCalls, 1);
    final pwdField = tester.widget<TextField>(find.byType(TextField).last);
    expect(pwdField.controller!.text, 'abcd');
  });

  testWidgets('打开链接：链接文本里自带提取码时自动填进提取码框', (tester) async {
    await _pumpDialog(tester, const WrongPasswordException());
    await tester.enterText(
      find.byType(TextField).first,
      'https://wwa.lanzoua.com/iabcdefg 密码: abcd',
    );
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();

    final pwdField = tester.widget<TextField>(find.byType(TextField).last);
    expect(pwdField.controller!.text, 'abcd');
  });
}
