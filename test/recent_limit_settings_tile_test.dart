import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/list_home_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/recent_limit_settings_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('最近使用上限使用 Riverpod 状态，并在松手后裁剪', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    final trims = <(String, int)>[];
    final state = ListHomeSettingsState(
      store,
      trimRecents: (uid, limit) async => trims.add((uid, limit)),
      activeUid: () => 'account-1',
    );
    final container = ProviderContainer(
      overrides: [listHomeSettingsStateProvider.overrideWithValue(state)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: RecentLimitSettingsTile()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('50 条'), findsOneWidget);
    await tester.drag(find.byType(M3ESlider), const Offset(-600, 0));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.recentLimit, 0);
    expect(trims, [('account-1', 0)]);
    expect(state.revision.value, 1);
    expect(find.text('不记录'), findsOneWidget);
  });
}
