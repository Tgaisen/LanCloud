import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/account_state.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/data/account_store_provider.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/data/settings_store_provider.dart';
import 'package:lancloud/core/settings_state.dart';

void main() {
  test('settingsStoreProvider 提供入口注入的同一设置存储', () {
    final settings = SettingsStore();
    final settingsState = SettingsState(store: settings);
    final container = ProviderContainer(
      overrides: [settingsStateProvider.overrideWithValue(settingsState)],
    );
    addTearDown(container.dispose);

    expect(identical(container.read(settingsStoreProvider), settings), isTrue);
  });

  test('accountStoreProvider 从唯一 AccountState 派生账号存储', () {
    final accounts = AccountStore();
    final accountState = AccountState(store: accounts);
    final container = ProviderContainer(
      overrides: [accountStateProvider.overrideWithValue(accountState)],
    );
    addTearDown(container.dispose);

    expect(identical(container.read(accountStoreProvider), accounts), isTrue);
  });
}
