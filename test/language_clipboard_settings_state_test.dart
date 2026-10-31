import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/language_clipboard_settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('LanguageClipboardSettingsState 读写语言与剪贴板提示', () async {
    final settings = SettingsStore();
    final state = LanguageClipboardSettingsState(settings);

    await state.setLanguage('en');
    await state.setClipboardLinkPrompt(true);
    state.refresh();

    expect(state.revision.value, 3);
    expect(state.language, 'en');
    expect(state.clipboardLinkPrompt, isTrue);
    expect(settings.language, 'en');
    expect(settings.clipboardLinkPrompt, isTrue);
  });

  test('languageClipboardSettingsStateProvider 可被共享实例覆盖', () {
    final state = LanguageClipboardSettingsState(SettingsStore());
    final container = ProviderContainer(
      overrides: [
        languageClipboardSettingsStateProvider.overrideWithValue(state),
      ],
    );
    addTearDown(container.dispose);

    expect(
      identical(container.read(languageClipboardSettingsStateProvider), state),
      isTrue,
    );
  });
}
