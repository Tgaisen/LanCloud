import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/platform_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lancloud/system');

  test('Android SDK 级别：读取 + 缓存，并按 Android 10 判定混合合成', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          if (call.method != 'androidSdkInt') return null;
          return 28; // Android 9：混合合成应当关闭
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    // 还没读到版本：保持插件默认（启用）
    expect(PlatformSupport.useHybridComposition, isTrue);

    expect(await PlatformSupport.loadAndroidSdkInt(), 28);
    expect(calls, 1);
    expect(PlatformSupport.androidSdkIntCached, 28);
    // Android 9 上按官方建议关掉混合合成
    expect(PlatformSupport.useHybridComposition, isFalse);

    // 再读一次走缓存，不再走通道
    expect(await PlatformSupport.loadAndroidSdkInt(), 28);
    expect(calls, 1);
  });
}
