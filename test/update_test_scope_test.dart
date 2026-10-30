import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/update/release_info.dart';
import 'package:lancloud/core/update/update_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<List<ReleaseInfo>> _noReleases() async => const [];

/// 创建只包含更新试点依赖的测试容器。
ProviderContainer createUpdateContainer({
  required SettingsStore settings,
  UpdateFetcher fetch = _noReleases,
  UpdateClock? clock,
}) {
  return ProviderContainer(
    overrides: [
      updateSettingsProvider.overrideWithValue(settings),
      updateFetcherProvider.overrideWithValue(fetch),
      if (clock != null) updateClockProvider.overrideWithValue(clock),
    ],
  );
}

/// 同时提供旧 Provider 与 Riverpod 试点作用域。
Widget updateTestTree({
  required AppController app,
  required ProviderContainer container,
  required Widget child,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: ChangeNotifierProvider<AppController>.value(
      value: app,
      child: child,
    ),
  );
}

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
