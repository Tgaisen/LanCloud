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

  @override
  Future<({List<LzFolder> folders, List<PathNode> path})> listFolders(
    String folderId,
  ) async => (
    folders: [LzFolder(id: 'f1', name: '空文件夹', desc: '')],
    path: const <PathNode>[],
  );

  @override
  Future<({List<LzFile> files, bool hasMore})> listFilesPage(
    String folderId,
    int page,
  ) async {
    filePages.add(page);
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
          home: const DrivePage(tabIndex: 0),
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
}
