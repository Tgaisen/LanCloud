import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/system_motion.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/predictive_back_transitions.dart';
// 出口只透出 wrapper；要断言 m3e_core 的具体控件就直连它（同 m3e_test.dart）。
import 'package:m3e_core/m3e_core.dart'
    show
        M3ECircularProgressIndicator,
        M3ELinearProgressIndicator,
        M3ELoadingIndicator;

void main() {
  // 系统「移除动画 / 减弱动态效果」（disableAnimations）与读屏软件接管交互
  // （accessibleNavigation）都算「要求少动效」：列表入场直接显示，
  // 不做淡入 + 位移。
  testWidgets('系统要求少动效时列表入场动画直接到位', (tester) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: ListEnterAnimation.duration,
    );
    addTearDown(controller.dispose);

    Widget host() => MaterialApp(
      home: Scaffold(
        body: ListEnterAnimation(
          progress: controller,
          index: 2,
          child: const Text('条目'),
        ),
      ),
    );

    await tester.pumpWidget(host());
    // 进度还在 0：正常应该包着透明度 / 位移
    expect(
      find.descendant(
        of: find.byType(ListEnterAnimation),
        matching: find.byType(Opacity),
      ),
      findsOneWidget,
    );

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(host());
    expect(
      find.descendant(
        of: find.byType(ListEnterAnimation),
        matching: find.byType(Opacity),
      ),
      findsNothing,
      reason: '「移除动画」时不应该再有淡入包装',
    );
    expect(find.text('条目'), findsOneWidget);

    // 引擎的 accessibleNavigation 不算「少动效」：任何无障碍服务查一次语义树
    // 它就会被置位（自动记账、自动填表这类与读屏无关的服务也会），拿它当
    // 少动效等于「开了任意无障碍服务 = 全应用没有动画」。
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    await tester.pumpWidget(host());
    expect(
      find.descendant(
        of: find.byType(ListEnterAnimation),
        matching: find.byType(Opacity),
      ),
      findsOneWidget,
      reason: '普通无障碍服务（自动记账等）不该让动画消失',
    );

    // 真正的读屏（触摸探索）由原生上报，这时才跳过动画
    SystemMotion.touchExploration.value = true;
    addTearDown(() => SystemMotion.touchExploration.value = false);
    await tester.pumpWidget(host());
    expect(
      find.descendant(
        of: find.byType(ListEnterAnimation),
        matching: find.byType(Opacity),
      ),
      findsNothing,
      reason: '读屏接管交互时不应该再有淡入包装',
    );
  });

  // 页面转场同理：开了「移除动画」后新页面第一帧就已经在最终位置，
  // 不做缩放 / 位移（对照：正常情况下第一帧会被转场挪走）。
  // 原生侧读到的动画缩放（华为「移除动画」只改 window/animator，
  // 引擎看不到）同样要生效。
  testWidgets('原生报告「移除动画」时列表入场也直接到位', (tester) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: ListEnterAnimation.duration,
    );
    addTearDown(controller.dispose);

    Widget host() => MaterialApp(
      home: Scaffold(
        body: ListEnterAnimation(
          progress: controller,
          index: 1,
          child: const Text('条目'),
        ),
      ),
    );

    await tester.pumpWidget(host());
    expect(
      find.descendant(
        of: find.byType(ListEnterAnimation),
        matching: find.byType(Opacity),
      ),
      findsOneWidget,
    );

    SystemMotion.reduceMotion.value = true;
    addTearDown(() => SystemMotion.reduceMotion.value = false);
    await tester.pumpWidget(host());
    expect(
      find.descendant(
        of: find.byType(ListEnterAnimation),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
  });

  // 少动效时加载指示器不再转圈：换成静止的 75% 环 / 条。
  testWidgets('少动效时进度指示器退化成静态', (tester) async {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    await tester.pumpWidget(host(const M3eLoadingIndicator()));
    expect(
      find.byType(M3ELoadingIndicator),
      findsOneWidget,
      reason: '正常情况是转圈的 loading indicator',
    );

    SystemMotion.reduceMotion.value = true;
    addTearDown(() => SystemMotion.reduceMotion.value = false);
    await tester.pumpWidget(host(const M3eLoadingIndicator()));
    final ring = tester.widget<M3ECircularProgressIndicator>(
      find.byType(M3ECircularProgressIndicator),
    );
    expect(ring.value, isNotNull, reason: '静态形态必须是确定进度');
    expect(find.byType(M3ELoadingIndicator), findsNothing);

    // 不确定进度的线性条同理
    await tester.pumpWidget(host(const M3eLinearProgressIndicator()));
    final bar = tester.widget<M3ELinearProgressIndicator>(
      find.byType(M3ELinearProgressIndicator),
    );
    expect(bar.value, isNotNull);
  });

  // 底部弹窗的显隐动画也要跟着「移除动画」走：整块面板直接到位，
  // 不存在滑入过程中间帧。
  testWidgets('少动效时底部弹窗瞬间就位', (tester) async {
    SystemMotion.reduceMotion.value = true;
    addTearDown(() => SystemMotion.reduceMotion.value = false);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showAppSheet<void>(
                  context,
                  child: const SizedBox(
                    height: 240,
                    child: Center(child: Text('弹窗内容')),
                  ),
                ),
                child: const Text('打开弹窗'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开弹窗'));
    await tester.pump();
    await tester.pump();
    final early = tester.getTopLeft(find.text('弹窗内容'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('弹窗内容')),
      early,
      reason: '少动效时弹窗不该有滑入中间帧',
    );
  });

  testWidgets('系统要求少动效时页面转场直接到位', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(pageTransitionsTheme: kLanCloudPageTransitionsTheme),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Align(
                        alignment: Alignment.topLeft,
                        child: Text('第二页'),
                      ),
                    ),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pump();

    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump();
    final firstFrame = tester.getTopLeft(find.text('第二页'));

    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('第二页')),
      firstFrame,
      reason: '「移除动画」时新页面第一帧就应该在最终位置',
    );
  });
}
