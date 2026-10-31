import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/app_runtime_state.dart';

void main() {
  test('AppController 运行时字段转发到同一 AppRuntimeState', () {
    final runtime = AppRuntimeState();
    final app = AppController(runtimeState: runtime);
    addTearDown(app.dispose);

    expect(app.ready, isFalse);
    app.ready = true;
    expect(runtime.ready.value, isTrue);

    runtime.secureStorageNeedsReauthentication.value = true;
    expect(app.secureStorageNeedsReauthentication, isTrue);

    app.systemReduceMotion = true;
    expect(runtime.systemReduceMotion.value, isTrue);
  });

  test('appRuntimeStateProvider 使用覆盖的同一实例', () {
    final runtime = AppRuntimeState();
    addTearDown(runtime.dispose);
    final container = ProviderContainer(
      overrides: [appRuntimeStateProvider.overrideWithValue(runtime)],
    );
    addTearDown(container.dispose);

    expect(container.read(appRuntimeStateProvider), same(runtime));
  });
}
