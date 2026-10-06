import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:provider/provider.dart';

/// 独立页面（TopBarOverlayScaffold + controller）：
/// 点顶栏空白处回到列表顶部，与网盘页一致。
Future<ScrollController> pumpPage(WidgetTester tester) async {
  final controller = ScrollController();
  final app = AppController();
  await tester.pumpWidget(
    MultiProvider(
      providers: [ChangeNotifierProvider<AppController>.value(value: app)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: TopBarOverlayScaffold(
          controller: controller,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            scrolledUnderElevation: 0,
            title: const Text('设置'),
          ),
          slivers: [
            SliverList.builder(
              itemCount: 60,
              itemBuilder: (context, index) =>
                  SizedBox(height: 56, child: Text('第 $index 项')),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('点顶栏空白处回到列表顶部', (tester) async {
    final controller = await pumpPage(tester);

    controller.jumpTo(600);
    await tester.pumpAndSettle();
    expect(controller.offset, 600);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('没传 controller 的页面不响应（保持原有行为）', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider<AppController>.value(value: app)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: TopBarOverlayScaffold(
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              scrolledUnderElevation: 0,
              title: const Text('设置'),
            ),
            slivers: [
              SliverList.builder(
                itemCount: 60,
                itemBuilder: (context, index) =>
                    SizedBox(height: 56, child: Text('第 $index 项')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 点顶栏不应抛异常，页面保持正常可滚动
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('第 0 项'), findsOneWidget);
  });
}
