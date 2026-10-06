import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/dynamic_color_support.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 动态取色插件的通道：返回非空即表示设备支持动态取色。
const _channel = MethodChannel('io.material.plugins/dynamic_color');

void mockDynamicColorSupport({required bool supported}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'getCorePalette') {
          // 真机插件返回的是 IntArray（编解码后为 Int32List）；
          // CorePalette 需要 5 组 × 13 个色调 = 65 个颜色
          return supported
              ? Int32List.fromList(List<int>.filled(65, 0x2E6BE6))
              : null;
        }
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('设备支持动态取色且用户没选过：自动开启并记为用户已选', () async {
    mockDynamicColorSupport(supported: true);
    // 支持探测带静态缓存，先按本次 mock 刷新，避免受其它用例影响
    await DynamicColorSupport.isSupported(refresh: true);
    final app = AppController();
    addTearDown(app.dispose);
    await app.settings.load();

    await app.autoEnableDynamicColorIfSupported();

    expect(app.settings.dynamicColor, isTrue);
    expect(app.settings.dynamicColorChosen, isTrue);
  });

  test('设备不支持动态取色：保持关闭', () async {
    mockDynamicColorSupport(supported: false);
    await DynamicColorSupport.isSupported(refresh: true);
    final app = AppController();
    addTearDown(app.dispose);
    await app.settings.load();

    await app.autoEnableDynamicColorIfSupported();

    expect(app.settings.dynamicColor, isFalse);
    expect(app.settings.dynamicColorChosen, isFalse);
  });

  test('用户手动关掉后：不再自动开启', () async {
    SharedPreferences.setMockInitialValues({
      'dynamic_color': false,
      'dynamic_color_chosen': true,
    });
    mockDynamicColorSupport(supported: true);
    await DynamicColorSupport.isSupported(refresh: true);
    final app = AppController();
    addTearDown(app.dispose);
    await app.settings.load();

    await app.autoEnableDynamicColorIfSupported();

    expect(app.settings.dynamicColor, isFalse);
  });
}
