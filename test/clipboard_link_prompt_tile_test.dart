import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/data/settings_store_provider.dart';
import 'package:lancloud/core/language_clipboard_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/clipboard_link_prompt_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('复制链接提示设置行不依赖 AppController', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsStore();
    final container = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: ClipboardLinkPromptTile(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final switchTile = find.byType(SwitchListTile);
    final settingsState = container.read(languageClipboardSettingsStateProvider);
    expect(tester.widget<SwitchListTile>(switchTile).value, isFalse);
    await tester.tap(switchTile);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(settings.clipboardLinkPrompt, isTrue);
    expect(settingsState.clipboardLinkPrompt, isTrue);
    expect(settingsState.revision.value, 1);
    expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);
  });
}
