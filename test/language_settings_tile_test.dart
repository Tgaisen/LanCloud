import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/language_clipboard_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/language_settings_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('语言设置行使用 Riverpod 状态，并局部刷新', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    final state = LanguageClipboardSettingsState(store);
    final container = ProviderContainer(
      overrides: [
        languageClipboardSettingsStateProvider.overrideWithValue(state),
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
          home: const Scaffold(body: LanguageSettingsTile()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('跟随系统'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '语言'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.language, 'en');
    expect(state.revision.value, 1);
    expect(find.text('English'), findsOneWidget);
  });
}
