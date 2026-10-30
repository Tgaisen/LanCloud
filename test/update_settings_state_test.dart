import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/settings_state.dart';
import 'package:lancloud/core/update/update_settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('UpdateSettingsState 读写原 SettingsStore 的更新设置', () async {
    final settings = SettingsStore();
    final state = UpdateSettingsState(settings);

    await state.setChannel('stable');
    await state.setAutoCheck(false);

    expect(state.revision.value, 2);
    expect(state.channel, 'stable');
    expect(state.autoCheck, isFalse);
    expect(settings.updateChannel, 'stable');
    expect(settings.updateAutoCheck, isFalse);
  });

  test('AppController 旧更新设置 API 保持通知行为', () async {
    final settingsState = SettingsState();
    final app = AppController(settingsState: settingsState);
    addTearDown(app.dispose);
    var notifications = 0;
    app.addListener(() => notifications += 1);

    await app.setUpdateChannel('stable');
    await app.setUpdateChannel('stable');
    await app.setUpdateAutoCheck(false);

    expect(app.settings.updateChannel, 'stable');
    expect(app.settings.updateAutoCheck, isFalse);
    expect(notifications, 2);
  });

  test('updateSettingsStateProvider 可以被应用共享实例覆盖', () {
    final state = UpdateSettingsState(SettingsStore());
    final container = ProviderContainer(
      overrides: [updateSettingsStateProvider.overrideWithValue(state)],
    );
    addTearDown(container.dispose);

    expect(
      identical(container.read(updateSettingsStateProvider), state),
      isTrue,
    );
  });
}
