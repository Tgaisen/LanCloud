import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/data/account_store_provider.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/data/settings_store_provider.dart';

void main() {
  test('settingsStoreProvider 提供入口注入的同一设置存储', () {
    final settings = SettingsStore();
    final container = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    expect(identical(container.read(settingsStoreProvider), settings), isTrue);
  });

  test('accountStoreProvider 提供入口注入的同一账号存储', () {
    final accounts = AccountStore();
    final container = ProviderContainer(
      overrides: [accountStoreProvider.overrideWithValue(accounts)],
    );
    addTearDown(container.dispose);

    expect(identical(container.read(accountStoreProvider), accounts), isTrue);
  });
}
