import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/share_folder_page.dart';
import 'package:provider/provider.dart';

Future<AppController> pumpShareFolder(
  WidgetTester tester,
  FolderShareDetail folder,
) async {
  // 本文件校验顶栏浮层的滚动渐隐：固定 Compact 窗口（<600dp）保持单列列表
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 600);
  addTearDown(tester.view.reset);
  final app = AppController()..settings.hideTopBar = true;
  addTearDown(app.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: ShareFolderPage(
          folder: folder,
          link: 'https://example.com/share',
          pwd: '',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

void main() {
  testWidgets('分享文件夹页：说明 / 子目录 / 文件正常渲染，顶栏为浮层', (tester) async {
    await pumpShareFolder(
      tester,
      FolderShareDetail(
        name: '测试分享',
        desc: '分享说明',
        folders: [SubFolder(name: '子目录', url: 'https://example.com/f')],
        files: [
          ShareFileItem(
            name: 'a.txt',
            time: '2026-10-01',
            size: '1 M',
            url: 'https://example.com/a',
          ),
        ],
      ),
    );

    expect(find.byType(TopBarOverlayScaffold), findsOneWidget);
    expect(find.text('测试分享'), findsOneWidget);
    expect(find.text('分享说明'), findsOneWidget);
    expect(find.text('子目录'), findsOneWidget);
    expect(find.text('a.txt'), findsOneWidget);
  });

  testWidgets('空分享居中显示提示', (tester) async {
    await pumpShareFolder(tester, FolderShareDetail(name: '空分享'));

    expect(find.text('这个分享里没有文件'), findsOneWidget);
    expect(find.byType(TopBarOverlayScaffold), findsOneWidget);
  });

  testWidgets('顶栏上滑同样随手指渐隐，且不动外壳进度', (tester) async {
    final app = await pumpShareFolder(
      tester,
      FolderShareDetail(
        name: '长分享',
        files: [
          for (var i = 0; i < 12; i++)
            ShareFileItem(
              name: 'file$i.txt',
              time: '2026-10-01',
              size: '1 M',
              url: 'https://example.com/$i',
            ),
        ],
      ),
    );
    double barTop() =>
        tester.getTopLeft(find.byType(AppBar, skipOffstage: false)).dy;
    double contentOpacity() => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byType(AppBar, skipOffstage: false),
                matching: find.byType(Opacity, skipOffstage: false),
              )
              .first,
        )
        .opacity;

    expect(barTop(), 0);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(barTop(), -kToolbarHeight);
    expect(contentOpacity(), closeTo(0, 0.01));
    expect(app.topBarHide.value, 0);
  });
}
