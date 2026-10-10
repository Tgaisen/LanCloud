import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/favorites_page.dart';
import 'package:lancloud/ui/share_folder_page.dart';
import 'package:lancloud/ui/transfers_page.dart';
import 'package:provider/provider.dart';

/// 空白提示（暂无任务 / 还没有收藏 …）应该在可见区域里居中显示，
/// 并且**不可滚动**：之前末尾多补了一截底栏 / 导航栏留白，
/// 提示能往下滑出去一屏。
void main() {
  /// 模拟带系统导航栏的手机（底部 inset 非 0 才会暴露这个问题）。
  void useBottomInset(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = FakeViewPadding(bottom: 48);
    tester.view.viewPadding = FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
  }

  double maxScrollExtent(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position
      .maxScrollExtent;

  testWidgets('传输页空状态居中且不可滚动', (tester) async {
    useBottomInset(tester);
    final app = AppController();
    final manager = TransferManager(app);
    addTearDown(app.dispose);
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
          home: const TransfersPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无上传任务'), findsOneWidget);
    expect(maxScrollExtent(tester), 0);
  });

  testWidgets('收藏页空状态居中且不可滚动', (tester) async {
    useBottomInset(tester);
    final app = AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const FavoritesPage(tabIndex: 3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无收藏内容'), findsOneWidget);
    expect(maxScrollExtent(tester), 0);
  });

  testWidgets('分享浏览页空状态居中且不可滚动', (tester) async {
    useBottomInset(tester);
    final app = AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: ShareFolderPage(
            folder: FolderShareDetail(name: '空分享'),
            link: 'https://example.com/share',
            pwd: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('这个分享里没有文件'), findsOneWidget);
    expect(maxScrollExtent(tester), 0);
  });
}
