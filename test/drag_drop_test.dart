import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/drag_drop.dart';
import 'package:lancloud/core/lanzou_link.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/app_localizations_zh.dart';
import 'package:lancloud/ui/drop_actions.dart';
import 'package:lancloud/ui/share_page.dart';
import 'package:provider/provider.dart';

void main() {
  test('parseAll：一段文本里提取多条链接、去重，密码按就近原则', () {
    const text =
        '第一个 https://wwa.lanzoua.com/iabc123 密码: abcd\n'
        '第二个 www.lanzoub.com/iXYZ789\n'
        '重复的 https://wwa.lanzoua.com/iabc123';
    final links = LanzouLink.parseAll(text);

    expect(links.length, 2);
    expect(links[0].url, 'https://wwa.lanzoua.com/iabc123');
    expect(links[0].pwd, 'abcd');
    expect(links[1].url, 'https://www.lanzoub.com/iXYZ789');
    // 第二条不该继承第一条的密码
    expect(links[1].pwd, isNull);
  });

  test('parseAll：单条链接时整段文本里找密码；没有链接时返回空', () {
    final single = LanzouLink.parseAll(
      '提取码：5a88\nhttps://wwx.lanzoux.com/i123456',
    );
    expect(single.length, 1);
    expect(single.single.pwd, '5a88');

    expect(LanzouLink.parseAll('普通文本，没有链接'), isEmpty);
    expect(LanzouLink.parseAll(null), isEmpty);
  });

  test('parseAll：换行分隔的多条短链', () {
    final links = LanzouLink.parseAll(
      'https://a.lanzoue.com/iAAAAAA\nhttps://b.lanzoue.com/iBBBBBB',
    );
    expect(links.map((l) => l.url), [
      'https://a.lanzoue.com/iAAAAAA',
      'https://b.lanzoue.com/iBBBBBB',
    ]);
  });

  test('payloadFrom：解析原生传来的文本与文件（忽略空项）', () {
    final payload = DragDropChannel.payloadFrom({
      'texts': ['hi', '', '   ', 'https://x'],
      'files': [
        {
          'uri': 'content://a/1',
          'name': 'a.zip',
          'size': 12,
          'mime': 'application/zip',
        },
        {'uri': '', 'name': 'bad'},
      ],
    });

    expect(payload.texts, ['hi', 'https://x']);
    expect(payload.files.length, 1);
    expect(payload.files.single.name, 'a.zip');
    expect(payload.files.single.size, 12);
    expect(payload.hasFiles, isTrue);
    expect(payload.hasText, isTrue);
  });

  test('payloadFrom：原生没给内容时返回空 payload', () {
    expect(DragDropChannel.payloadFrom(null).hasFiles, isFalse);
    expect(
      DragDropChannel.payloadFrom({'texts': [], 'files': []}).hasText,
      isFalse,
    );
  });

  test('拖拽目标：按「内容类型 + 当前视图」决定', () {
    expect(dropFileTarget(onDrivePage: true), DropFileTarget.currentFolder);
    expect(dropFileTarget(onDrivePage: false), DropFileTarget.folderPicker);
    expect(dropLinkTarget(onFavoritesPage: true), DropLinkTarget.favorites);
    expect(dropLinkTarget(onFavoritesPage: false), DropLinkTarget.linkDialog);
  });

  test('DropHover：混合内容与相等判断', () {
    expect(const DropHover(texts: 1, files: 1).isMixed, isTrue);
    expect(const DropHover(files: 2).hasFiles, isTrue);
    expect(const DropHover(texts: 2).hasText, isTrue);
    expect(DropHover.empty.isEmpty, isTrue);
    expect(const DropHover(files: 1), const DropHover(files: 1));
  });

  testWidgets('其它页面拖入链接：走「打开链接」弹窗', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    await handleExternalDrop(
                      context,
                      const DropPayload(
                        texts: ['https://wwa.lanzoua.com/iabc123'],
                      ),
                      onDrivePage: false,
                      onFavoritesPage: false,
                    );
                  },
                  child: const Text('drop'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('drop'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ShareLinkDialog), findsOneWidget);
    // 弹窗会自动解析（测试环境网络不可用，会停在错误提示上），这里只验证它被打开
    // 让解析请求的定时器跑完，避免用例结束时报 pending timer
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    app.dispose();
  });

  testWidgets('收藏页拖入链接：先弹确认条，取消则不解析', (tester) async {
    final app = AppController();
    DropOutcome? outcome;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    outcome = await handleExternalDrop(
                      context,
                      const DropPayload(
                        texts: [
                          'https://wwa.lanzoua.com/iabc123\n'
                              'https://wwa.lanzoua.com/iabc456',
                        ],
                      ),
                      onDrivePage: false,
                      onFavoritesPage: true,
                    );
                  },
                  child: const Text('drop'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('drop'));
    await tester.pumpAndSettle();
    expect(find.text('2 个链接'), findsOneWidget);
    expect(find.text('添加收藏'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(outcome?.canceled, isTrue);
    app.dispose();
  });

  testWidgets('没有可导入内容：提示不支持', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => handleExternalDrop(
                    context,
                    const DropPayload(texts: ['普通文本']),
                    onDrivePage: false,
                    onFavoritesPage: false,
                  ),
                  child: const Text('drop'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('drop'));
    await tester.pumpAndSettle();
    expect(
      find.text(AppLocalizationsZh().shareTargetUnsupported),
      findsOneWidget,
    );
    app.dispose();
  });

  testWidgets('混合内容：文件这一步取消后，链接仍然继续处理', (tester) async {
    final app = AppController();
    final l10n = AppLocalizationsZh();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => handleExternalDrop(
                    context,
                    const DropPayload(
                      texts: ['https://wwa.lanzoua.com/iabc123'],
                      files: [DropFile(uri: 'content://a/1', name: 'a.zip')],
                    ),
                    onDrivePage: false,
                    onFavoritesPage: true,
                  ),
                  child: const Text('drop'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('drop'));
    await tester.pumpAndSettle();
    // 混合内容先确认
    expect(find.text(l10n.dropMixedTitle), findsOneWidget);
    await tester.tap(find.text(l10n.dropContinue));
    await tester.pumpAndSettle();

    // 文件这步因为未登录直接跳过（提示未登录），链接这步继续：弹出收藏确认条
    expect(find.text(l10n.notLoggedIn), findsOneWidget);
    expect(find.text(l10n.dropLinksCount(1)), findsOneWidget);
    expect(find.text(l10n.dropAddFavorites), findsOneWidget);
    app.dispose();
  });
}
