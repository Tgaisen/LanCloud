import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoPageTransitionsBuilder;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/predictive_back_transitions.dart';

const ValueKey<String> _firstPage = ValueKey<String>('first-page');
const ValueKey<String> _secondPage = ValueKey<String>('second-page');

/// 走真实的 `flutter/backgesture` 通道：系统事件 → 手势检测 → 路由动画，
/// 覆盖整条链路（而不是直接调路由的 handle* 方法）。
Future<void> backGesture(
  WidgetTester tester,
  String method, [
  Map<String, Object?>? args,
]) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.backGesture.name,
    SystemChannels.backGesture.codec.encodeMethodCall(MethodCall(method, args)),
    (ByteData? _) {},
  );
  await tester.pump();
}

Map<String, Object?> backEvent(double progress) => <String, Object?>{
  'progress': progress,
  'swipeEdge': 0, // 左侧边缘往右滑
  'touchOffset': <double>[10 + progress * 400, 300],
};

/// 打开一个二级页面（测试里 [defaultTargetPlatform] 是 Android）。
Future<void> pumpSecondPage(
  WidgetTester tester, {
  TargetPlatform? platform,
}) async {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: ThemeData(
        platform: platform,
        pageTransitionsTheme: kLanCloudPageTransitionsTheme,
      ),
      home: const Scaffold(body: SizedBox.expand(key: _firstPage)),
    ),
  );
  navigatorKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: SizedBox.expand(key: _secondPage)),
    ),
  );
  await tester.pumpAndSettle();
}

double pageDx(WidgetTester tester, Key key) =>
    tester.getTopLeft(find.byKey(key)).dx;

void main() {
  test('转场表：PC 保持缩放淡入，移动端换成 iOS 视差', () {
    expect(
      kLanCloudPageTransitionBuilders[TargetPlatform.windows],
      isA<ZoomPageTransitionsBuilder>(),
    );
    expect(
      kLanCloudPageTransitionBuilders[TargetPlatform.linux],
      isA<ZoomPageTransitionsBuilder>(),
    );
    expect(
      kLanCloudPageTransitionBuilders[TargetPlatform.android],
      isA<CupertinoPredictiveBackPageTransitionsBuilder>(),
    );
    expect(
      kLanCloudPageTransitionBuilders[TargetPlatform.iOS],
      isA<CupertinoPageTransitionsBuilder>(),
    );
    expect(
      kLanCloudPageTransitionBuilders[TargetPlatform.macOS],
      isA<CupertinoPageTransitionsBuilder>(),
    );
  });

  testWidgets('Android：侧滑返回跟手滑动，上一页按 1/3 视差让位', (tester) async {
    await pumpSecondPage(tester);
    final double width = tester.getSize(find.byKey(_secondPage)).width;
    expect(pageDx(tester, _secondPage), 0, reason: '静止时二级页面盖住整屏');

    await backGesture(tester, 'startBackGesture', backEvent(0));
    await backGesture(tester, 'updateBackGestureProgress', backEvent(0.4));

    // 手指往回拖了 40%：新页面跟着滑出 40%（线性跟手，不是松手才动）
    expect(
      pageDx(tester, _secondPage),
      moreOrLessEquals(width * 0.4, epsilon: 0.5),
    );
    // 上一页同步让位：进度 60% × 1/3 屏宽
    expect(
      pageDx(tester, _firstPage),
      moreOrLessEquals(-width / 3 * 0.6, epsilon: 0.5),
    );

    // 往回拖回屏幕：新手势重新接管，位置再次跟手（不会累积偏差）
    await backGesture(tester, 'updateBackGestureProgress', backEvent(0.1));
    expect(
      pageDx(tester, _secondPage),
      moreOrLessEquals(width * 0.1, epsilon: 0.5),
    );
  });

  testWidgets('Android：松手取消按跟手位置回位，页面不出栈', (tester) async {
    await pumpSecondPage(tester);
    final double width = tester.getSize(find.byKey(_secondPage)).width;

    await backGesture(tester, 'startBackGesture', backEvent(0));
    await backGesture(tester, 'updateBackGestureProgress', backEvent(0.4));
    await backGesture(tester, 'cancelBackGesture');
    await tester.pump(const Duration(milliseconds: 100));

    final double midway = pageDx(tester, _secondPage);
    expect(midway, lessThan(width * 0.4), reason: '取消后开始回位');
    expect(midway, greaterThanOrEqualTo(0));

    await tester.pumpAndSettle();
    expect(pageDx(tester, _secondPage), 0);
    expect(find.byKey(_secondPage), findsOneWidget);
  });

  testWidgets('Android：松手提交从手指位置继续滑出，不弹回原位', (tester) async {
    await pumpSecondPage(tester);
    final double width = tester.getSize(find.byKey(_secondPage)).width;

    await backGesture(tester, 'startBackGesture', backEvent(0));
    await backGesture(tester, 'updateBackGestureProgress', backEvent(0.9));
    final double dragged = pageDx(tester, _secondPage);
    expect(dragged, moreOrLessEquals(width * 0.9, epsilon: 0.5));

    await backGesture(tester, 'commitBackGesture');
    // 提交瞬间不能弹回原位（框架原版会 reverse(from: 1.0) 重播整段退场）
    expect(pageDx(tester, _secondPage), greaterThanOrEqualTo(dragged - 0.5));

    // 剩余行程继续滑完，然后页面才出栈
    await tester.pump(const Duration(milliseconds: 60));
    expect(pageDx(tester, _secondPage), greaterThan(dragged + 1));
    await tester.pumpAndSettle();
    expect(find.byKey(_secondPage), findsNothing);
    expect(pageDx(tester, _firstPage), 0);
  });

  testWidgets('PC（Windows）：不接管返回手势，仍是默认缩放淡入转场', (tester) async {
    await pumpSecondPage(tester, platform: TargetPlatform.windows);

    await backGesture(tester, 'startBackGesture', backEvent(0));
    await backGesture(tester, 'updateBackGestureProgress', backEvent(0.4));
    // 默认转场是缩放 + 淡入，不做水平位移
    expect(pageDx(tester, _secondPage), 0);

    await backGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.byKey(_secondPage), findsNothing);
  });
}
