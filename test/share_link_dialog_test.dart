import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/share_page.dart';
import 'package:provider/provider.dart';

import 'package:lancloud/l10n/delegates.dart';

/// 解析分享时固定抛某个异常的假客户端。
class _FakeClient extends LanzouClient {
  _FakeClient(this.error) : super(uid: '0');

  final LanzouException error;

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
  }) async => throw error;

  @override
  Future<FolderShareDetail> resolveFolderShare(
    String shareUrl, {
    String pwd = '',
  }) async => throw error;
}

class _FakeApp extends AppController {
  _FakeApp(LanzouException error) : _client = _FakeClient(error);

  final LanzouClient _client;

  @override
  LanzouClient get publicClient => _client;
}

Future<void> pumpDialog(WidgetTester tester, LanzouException error) async {
  final app = _FakeApp(error);
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
}

Future<void> parseWithWrongPwd(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.first, 'https://example.com/abcdefg');
  await tester.enterText(fields.last, '0000');
  await tester.tap(find.text('解析'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('打开链接：提取码错误标在提取码输入框上，不用红卡片', (tester) async {
    await pumpDialog(tester, const WrongPasswordException());
    await parseWithWrongPwd(tester);

    expect(find.text('提取码错误'), findsOneWidget);
    // 与「该分享需要提取码」同一处（输入框 errorText），不是下面的错误卡片
    expect(find.byType(ErrorHintCard), findsNothing);
  });

  testWidgets('打开链接：该分享需要提取码同样是输入框 errorText', (tester) async {
    await pumpDialog(tester, const NeedPasswordException());
    await parseWithWrongPwd(tester);

    expect(find.text('该分享需要提取码'), findsOneWidget);
    expect(find.byType(ErrorHintCard), findsNothing);
  });

  testWidgets('打开链接：其它解析错误仍用错误卡片', (tester) async {
    await pumpDialog(tester, const LanzouException('文件不存在或已取消分享'));
    await parseWithWrongPwd(tester);

    expect(find.text('文件不存在或已取消分享'), findsOneWidget);
    // 错误提示用 Error container 卡片（不再是裸文字 / 默认 Card）
    expect(find.byType(ErrorHintCard), findsOneWidget);
    final card = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(ErrorHintCard),
            matching: find.byType(Container),
          )
          .first,
    );
    final scheme = Theme.of(tester.element(find.byType(ErrorHintCard)))
        .colorScheme;
    expect((card.decoration! as BoxDecoration).color, scheme.errorContainer);
    final text = tester.widget<Text>(find.text('文件不存在或已取消分享'));
    expect(text.style?.color, scheme.onErrorContainer);
  });
}
