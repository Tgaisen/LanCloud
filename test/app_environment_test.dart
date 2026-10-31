import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';

void main() {
  test('应用环境中的设置子组共享同一存储实例', () {
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    final settings = environment.settingsState.store;

    expect(environment.updateSettings.store, same(settings));
    expect(environment.notificationSettings.store, same(settings));
    expect(environment.navigationAppearanceSettings.store, same(settings));
    expect(environment.themeSettings.store, same(settings));
    expect(environment.transferConnectionSettings.store, same(settings));
    expect(environment.listHomeSettings.store, same(settings));
    expect(environment.languageClipboardSettings.store, same(settings));
    expect(environment.cachePageSettings.store, same(settings));
    expect(environment.downloadDirectorySettings.store, same(settings));

    expect(
      environment.accountLogin.accountState,
      same(environment.accountState),
    );
    expect(
      environment.accountSession.accountState,
      same(environment.accountState),
    );
    expect(environment.accountLogin.clients, same(environment.clientRegistry));
    expect(
      environment.accountSession.clients,
      same(environment.clientRegistry),
    );
  });
}
