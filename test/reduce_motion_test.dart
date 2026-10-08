import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/system_motion.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/predictive_back_transitions.dart';

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

    // 读屏软件（TalkBack / 屏幕朗读）接管交互时同样跳过
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
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
