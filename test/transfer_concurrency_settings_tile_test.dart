import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/transfer_connection_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/transfer_concurrency_settings_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<TransferConnectionSettingsState> _pump(
  WidgetTester tester,
  SettingsStore store,
  TransferConcurrencySetting setting,
) async {
  final state = TransferConnectionSettingsState(store);
  final container = ProviderContainer(
    overrides: [
      transferConnectionSettingsStateProvider.overrideWithValue(state),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(body: TransferConcurrencySettingsTile(setting: setting)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('上传并发数使用 Riverpod 状态，松手后局部刷新', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    final state = await _pump(
      tester,
      store,
      TransferConcurrencySetting.uploads,
    );

    await tester.drag(find.byType(M3ESlider), const Offset(600, 0));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.maxUploads, 3);
    expect(state.revision.value, 1);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('下载并发数使用 Riverpod 状态，松手后局部刷新', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    final state = await _pump(
      tester,
      store,
      TransferConcurrencySetting.downloads,
    );

    await tester.drag(find.byType(M3ESlider), const Offset(600, 0));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.maxDownloads, 5);
    expect(state.revision.value, 1);
    expect(find.text('5'), findsOneWidget);
  });
}
