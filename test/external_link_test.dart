import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/external_link.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// 记录 launchUrl 的假实现（落回系统默认方式时的断言用）。
class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = [];

  @override
  final LinkDelegate? linkDelegate = null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  const channel = MethodChannel('lancloud/external_link');
  late _FakeUrlLauncher launcher;
  late UrlLauncherPlatform originalLauncher;

  setUp(() {
    originalLauncher = UrlLauncherPlatform.instance;
    launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = originalLauncher;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // flutter test 里 defaultTargetPlatform 固定为 Android（见 platform_support.dart）
  testWidgets('Android：原生侧用 Custom Tabs 打开时不再调 url_launcher', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      expect(call.arguments, {'url': 'https://example.com'});
      return true;
    });

    expect(await openExternalUrl(Uri.parse('https://example.com')), isTrue);
    expect(calls, ['openCustomTab']);
    expect(launcher.launched, isEmpty);
  });

  testWidgets('Android：原生侧判定不支持时落回系统默认方式', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => false,
    );

    expect(await openExternalUrl(Uri.parse('https://example.com')), isTrue);
    expect(launcher.launched, ['https://example.com']);
  });

  testWidgets('Android：通道未注册（旧原生侧）同样落回系统默认方式', (tester) async {
    // 不注册处理器：invokeMethod 抛 MissingPluginException，应被吞掉后落回。
    // 消息真的走一遍引擎（没有假处理器），要用 runAsync 跑真实异步。
    final opened = await tester.runAsync(
      () => openExternalUrl(Uri.parse('https://example.com')),
    );
    expect(opened, isTrue);
    expect(launcher.launched, ['https://example.com']);
  });

  testWidgets('桌面端：不经过原生通道，直接交给系统默认程序', (tester) async {
    // 复位要写在测试体内：框架在 addTearDown 之前就会校验调试变量已还原
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      var channelCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        channelCalls++;
        return true;
      });

      expect(await openExternalUrl(Uri.parse('https://example.com')), isTrue);
      expect(channelCalls, 0);
      expect(launcher.launched, ['https://example.com']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
