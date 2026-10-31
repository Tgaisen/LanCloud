import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/share_folder_page.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'transfer_dependencies_test.dart' show buildTransferManager;

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
  final transfers = buildTransferManager(app);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transferManagerProvider.overrideWithValue(transfers),
        navigationAppearanceSettingsStateProvider.overrideWithValue(
          app.navigationAppearanceSettings,
        ),
        navigationStateProvider.overrideWithValue(app.navigation),
      ],
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
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
  // 长按进入多选：整条顶栏淡入淡出（与网盘页同款），不是直接换掉
  testWidgets('分享文件夹页：长按进多选时顶栏是淡入的', (tester) async {
    await pumpShareFolder(
      tester,
      FolderShareDetail(
        name: '测试分享',
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

    await tester.longPress(find.text('a.txt'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // 多选顶栏已经在树里，但还在淡入（透明度介于 0~1）
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('share-selection-appbar')),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, greaterThan(0));
    expect(fade.opacity.value, lessThan(1));

    await tester.pumpAndSettle();
    expect(fade.opacity.value, 1.0);
    expect(find.text('已选择 1 项'), findsOneWidget);
  });

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

  // 条目 ⋯ 菜单：文件夹给「打开 / 复制链接 / 收藏」，文件多一个「下载」、
  // 打开项叫「查看」（等于点条目本身，弹属性弹窗）
  testWidgets('分享浏览页条目 ⋯ 菜单：文件夹三项、文件四项', (tester) async {
    await pumpShareFolder(
      tester,
      FolderShareDetail(
        name: '测试分享',
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

    List<String> menuLabels() => tester
        .widgetList<M3eMenuRow>(find.byType(M3eMenuRow))
        .map((row) => row.label)
        .toList();

    Future<void> openMenu(String name) async {
      final row = find.ancestor(
        of: find.text(name),
        matching: find.byType(Md3ListItem),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byTooltip('更多操作')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    // 子文件夹：打开 / 复制链接 / 收藏
    await openMenu('子目录');
    expect(menuLabels(), ['打开', '复制链接', '收藏']);
    // 点菜单外收起（菜单有遮罩，点不到下面的列表）
    await tester.tapAt(const Offset(5, 300));
    await tester.pumpAndSettle();

    // 文件：查看 / 下载 / 复制链接 / 收藏
    await openMenu('a.txt');
    expect(menuLabels(), ['查看', '下载', '复制链接', '收藏']);
    await tester.tapAt(const Offset(5, 300));
    await tester.pumpAndSettle();
  });

  testWidgets('分享浏览页 ⋯ 菜单：已加入下载的文件「下载」项置灰', (tester) async {
    await pumpShareFolder(
      tester,
      FolderShareDetail(
        name: '测试分享',
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
    // 页面里读的就是同一个管理器：直接塞一条匹配的任务（含下载中）
    final manager = ProviderScope.containerOf(
      tester.element(find.byType(ShareFolderPage)),
      listen: false,
    ).read(transferManagerProvider);
    manager.tasks.add(
      TransferTask(
        id: 'd1',
        kind: TransferKind.download,
        name: 'a.txt',
        accountUid: '',
        referer: 'https://example.com/a',
      )..status = TransferStatus.running,
    );

    final row = find.ancestor(
      of: find.text('a.txt'),
      matching: find.byType(Md3ListItem),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('更多操作')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final downloadRow = tester
        .widgetList<M3eMenuRow>(find.byType(M3eMenuRow))
        .firstWhere((r) => r.label == '下载');
    expect(downloadRow.enabled, isFalse);
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
