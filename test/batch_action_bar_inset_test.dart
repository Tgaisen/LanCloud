import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lancloud/l10n/delegates.dart';

/// 外壳底栏高度（与 app.dart 保持一致）：悬浮 92 + 手势区，普通 80 + 手势区。
const double _gestureInset = 24;

Widget barApp(double shellBarHeight) => MaterialApp(
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('zh'),
  home: MediaQuery(
    data: MediaQueryData(padding: EdgeInsets.only(bottom: shellBarHeight)),
    child: const Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: BatchActionBar(children: []),
      ),
    ),
  ),
);

Future<void> pumpRiverpodBar(
  WidgetTester tester, {
  required NavigationAppearanceSettingsState appearance,
  required double shellBarHeight,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        navigationAppearanceSettingsStateProvider.overrideWithValue(appearance),
      ],
      child: barApp(shellBarHeight),
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
  testWidgets('多选条使用胶囊、8dp 间距和圆形按钮波纹', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          navigationAppearanceSettingsStateProvider.overrideWithValue(
            environment.navigationAppearanceSettings,
          ),
        ],
        child: MaterialApp(
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: BatchActionBar(
                children: [
                  BatchAction(
                    icon: Icons.download_outlined,
                    label: '下载',
                    onPressed: null,
                  ),
                  BatchAction(icon: Icons.copy, label: '复制', onPressed: null),
                  BatchAction(
                    icon: Icons.delete_outline,
                    label: '删除',
                    onPressed: null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = tester.widget<Material>(
      find.byKey(const ValueKey('batch-action-bar-surface')),
    );
    final scheme = Theme.of(tester.element(find.byType(BatchActionBar)))
        .colorScheme;
    expect(surface.color, scheme.surfaceContainerHighest);
    expect(surface.elevation, 0);
    expect(surface.shape, const StadiumBorder());

    final content = tester.widget<Padding>(
      find.byKey(const ValueKey('batch-action-bar-content')),
    );
    expect(
      content.padding,
      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('batch-action-bar-surface')))
          .height,
      56,
    );

    final row = tester.widget<Row>(
      find.byKey(const ValueKey('batch-action-bar-row')),
    );
    expect((row.children[1] as SizedBox).width, 0);
    expect((row.children[3] as SizedBox).width, 0);
    expect(
      tester
          .widgetList<M3eIconButton>(find.byType(M3eIconButton))
          .every((button) => !button.enablePressedMorph),
      isTrue,
    );
  });

  testWidgets('普通底栏：多选条贴在底栏上方 12dp', (tester) async {
    final environment = AppEnvironment();
    environment.settingsState.store.floatingNavBar = false;
    addTearDown(environment.dispose);
    // 普通底栏槽位 = 80 + 手势区
    await pumpRiverpodBar(
      tester,
      appearance: environment.navigationAppearanceSettings,
      shellBarHeight: 80 + _gestureInset,
    );
    expect(barPadding(tester).bottom, closeTo(80 + _gestureInset + 12, 0.01));
  });

  testWidgets('悬浮底栏：多选条按胶囊高度避让（不加 16dp 槽位留白）', (tester) async {
    final environment = AppEnvironment();
    environment.settingsState.store.floatingNavBar = true;
    addTearDown(environment.dispose);
    // 悬浮底栏槽位 = 92 + 手势区（胶囊 64 + 顶留白 16 + 底留白 12）
    await pumpRiverpodBar(
      tester,
      appearance: environment.navigationAppearanceSettings,
      shellBarHeight: 92 + _gestureInset,
    );
    // 期望值：92 + 手势区 - 16（槽位顶留白）+ 12（自身间距）
    expect(
      barPadding(tester).bottom,
      closeTo(92 + _gestureInset - 16 + 12, 0.01),
    );
  });

  testWidgets('Riverpod 导航外观变化会更新多选条避让', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final environment = AppEnvironment();
    environment.settingsState.store.floatingNavBar = true;
    addTearDown(environment.dispose);
    await pumpRiverpodBar(
      tester,
      appearance: environment.navigationAppearanceSettings,
      shellBarHeight: 92 + _gestureInset,
    );
    expect(
      barPadding(tester).bottom,
      closeTo(92 + _gestureInset - 16 + 12, 0.01),
    );

    await environment.navigationAppearanceSettings.setFloatingNavBar(false);
    await tester.pumpAndSettle();
    expect(barPadding(tester).bottom, closeTo(92 + _gestureInset + 12, 0.01));
  });
}
