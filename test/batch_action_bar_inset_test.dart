import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:provider/provider.dart';

/// 外壳底栏高度（与 app.dart 保持一致）：悬浮 108 + 手势区，普通 80 + 手势区。
const double _gestureInset = 24;

Future<void> pumpBar(
  WidgetTester tester, {
  required AppController app,
  required double shellBarHeight,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: MediaQuery(
          data: MediaQueryData(
            padding: EdgeInsets.only(bottom: shellBarHeight),
          ),
          child: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: BatchActionBar(children: []),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 取出多选条最外层的内边距（BatchActionBar 根节点的 Padding）。
EdgeInsets barPadding(WidgetTester tester) {
  final padding = tester.widget<Padding>(
    find
        .descendant(
          of: find.byType(BatchActionBar),
          matching: find.byType(Padding),
        )
        .first,
  );
  return padding.padding as EdgeInsets;
}

void main() {
  testWidgets('普通底栏：多选条贴在底栏上方 12dp', (tester) async {
    final app = AppController()..settings.floatingNavBar = false;
    addTearDown(app.dispose);
    // 普通底栏槽位 = 80 + 手势区
    await pumpBar(tester, app: app, shellBarHeight: 80 + _gestureInset);
    expect(barPadding(tester).bottom, closeTo(80 + _gestureInset + 12, 0.01));
  });

  testWidgets('悬浮底栏：多选条按胶囊高度避让（不加 16dp 槽位留白）', (tester) async {
    final app = AppController()..settings.floatingNavBar = true;
    addTearDown(app.dispose);
    // 悬浮底栏槽位 = 108 + 手势区（胶囊 80 + 顶留白 16 + 底留白 12）
    await pumpBar(tester, app: app, shellBarHeight: 108 + _gestureInset);
    // 期望值：108 + 手势区 - 16（槽位顶留白）+ 12（自身间距）
    expect(
      barPadding(tester).bottom,
      closeTo(108 + _gestureInset - 16 + 12, 0.01),
    );
  });
}
