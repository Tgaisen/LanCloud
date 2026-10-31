import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_runtime_state.dart';

void main() {
  test('AppRuntimeState 保存运行时应用信号', () {
    final runtime = AppRuntimeState();
    addTearDown(runtime.dispose);

    expect(runtime.ready.value, isFalse);
    runtime.ready.value = true;
    expect(runtime.ready.value, isTrue);

    runtime.secureStorageNeedsReauthentication.value = true;
    expect(runtime.secureStorageNeedsReauthentication.value, isTrue);

    runtime.systemReduceMotion.value = true;
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
