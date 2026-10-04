import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/predictive_back_transitions.dart';

void main() {
  const double maxScrimOpacity = 0.32;

  Future<void> backGesture(
    WidgetTester tester,
    String method, [
    Map<String, Object?>? args,
  ]) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.backGesture.name,
      SystemChannels.backGesture.codec.encodeMethodCall(
        MethodCall(method, args),
      ),
      (ByteData? _) {},
    );
  }

  double scrimAlpha(WidgetTester tester) {
    final ColoredBox box = tester.widget<ColoredBox>(
      find.byKey(kPredictiveBackScrimKey),
    );
    return box.color.a;
  }

  Future<ModalRoute<dynamic>> pumpSecondPage(WidgetTester tester) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: <TargetPlatform, PageTransitionsBuilder>{
              TargetPlatform.android: AospPredictiveBackPageTransitionsBuilder(),
            },
          ),
        ),
        home: const Scaffold(body: Center(child: Text('first'))),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('second'))),
      ),
    );
    await tester.pumpAndSettle();
    return ModalRoute.of(tester.element(find.text('second')))!;
  }

  testWidgets('预测性返回：上一页遮罩随手势由深到透明', (tester) async {
    final ModalRoute<dynamic> route = await pumpSecondPage(tester);

    // 没有手势：结构在，但不画遮罩
    expect(find.byKey(kPredictiveBackScrimKey), findsNothing);

    // 手指刚移动（上一页刚被露出一点）：盖最深的一层半透明黑色遮罩
    route.handleStartBackGesture(progress: 0.9);
    await tester.pump();
    expect(find.byKey(kPredictiveBackScrimKey), findsOneWidget);
    expect(scrimAlpha(tester), closeTo(maxScrimOpacity * 0.9, 0.005));

    // 滑到一半：遮罩变淡，上一页更清晰
    route.handleUpdateBackGestureProgress(progress: 0.45);
    await tester.pump();
    expect(scrimAlpha(tester), closeTo(maxScrimOpacity * 0.45, 0.005));

    // 滑到底：遮罩完全透明，上一页完全清晰
    route.handleUpdateBackGestureProgress(progress: 0);
    await tester.pump();
    expect(find.byKey(kPredictiveBackScrimKey), findsNothing);

    // 取消手势、页面回位后遮罩消失
    route.handleCancelBackGesture();
    await tester.pumpAndSettle();
    expect(find.byKey(kPredictiveBackScrimKey), findsNothing);
  });

  testWidgets('普通 push / pop 不加遮罩', (tester) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: <TargetPlatform, PageTransitionsBuilder>{
              TargetPlatform.android: AospPredictiveBackPageTransitionsBuilder(),
            },
          ),
        ),
        home: const Scaffold(body: Center(child: Text('first'))),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('second'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kPredictiveBackScrimKey), findsNothing);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(find.byKey(kPredictiveBackScrimKey), findsNothing);
  });

  testWidgets('松手提交后仍然播放原版返回动画（逐帧淡出，不是直接消失）', (tester) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: <TargetPlatform, PageTransitionsBuilder>{
              TargetPlatform.android: AospPredictiveBackPageTransitionsBuilder(),
            },
          ),
        ),
        home: const Scaffold(body: Center(child: Text('first'))),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('second'))),
      ),
    );
    await tester.pumpAndSettle();

    // 走真实手势管线，保证 commit 时 transition 的 phase 生效。
    await backGesture(tester, 'startBackGesture', <String, Object?>{
      'progress': 0.0,
      'swipeEdge': 0,
      'touchOffset': <double>[20.0, 1200.0],
    });
    await tester.pump();
    await backGesture(tester, 'updateBackGestureProgress', <String, Object?>{
      'progress': 0.4,
      'swipeEdge': 0,
      'touchOffset': <double>[500.0, 1200.0],
    });
    await tester.pump();
    await backGesture(tester, 'commitBackGesture');
    await tester.pump();

    // 提交过程中页面仍在，并在逐帧淡出（原版动画）。
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('second', skipOffstage: false), findsOneWidget);
    final Opacity fade = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.text('second', skipOffstage: false),
            matching: find.byType(Opacity, skipOffstage: false),
          )
          .first,
    );
    expect(fade.opacity, lessThan(1.0));

    // 动画播完后页面才被移除。
    await tester.pumpAndSettle();
    expect(find.text('second', skipOffstage: false), findsNothing);
    expect(find.text('first'), findsOneWidget);
  });
}
