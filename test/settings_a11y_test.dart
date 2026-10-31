import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/system_motion.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/app_localizations_zh.dart';
import 'package:lancloud/ui/reduce_motion.dart';
import 'package:lancloud/ui/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'update_test_scope_test.dart';

/// 文案以中文本地化为准，避免改文案就要改测试。
final _zh = AppLocalizationsZh();

/// 记录 launchUrl 的假实现（「反馈」按钮的 mailto 断言用）。
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

late _FakeUrlLauncher _launcher;
late UrlLauncherPlatform _originalLauncher;

Future<AppEnvironment> _pumpSettings(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final environment = AppEnvironment();
  addTearDown(environment.dispose);
  await tester.pumpWidget(
    appEnvironmentTestTree(
      environment: environment,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        // 无障碍设置项都在「行为与权限」大类页里
        home: const SettingsCategoryPage(
          category: SettingsCategory.behaviorPermissions,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return environment;
}

Future<void> _scrollTo(WidgetTester tester, String text) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(find.text(text), 400, scrollable: scrollable);
  // 顶栏是浮层、不占布局：往回拖一段让目标落在顶栏下方（同其它设置页测试）
  await tester.drag(scrollable, const Offset(0, 120));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _originalLauncher = UrlLauncherPlatform.instance;
    _launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = _launcher;
    // 全局动效状态在测试之间复位
    SystemMotion.motionMode.value = 'auto';
    SystemMotion.reduceMotion.value = false;
    SystemMotion.touchExploration.value = false;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = _originalLauncher;
    SystemMotion.motionMode.value = 'auto';
    SystemMotion.reduceMotion.value = false;
    SystemMotion.touchExploration.value = false;
  });

  testWidgets('无障碍小节在行为之下、权限之上，包含全局动画与无障碍相关问题', (tester) async {
    final environment = await _pumpSettings(tester);
    await _scrollTo(tester, _zh.a11yFeedback);
    // 继续滚到最底：行为 / 无障碍 / 权限 三组同屏，顺序以此为准
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(find.text(_zh.categoryAccessibility), findsOneWidget);
    final behavior = tester.getTopLeft(find.text(_zh.categoryBehavior)).dy;
    final a11y = tester.getTopLeft(find.text(_zh.categoryAccessibility)).dy;
    final permissions = tester
        .getTopLeft(find.text(_zh.categoryPermissions))
        .dy;
    expect(behavior, lessThan(a11y));
    expect(a11y, lessThan(permissions));

    // 两个入口：全局动画（副标题＝当前档）与无障碍相关问题
    expect(find.text(_zh.globalAnimations), findsOneWidget);
    expect(environment.settingsState.store.motionMode, 'auto');
    expect(find.text(_zh.motionModeAuto), findsOneWidget);
    expect(find.text(_zh.a11yFeedback), findsOneWidget);
  });

  testWidgets('全局动画：单选弹窗三个选项，选择后落盘并同步读屏信号', (tester) async {
    final environment = await _pumpSettings(tester);
    await _scrollTo(tester, _zh.globalAnimations);

    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

    await tester.tap(find.text(_zh.globalAnimations));
    await tester.pumpAndSettle();

    // 三个选项；「自动」带说明副标题
    expect(inDialog(_zh.motionModeAuto), findsOneWidget);
    expect(inDialog(_zh.motionModeEnabled), findsOneWidget);
    expect(inDialog(_zh.motionModeDisabled), findsOneWidget);
    expect(inDialog(_zh.motionModeAutoSubtitle), findsOneWidget);

    await tester.tap(inDialog(_zh.motionModeDisabled));
    await tester.pumpAndSettle();
    expect(environment.settingsState.store.motionMode, 'off');
    expect(SystemMotion.motionMode.value, 'off');
    // 行副标题更新为当前档
    expect(find.text(_zh.motionModeDisabled), findsOneWidget);

    // 再切回「启用」
    await tester.tap(find.text(_zh.globalAnimations));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(_zh.motionModeEnabled));
    await tester.pumpAndSettle();
    expect(environment.settingsState.store.motionMode, 'on');
    expect(SystemMotion.motionMode.value, 'on');
    expect(find.text(_zh.motionModeEnabled), findsOneWidget);
  });

  testWidgets('全局动画设置覆盖系统与读屏信号', (tester) async {
    // 模拟读屏接管交互（触摸探索开启）
    SystemMotion.touchExploration.value = true;
    late bool observed;

    Future<void> pumpProbe() async {
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: Builder(
            builder: (context) {
              observed = reduceMotionOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
    }

    await pumpProbe();
    expect(observed, isTrue); // auto：读屏 → 少动效

    SystemMotion.motionMode.value = 'on';
    await pumpProbe();
    expect(observed, isFalse); // 「启用」：无视读屏信号，始终动画

    SystemMotion.motionMode.value = 'off';
    SystemMotion.touchExploration.value = false;
    await pumpProbe();
    expect(observed, isTrue); // 「禁用」：没有信号也少动效
  });

  testWidgets('无障碍相关问题：确认后复制邮箱、轻提示并唤起邮件', (tester) async {
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpSettings(tester);
    await _scrollTo(tester, _zh.a11yFeedback);
    await tester.tap(find.text(_zh.a11yFeedback));
    await tester.pumpAndSettle();

    expect(find.text(_zh.a11yFeedbackDialogTitle), findsOneWidget);
    expect(find.text(_zh.a11yFeedbackDialogBody), findsOneWidget);

    // 取消：什么都不做
    await tester.tap(find.text(_zh.cancel));
    await tester.pumpAndSettle();
    expect(clipboard, isEmpty);
    expect(_launcher.launched, isEmpty);

    // 反馈：复制邮箱 → 轻提示 → mailto 跳转
    await tester.tap(find.text(_zh.a11yFeedback));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_zh.feedback));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(clipboard, ['lancloud_feedback@outlook.com']);
    expect(find.text(_zh.emailCopied), findsOneWidget);
    expect(_launcher.launched, ['mailto:lancloud_feedback@outlook.com']);

    // 轻提示 1.6s 停留 + 180ms 淡出：跑完它，别留挂起的定时器
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text(_zh.emailCopied), findsNothing);
  });

  test('设置存取与备份：全局动画档位往返', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore();
    await store.load();
    expect(store.motionMode, 'auto');
    await store.setMotionMode('off');
    expect(store.motionMode, 'off');

    final target = SettingsStore();
    await target.load();
    await target.applyJson(store.toJson());
    expect(target.motionMode, 'off');
  });
}
