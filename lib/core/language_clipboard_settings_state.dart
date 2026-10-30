import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

/// 界面语言与复制分享链接提示的明确读写入口。
class LanguageClipboardSettingsState {
  const LanguageClipboardSettingsState(this.store);

  final SettingsStore store;

  String get language => store.language;
  bool get clipboardLinkPrompt => store.clipboardLinkPrompt;

  Future<void> setLanguage(String value) => store.setLanguage(value);
  Future<void> setClipboardLinkPrompt(bool value) =>
      store.setClipboardLinkPrompt(value);
}

final languageClipboardSettingsStateProvider =
    Provider<LanguageClipboardSettingsState>(
      (ref) => LanguageClipboardSettingsState(
        ref.watch(settingsStoreProvider),
      ),
    );
