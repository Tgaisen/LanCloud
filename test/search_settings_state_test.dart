import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/search_options.dart';
import 'package:lancloud/core/search_settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('搜索选项保存后可由新状态实例恢复', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    await store.load();
    final state = SearchSettingsState(store);
    addTearDown(state.dispose);

    expect(state.options.value, SearchOptions.disabled);

    await state.setOptions(
      const SearchOptions(matchCase: true, wholeWord: true, regex: true),
    );
    expect(store.searchMatchCase, isTrue);
    expect(store.searchWholeWord, isTrue);
    expect(store.searchRegex, isTrue);

    final reloaded = SettingsStore();
    await reloaded.load();
    final restored = SearchSettingsState(reloaded);
    addTearDown(restored.dispose);
    expect(
      restored.options.value,
      const SearchOptions(matchCase: true, wholeWord: true, regex: true),
    );
  });

  test('备份恢复写入存储后 refresh 会同步当前状态', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    await store.load();
    final state = SearchSettingsState(store);
    addTearDown(state.dispose);

    await store.applyJson(<String, Object?>{
      'search_match_case': true,
      'search_whole_word': false,
      'search_regex': true,
    });
    state.refresh();

    expect(
      state.options.value,
      const SearchOptions(matchCase: true, regex: true),
    );
  });
}
