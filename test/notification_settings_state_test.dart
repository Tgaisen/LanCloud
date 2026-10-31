import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/notification_settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('NotificationSettingsState 读写原 SettingsStore 的通知开关', () async {
    final settings = SettingsStore();
    final state = NotificationSettingsState(settings);

    await state.setNotifyProgress(false);
    await state.setNotifyDone(false);

    expect(state.revision.value, 2);
    expect(state.notifyProgress, isFalse);
    expect(state.notifyDone, isFalse);
    expect(settings.notifyProgress, isFalse);
    expect(settings.notifyDone, isFalse);
  });

  test('notificationSettingsStateProvider 可被共享实例覆盖', () {
    final state = NotificationSettingsState(SettingsStore());
    final container = ProviderContainer(
      overrides: [
        notificationSettingsStateProvider.overrideWithValue(state),
      ],
    );
    addTearDown(container.dispose);

    expect(
      identical(container.read(notificationSettingsStateProvider), state),
      isTrue,
    );
  });
}
