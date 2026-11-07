import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/transfer_connection_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/auto_start_upload_settings_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('自动开始上传默认开启并可立即关闭', (tester) async {
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
          home: const Scaffold(body: AutoStartUploadSettingsTile()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('自动开始上传'), findsOneWidget);
    expect(find.text('关闭后需在传输列表手动开始上传，上传前可修改任务队列'), findsOneWidget);
    final tile = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    await tester.tap(tile);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.autoStartUploads, isFalse);
    expect(state.revision.value, 1);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
  });
}
