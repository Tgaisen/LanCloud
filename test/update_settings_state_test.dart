import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
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
