import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';

import 'package:lancloud/l10n/delegates.dart';

Widget host(AppEnvironment environment, Widget home) => ProviderScope(
  overrides: [
    navigationAppearanceSettingsStateProvider.overrideWithValue(
      environment.navigationAppearanceSettings,
    ),
    navigationStateProvider.overrideWithValue(environment.navigation),
  ],
  child: MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: home,
  ),
);

/// 独立页面（TopBarOverlayScaffold + controller）：
/// 点顶栏空白处回到列表顶部，与网盘页一致。
Future<ScrollController> pumpPage(WidgetTester tester) async {
  final controller = ScrollController();
  final environment = AppEnvironment();
  addTearDown(environment.dispose);
  await tester.pumpWidget(
    host(
      environment,
      TopBarOverlayScaffold(
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
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    await tester.pumpWidget(
      host(
        environment,
        TopBarOverlayScaffold(
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
    );
    await tester.pumpAndSettle();

    // 点顶栏不应抛异常，页面保持正常可滚动
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('第 0 项'), findsOneWidget);
  });
}
