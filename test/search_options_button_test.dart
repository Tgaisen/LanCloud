import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/search_options.dart';
import 'package:lancloud/core/search_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/search_options_button.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('搜索选项按钮使用 Tune 并展示三个默认关闭的复选项', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    await store.load();
    final settings = SearchSettingsState(store);
    addTearDown(settings.dispose);
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(settings));
    final button = find.byTooltip('搜索选项');
    expect(button, findsOneWidget);
    expect(find.byIcon(app_icons.Icons.tune), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();

    for (final label in ['区分大小写', '全字匹配', '正则表达式']) {
      final row = tester.widget<M3eMenuRow>(
        find.ancestor(of: find.text(label), matching: find.byType(M3eMenuRow)),
      );
      expect(row.selected, isFalse, reason: label);
    }

    await tester.tap(find.text('区分大小写'));
    await tester.tap(find.text('全字匹配'));
    await tester.tap(find.text('正则表达式'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(
      settings.options.value,
      const SearchOptions(matchCase: true, wholeWord: true, regex: true),
    );
    for (final label in ['区分大小写', '全字匹配', '正则表达式']) {
      final row = tester.widget<M3eMenuRow>(
        find.ancestor(of: find.text(label), matching: find.byType(M3eMenuRow)),
      );
      expect(row.selected, isTrue, reason: label);
    }

    final reloaded = SearchSettingsState(SettingsStore());
    addTearDown(reloaded.dispose);
    await reloaded.store.load();
    reloaded.refresh();
    expect(
      reloaded.options.value,
      const SearchOptions(matchCase: true, wholeWord: true, regex: true),
    );
  });

  testWidgets('搜索选项按钮与标准 AppBar 按钮尺寸一致', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    await store.load();
    final settings = SearchSettingsState(store);
    addTearDown(settings.dispose);

    await tester.pumpWidget(_host(settings, leadingNormalAction: true));

    expect(
      tester.getSize(find.byTooltip('搜索选项')),
      tester.getSize(find.byTooltip('菜单')),
    );
  });
}

Widget _host(SearchSettingsState settings, {bool leadingNormalAction = false}) {
  return MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        actions: [
          if (leadingNormalAction)
            IconButton(
              tooltip: '菜单',
              icon: const Icon(Icons.more_vert),
              onPressed: () {},
            ),
          SearchOptionsButton(settings: settings),
        ],
      ),
    ),
  );
}
