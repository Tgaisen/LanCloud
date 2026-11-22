import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'search_options.dart';

/// 三个名称搜索页面共享的搜索选项状态。
final class SearchSettingsState {
  SearchSettingsState(this.store)
    : options = ValueNotifier(
        SearchOptions(
          matchCase: store.searchMatchCase,
          wholeWord: store.searchWholeWord,
          regex: store.searchRegex,
        ),
      );

  final SettingsStore store;
  final ValueNotifier<SearchOptions> options;

  Future<void> setOptions(SearchOptions next) async {
    final previous = options.value;
    if (previous == next) return;
    if (previous.matchCase != next.matchCase) {
      await store.setSearchMatchCase(next.matchCase);
    }
    if (previous.wholeWord != next.wholeWord) {
      await store.setSearchWholeWord(next.wholeWord);
    }
    if (previous.regex != next.regex) {
      await store.setSearchRegex(next.regex);
    }
    options.value = next;
  }

  /// 设置加载或备份恢复后，从唯一存储重新同步。
  void refresh() {
    final next = SearchOptions(
      matchCase: store.searchMatchCase,
      wholeWord: store.searchWholeWord,
      regex: store.searchRegex,
    );
    if (options.value != next) options.value = next;
  }

  void dispose() => options.dispose();
}

final searchSettingsStateProvider = Provider<SearchSettingsState>((ref) {
  throw StateError('searchSettingsStateProvider 必须由应用入口覆盖');
});
