import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/transfer_connection_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/request_interval_settings_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(
    () => LanzouClient.requestInterval = const Duration(milliseconds: 300),
  );

  tearDown(
    () => LanzouClient.requestInterval = const Duration(milliseconds: 300),
  );

  testWidgets('网络请求间隔使用 Riverpod 状态，并同步客户端配置', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
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
          home: const Scaffold(body: RequestIntervalSettingsTile()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('100 ms'), findsOneWidget);
    await tester.drag(find.byType(M3ESlider), const Offset(600, 0));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.requestInterval, 1000);
    expect(
      LanzouClient.requestInterval,
      const Duration(milliseconds: 1000),
    );
    expect(state.revision.value, 1);
    expect(find.text('1000 ms'), findsOneWidget);
  });
}
