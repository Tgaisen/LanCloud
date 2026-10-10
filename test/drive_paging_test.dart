import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/drive_page.dart';
import 'package:provider/provider.dart';

/// 第一页只有几条、且服务端说「还有下一页」的目录：真机上必须自动补一页，
/// 才能知道已经到底（否则要用户滑一下才出现「已经到底了」）。
class _FakeClient extends LanzouClient {
  _FakeClient() : super(uid: '1');

  final List<int> filePages = [];
  final List<String> filePageFolders = [];

  @override
  Future<({List<LzFolder> folders, List<PathNode> path})> listFolders(
    String folderId,
  ) async {
    // 根目录里放一个子目录，用来测「进入目录」这条路径
    if (folderId == '-1') {
      return (
        folders: [LzFolder(id: 'sub', name: '子目录', desc: '')],
        path: const <PathNode>[],
      );
    }
    return (
      folders: const <LzFolder>[],
      path: [PathNode(id: folderId, name: '子目录')],
    );
  }

  @override
  Future<({List<LzFile> files, bool hasMore})> listFilesPage(
    String folderId,
    int page,
  ) async {
    filePages.add(page);
    filePageFolders.add(folderId);
    // 根目录：没有文件，也没有下一页
    if (folderId == '-1') {
      return (files: const <LzFile>[], hasMore: false);
    }
    if (page == 1) {
      return (
        files: [
          for (var i = 0; i < 3; i++)
            LzFile(id: 'l$i', name: 'f$i.zip', size: '1 M', time: ''),
        ],
        hasMore: true,
      );
    }
    // 第二页空 + hasMore=false：服务端说「到底了」
    return (files: const <LzFile>[], hasMore: false);
  }
}

class _FakeApp extends AppController {
  _FakeApp(this._client);

  final LanzouClient _client;

  @override
  LanzouClient get client => _client;
}

void main() {
  testWidgets('目录内容不满一屏时自动补页：进入即显示「已经到底了」', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    final manager = TransferManager(app);
    addTearDown(app.dispose);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppController>.value(value: app),
          ChangeNotifierProvider<TransferManager>.value(value: manager),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const DrivePage(
            initialFolderId: 'sub',
            initialName: '子目录',
            tabIndex: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 自动补了第二页（不需要用户滑动）
    expect(client.filePages, contains(2));
    // 并且立刻显示「已经到底了」
    expect(find.text('f0.zip'), findsOneWidget);
    expect(find.text('已经到底了'), findsOneWidget);
  });

  // 下拉刷新会清掉目录缓存并强制重新联网拉第一页；这条路径同样要自动补页，
  // 否则刷新后又变成「看起来没到底」。
  testWidgets('下拉刷新后依然自动补页并显示「已经到底了」', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    final manager = TransferManager(app);
    addTearDown(app.dispose);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppController>.value(value: app),
          ChangeNotifierProvider<TransferManager>.value(value: manager),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const DrivePage(
            initialFolderId: 'sub',
            initialName: '子目录',
            tabIndex: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已经到底了'), findsOneWidget);

    // 下拉刷新：清缓存 + 重新拉第一页
    client.filePages.clear();
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1200,
    );
    await tester.pumpAndSettle();

    expect(client.filePages, contains(1));
    expect(client.filePages, contains(2));
    expect(find.text('已经到底了'), findsOneWidget);
  });

  // 真机上最常见的一条路径：从根目录点进子目录（走目录切换流程），
  // 切换期间的补页检查会被 _directorySwitching 挡住，切换结束后必须再补一次。
  testWidgets('从根目录进入子目录后也会自动补页并显示「已经到底了」', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    // 关掉「最近使用」记录：测试环境没有数据库实现，进入目录时不必写库
    app.settings.recentLimit = 0;
    final manager = TransferManager(app);
    addTearDown(app.dispose);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppController>.value(value: app),
          ChangeNotifierProvider<TransferManager>.value(value: manager),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          // 从根目录开始，点进「子目录」验证目录切换这条路径
          home: const DrivePage(tabIndex: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('子目录'), findsOneWidget);

    // 进入子目录：这里会经历 _animateDirectorySwitch + _load
    client.filePages.clear();
    client.filePageFolders.clear();
    await tester.tap(find.text('子目录'));
    await tester.pumpAndSettle();

    expect(
      client.filePageFolders,
      containsAll(<String>['sub']),
      reason: '进入子目录后应该请求该目录的分页',
    );
    expect(client.filePages, contains(2), reason: '内容不满一屏时要自动补第二页');
    expect(find.text('已经到底了'), findsOneWidget);
  });
}
