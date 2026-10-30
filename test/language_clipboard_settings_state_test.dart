import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/language_clipboard_settings_state.dart';
import 'package:lancloud/core/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('LanguageClipboardSettingsState 读写语言与剪贴板提示', () async {
    final settings = SettingsStore();
    final state = LanguageClipboardSettingsState(settings);

    await state.setLanguage('en');
    await state.setClipboardLinkPrompt(true);

    expect(state.language, 'en');
    expect(state.clipboardLinkPrompt, isTrue);
    expect(settings.language, 'en');
    expect(settings.clipboardLinkPrompt, isTrue);
  });

  test('AppController 旧 API 保持通知行为', () async {
    final app = AppController(settingsState: SettingsState());
    addTearDown(app.dispose);
    var notifications = 0;
    app.addListener(() => notifications += 1);

    await app.setLanguage('en');
    await app.setClipboardLinkPrompt(true);

    expect(app.settings.language, 'en');
    expect(app.settings.clipboardLinkPrompt, isTrue);
    expect(notifications, 2);
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
      identical(
        container.read(languageClipboardSettingsStateProvider),
        state,
      ),
      isTrue,
    );
  });
}
