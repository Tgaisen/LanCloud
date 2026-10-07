import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/app_localizations_zh.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/share_folder_page.dart';
import 'package:provider/provider.dart';

/// 记录分页请求的假客户端：第二页固定返回一个文件并到底。
class _FakeClient extends LanzouClient {
  _FakeClient() : super(uid: '0');

  final List<int> calls = [];

  @override
  Future<({List<ShareFileItem> files, bool hasMore})> fetchShareFolderFiles(
    ShareFolderPaging paging,
    int page,
  ) async {
    calls.add(page);
    if (page == 2) {
      return (
        files: [
          ShareFileItem(
            name: 'second-page.txt',
            time: '',
            size: '1 M',
            url: 'https://example.com/b',
          ),
        ],
        hasMore: false,
      );
    }
    return (files: const <ShareFileItem>[], hasMore: false);
  }
}

class _FakeApp extends AppController {
  _FakeApp(this._client);

  final LanzouClient _client;

  @override
  LanzouClient get publicClient => _client;
}

ShareFolderPaging _paging() => ShareFolderPaging(
  base: 'https://example.com',
  referer: 'https://example.com/s/abc',
  fid: '123',
  lx: '2',
  t: '1700000000',
  k: 'abcdefghijklmnop',
);

FolderShareDetail _folder({int firstPageFiles = 20}) => FolderShareDetail(
  name: '测试分享',
  files: [
    for (var i = 0; i < firstPageFiles; i++)
      ShareFileItem(
        name: 'file$i.txt',
        time: '2026-10-01',
        size: '1 M',
        url: 'https://example.com/f$i',
      ),
  ],
  paging: _paging(),
  hasMore: true,
);

Future<void> pumpPage(
  WidgetTester tester, {
  required AppController app,
  required FolderShareDetail folder,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 700);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: ShareFolderPage(
          folder: folder,
          link: 'https://example.com/s/abc',
          pwd: '',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('分享文件夹：解析后只进页面，滑到底才加载下一页', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    addTearDown(app.dispose);
    await pumpPage(tester, app: app, folder: _folder());

    // 首屏已经填满：不应该提前请求下一页
    expect(client.calls, isEmpty);
    expect(find.text('second-page.txt'), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(client.calls, contains(2));
    expect(find.text('second-page.txt'), findsOneWidget);
  });

  testWidgets('分享文件夹：开启「自动加载全部目录内容」后后台补齐全部分页', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client)..settings.loadAllPages = true;
    addTearDown(app.dispose);
    await pumpPage(tester, app: app, folder: _folder());

    expect(client.calls, contains(2));
    // 列表是懒加载的：新一页在屏幕外，先滚到底再确认它已经渲染出来
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('second-page.txt'), findsOneWidget);
  });

  testWidgets('分享文件夹：长列表只构建可见条目（懒加载）', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    addTearDown(app.dispose);
    await pumpPage(tester, app: app, folder: _folder(firstPageFiles: 400));

    // 400 条里只构建屏幕附近的少量条目，而不是全部常驻
    expect(find.byType(Md3ListItem).evaluate().length, lessThan(40));
    expect(client.calls, isEmpty);
  });

  testWidgets('分享文件夹：第一页不满一屏时自动补页，不留常驻的加载转圈', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    addTearDown(app.dispose);
    // 只有 3 个文件：内容明显不足一屏（修复前 maxScrollExtent > 0 时不会补页，
    // 底部“加载下一页”的转圈会一直停着，直到用户滑动）
    await pumpPage(tester, app: app, folder: _folder(firstPageFiles: 3));

    expect(client.calls, contains(2));
    expect(find.text('second-page.txt'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(AppLocalizationsZh().reachedEnd), findsOneWidget);
  });

  testWidgets('分享文件夹：搜索时不显示加载转圈，改为提示结果可能不全', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    addTearDown(app.dispose);
    // 首页有 20 个文件、还有下一页没加载：搜索只在已加载内容里过滤
    await pumpPage(tester, app: app, folder: _folder());
    expect(client.calls, isEmpty);

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    // 只匹配 file0 一条：尾部提示会渲染在可见区域内
    await tester.enterText(find.byType(TextField), 'file0');
    await tester.pumpAndSettle();

    // 未全部加载 → 提示可能不全，而不是「加载下一页」的转圈
    expect(find.text(AppLocalizationsZh().searchIncomplete), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // 搜索期间不会继续补页（滑动到搜索结果的底部也不会请求下一页）
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(client.calls, isEmpty);
    expect(find.text(AppLocalizationsZh().searchIncomplete), findsOneWidget);
  });
}
