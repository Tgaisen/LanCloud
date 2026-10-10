import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/favorites_page.dart';
import 'package:provider/provider.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  testWidgets('收藏视图可独立打开，空收藏时显示提示', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const FavoritesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('暂无收藏内容'), findsOneWidget);
    app.dispose();
  });

  testWidgets('独立页面：多选时返回只退出多选，不退出页面', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      // 独立打开时外壳传的就是同一个 tabIndex（见 app.dart
                      // 的 _openView），这里保持一致，避免判断错页面形态
                      builder: (_) => const FavoritesPage(tabIndex: 3),
                    ),
                  ),
                  child: const Text('打开收藏'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();

    // 空收藏也能进多选：菜单里的「多选」
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    // 图标与传输页顶栏的多选入口一致（Checklist）
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.widgetWithText(ListTile, '多选'),
              matching: find.byType(Icon),
            ),
          )
          .icon,
      Icons.checklist,
    );
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    expect(app.selectionMode, isTrue);

    // 第一次返回：退出多选，页面还在
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(app.selectionMode, isFalse);
    expect(find.byType(FavoritesPage), findsOneWidget);

    // 再返回一次才退出页面
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesPage), findsNothing);
    app.dispose();
  });

  // 搜索框打开时返回键先退出搜索（与分享浏览页一致），再退出页面
  testWidgets('独立页面：搜索时返回只退出搜索，不退出页面', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const FavoritesPage(tabIndex: 3),
                    ),
                  ),
                  child: const Text('打开收藏'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();

    // 打开搜索：搜索框是带过渡淡入的
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(TextField), findsOneWidget);
    await tester.pumpAndSettle();

    // 第一次返回：只退出搜索，页面还在
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FavoritesPage), findsOneWidget);

    // 再返回一次才退出页面
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesPage), findsNothing);
    app.dispose();
  });
}
