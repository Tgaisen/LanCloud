import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/drive_refresh_indicator.dart';

Widget host({required bool enabled, Future<void> Function()? onRefresh}) =>
    MaterialApp(
      home: Scaffold(
        body: LanRefreshIndicator(
          enabled: enabled,
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
  await tester.drag(find.byType(CustomScrollView), const Offset(0, 320));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('enabled=false 时不响应下拉刷新', (tester) async {
    await tester.pumpWidget(host(enabled: false));

    await pullDown(tester);
    expect(find.byType(RefreshProgressIndicator), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });

  testWidgets('enabled=true 时正常拉出刷新小球（对照组）', (tester) async {
    await tester.pumpWidget(host(enabled: true));

    await pullDown(tester);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });

  testWidgets('onRefresh 抛异常时小球也会收起', (tester) async {
    await tester.pumpWidget(
      host(enabled: true, onRefresh: () async => throw StateError('boom')),
    );

    await pullDown(tester);
    await tester.pumpAndSettle();
    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });

  testWidgets('拉出小球后 enabled 变 false：小球收起', (tester) async {
    final enabled = ValueNotifier<bool>(true);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (context, value, _) => LanRefreshIndicator(
              enabled: value,
              onRefresh: () async {},
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
    await gesture.moveBy(const Offset(0, 200));
    await tester.pump();
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);

    enabled.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(RefreshProgressIndicator), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
