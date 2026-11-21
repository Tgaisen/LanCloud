import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/dynamic_color_support.dart';
import 'package:lancloud/core/platform_capabilities.dart';

class _FakeDynamicColorProbe implements DynamicColorProbe {
  _FakeDynamicColorProbe({this.core = false, this.accent = false, this.error});

  final bool core;
  final bool accent;
  final Object? error;
  final List<String> calls = [];

  @override
  Future<bool> hasCorePalette() async {
    calls.add('core');
    final currentError = error;
    if (currentError != null) throw currentError;
    return core;
  }

  @override
  Future<bool> hasAccentColor() async {
    calls.add('accent');
    final currentError = error;
    if (currentError != null) throw currentError;
    return accent;
  }
}

void main() {
  group('DynamicColorSupport', () {
    test('wallpaper 应该优先 CorePalette，并在失败后回退 AccentColor', () async {
      final coreProbe = _FakeDynamicColorProbe(core: true);
      expect(
        await DynamicColorSupport.isSupported(
          refresh: true,
          capabilities: PlatformCapabilities.android,
          probe: coreProbe,
        ),
        isTrue,
      );
      expect(coreProbe.calls, ['core']);

      final accentProbe = _FakeDynamicColorProbe(accent: true);
      expect(
        await DynamicColorSupport.isSupported(
          refresh: true,
          capabilities: PlatformCapabilities.android,
          probe: accentProbe,
        ),
        isTrue,
      );
      expect(accentProbe.calls, ['core', 'accent']);
    });

    test('systemAccent 应该只查询 AccentColor', () async {
      final probe = _FakeDynamicColorProbe(accent: true);
      expect(
        await DynamicColorSupport.isSupported(
          refresh: true,
          capabilities: PlatformCapabilities.windows,
          probe: probe,
        ),
        isTrue,
      );
      expect(probe.calls, ['accent']);
    });

    test('none 来源应该直接关闭且不调用插件', () async {
      for (final capabilities in [
        PlatformCapabilities.ios,
        PlatformCapabilities.macOS,
        PlatformCapabilities.linux,
        PlatformCapabilities.unsupported,
      ]) {
        final probe = _FakeDynamicColorProbe(core: true, accent: true);
        expect(
          await DynamicColorSupport.isSupported(
            refresh: true,
            capabilities: capabilities,
            probe: probe,
          ),
          isFalse,
        );
        expect(probe.calls, isEmpty);
      }
    });

    test('插件异常应该返回 false', () async {
      final probe = _FakeDynamicColorProbe(
        error: PlatformException(code: 'unsupported'),
      );
      expect(
        await DynamicColorSupport.isSupported(
          refresh: true,
          capabilities: PlatformCapabilities.android,
          probe: probe,
        ),
        isFalse,
      );
    });

    test('相同来源应该复用缓存，切换来源后重新探测', () async {
      final first = _FakeDynamicColorProbe(core: true);
      expect(
        await DynamicColorSupport.isSupported(
          refresh: true,
          capabilities: PlatformCapabilities.android,
          probe: first,
        ),
        isTrue,
      );

      final cachedProbe = _FakeDynamicColorProbe();
      expect(
        await DynamicColorSupport.isSupported(
          capabilities: PlatformCapabilities.android,
          probe: cachedProbe,
        ),
        isTrue,
      );
      expect(cachedProbe.calls, isEmpty);

      final windowsProbe = _FakeDynamicColorProbe(accent: true);
      expect(
        await DynamicColorSupport.isSupported(
          capabilities: PlatformCapabilities.windows,
          probe: windowsProbe,
        ),
        isTrue,
      );
      expect(windowsProbe.calls, ['accent']);
    });
  });
}
