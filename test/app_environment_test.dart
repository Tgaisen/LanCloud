import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';

void main() {
  test('应用环境唯一组装状态对象，控制器仅转发同一实例', () {
    final app = AppController();
    addTearDown(app.dispose);
    final environment = app.environment;

    expect(app.db, same(environment.db));
    expect(app.navigation, same(environment.navigation));
    expect(app.drive, same(environment.drive));
    expect(app.accountState, same(environment.accountState));
    expect(app.settingsState, same(environment.settingsState));
    expect(app.runtimeState, same(environment.runtimeState));
    expect(app.clientRegistry, same(environment.clientRegistry));
    expect(app.accountLogin, same(environment.accountLogin));
    expect(app.accountSession, same(environment.accountSession));
    expect(app.updateSettings, same(environment.updateSettings));
    expect(app.notificationSettings, same(environment.notificationSettings));
    expect(
      app.navigationAppearanceSettings,
      same(environment.navigationAppearanceSettings),
    );
    expect(app.themeSettings, same(environment.themeSettings));
    expect(
      app.transferConnectionSettings,
      same(environment.transferConnectionSettings),
    );
    expect(app.listHomeSettings, same(environment.listHomeSettings));
    expect(
      app.languageClipboardSettings,
      same(environment.languageClipboardSettings),
    );
    expect(app.cachePageSettings, same(environment.cachePageSettings));
    expect(
      app.downloadDirectorySettings,
      same(environment.downloadDirectorySettings),
    );
  });
}
