import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/update/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_test_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('测试容器通过 provider override 注入网络假数据', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsStore()..updateChannel = 'stable';
    var calls = 0;
    final container = createUpdateContainer(
      settings: settings,
      fetch: () async {
        calls++;
        return const [];
      },
    );
    addTearDown(container.dispose);
    final service = container.read(updateServiceProvider.notifier);
    await service.initialize();

    expect(await service.check(), isTrue);
    expect(calls, 1);
  });
}
