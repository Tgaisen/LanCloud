import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:material_ui/material_ui.dart';

/// MD3E 下拉刷新（M3ePullToRefresh）：拖拽、阈值、回弹都在组件内部，
/// 这里守住的是「能不能触发刷新」与「禁用时是否完全不响应」两条底线。
Widget host({required bool enabled, Future<void> Function()? onRefresh}) =>
    MaterialApp(
      home: Scaffold(
        body: M3ePullToRefresh(
          enabled: enabled,
          edgeOffset: 56,
          semanticsLabel: '刷新',
          onRefresh: onRefresh ?? () async {},
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: const [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('内容')),
              ),
            ],
          ),
        ),
      ),
    );

Future<void> pullDown(WidgetTester tester) async {
  await tester.drag(
    find.byType(CustomScrollView),
    const Offset(0, 320),
    touchSlopY: 0,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('下拉过阈值触发 onRefresh，并把带容器的指示器拉出来', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(
      host(
        enabled: true,
        onRefresh: () async {
          refreshed += 1;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        },
      ),
    );

    await pullDown(tester);
    expect(refreshed, 1);
    expect(find.byType(M3EContainedLoadingIndicator), findsOneWidget);

    // 刷新结束后指示器收起
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(M3EContainedLoadingIndicator), findsNothing);
  });

  testWidgets('enabled=false 时不响应下拉刷新', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(
      host(enabled: false, onRefresh: () async => refreshed += 1),
    );

    await pullDown(tester);
    expect(refreshed, 0);
    expect(find.byType(M3EContainedLoadingIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(M3EContainedLoadingIndicator), findsNothing);
  });

  testWidgets('拉出指示器后 enabled 变 false：松手不再触发刷新', (tester) async {
    final enabled = ValueNotifier<bool>(true);
    addTearDown(enabled.dispose);
    var refreshed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (context, value, _) => M3ePullToRefresh(
              enabled: value,
              onRefresh: () async => refreshed += 1,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: const [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('内容')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, 260));
    await tester.pump();

    enabled.value = false;
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(refreshed, 0);
  });

  testWidgets('onRefresh 抛异常时指示器也会收起', (tester) async {
    await tester.pumpWidget(
      host(enabled: true, onRefresh: () async => throw StateError('boom')),
    );

    await pullDown(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(M3EContainedLoadingIndicator), findsNothing);
  });
}
