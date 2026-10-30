import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

/// 界面语言与复制分享链接提示的明确读写入口。
class LanguageClipboardSettingsState {
  LanguageClipboardSettingsState(this.store);

  final SettingsStore store;
  final ValueNotifier<int> revision = ValueNotifier(0);

  String get language => store.language;
  bool get clipboardLinkPrompt => store.clipboardLinkPrompt;

  Future<void> setLanguage(String value) async {
    await store.setLanguage(value);
    revision.value += 1;
  }

  Future<void> setClipboardLinkPrompt(bool value) async {
    await store.setClipboardLinkPrompt(value);
    revision.value += 1;
  }
}

final languageClipboardSettingsStateProvider =
    Provider<LanguageClipboardSettingsState>(
      (ref) => LanguageClipboardSettingsState(
        ref.watch(settingsStoreProvider),
      ),
    );
