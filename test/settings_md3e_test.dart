import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'update_test_scope_test.dart';

Future<AppController> pumpSettings(
  WidgetTester tester, [
  SettingsCategory category = SettingsCategory.appearanceLayout,
]) async {
  SharedPreferences.setMockInitialValues({});
  final app = AppController();
  addTearDown(app.dispose);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(420, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    appTestTree(
      app: app,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: SettingsCategoryPage(category: category),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

/// 弹窗里的某一行（选择项）：返回包着色块的那个 Material。
Finder pickRow(String label) => find
    .ancestor(
      of: find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(label),
      ),
      matching: find.byType(Material),
    )
    .first;

void main() {
  testWidgets('主题模式：行内 tonal 按钮组，选中项带对勾，点一下即切换', (tester) async {
    final app = await pumpSettings(tester);

    final group = find.byType(M3eConnectedButtonGroup<String>);
    expect(group, findsOneWidget);
    // 组件内部会为「测量 / 选中态」多渲染几份文字，按组件的选中值断言更稳
    expect(
      tester.widget<M3eConnectedButtonGroup<String>>(group).selected,
      'system',
    );
    for (final label in ['系统', '浅色', '深色']) {
      expect(
        find.descendant(of: group, matching: find.text(label)),
        findsWidgets,
      );
    }

    await tester.tap(
      find.descendant(of: group, matching: find.text('深色')).first,
    );
    await tester.pumpAndSettle();
    expect(app.settingsState.store.themeMode, 'dark');
    expect(
      tester.widget<M3eConnectedButtonGroup<String>>(group).selected,
      'dark',
    );
  });

  testWidgets('网络请求间隔：行内滑杆（离散档位），拖动松手后落盘', (tester) async {
    final app = await pumpSettings(tester, SettingsCategory.transferConnection);

    final entry = find.text('网络请求间隔');
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    // ensureVisible 会把条目贴到浮层顶栏下面（拖不到）：往回滚一点
    await tester.drag(find.byType(SettingsCategoryPage), const Offset(0, 240));
    await tester.pumpAndSettle();

    final slider = find.byKey(const ValueKey('settings-slider-网络请求间隔'));
    expect(slider, findsOneWidget);
    // 滑杆上方有「间隔过小易触发服务器限流」的说明
    expect(find.text('间隔过小易触发服务器限流'), findsOneWidget);
    // 值显示在行的尾部（不再开弹窗）
    expect(find.text('100 ms'), findsOneWidget);

    // 滑杆绘制区向两端各溢出 thumbRadius；扣除后，轨道两端分别与标题
    // 左缘、当前值右缘对齐。
    final titleRect = tester.getRect(entry);
    final subtitleRect = tester.getRect(find.text('间隔过小易触发服务器限流'));
    final valueRect = tester.getRect(find.text('100 ms'));
    final sliderRect = tester.getRect(slider);
    const endpointInset = M3ESliderDefaults.thumbRadius;
    expect(
      valueRect.center.dy,
      moreOrLessEquals((titleRect.top + subtitleRect.bottom) / 2, epsilon: 0.5),
      reason: '当前值应与标题和副标题组成的文字列整体垂直居中',
    );
    expect(
      sliderRect.left + endpointInset,
      moreOrLessEquals(titleRect.left, epsilon: 0.5),
    );
    expect(
      sliderRect.right - endpointInset,
      moreOrLessEquals(valueRect.right, epsilon: 0.5),
    );

    // 拖到最右 → 最大档 1000ms，松手才写设置
    await tester.drag(slider, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(app.settingsState.store.requestInterval, 1000);
    expect(find.text('1000 ms'), findsOneWidget);
  });

  testWidgets('单选弹窗：列表组 + radio 指示器，选中项 tonal 强调色，点击即生效', (tester) async {
    final app = await pumpSettings(tester);

    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();

    final scheme = Theme.of(tester.element(find.byType(AlertDialog)))
        .colorScheme;
    // 选中态只由 radio 表示：行的底色不随选中变化（没有 tonal 强调）
    expect(tester.widget<Material>(pickRow('跟随系统')).color, isNull);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Radio<bool>),
      ),
      findsNWidgets(3),
    );
    // 单选列表用 radio：只有当前项选中
    final groups = tester
        .widgetList<RadioGroup<bool>>(find.byType(RadioGroup<bool>))
        .toList();
    expect(groups.where((group) => group.groupValue == true), hasLength(1));
    // 列表组容器色比弹窗底（surfaceContainerHigh）高一档
    expect(
      tester
          .widget<SegmentedList>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(SegmentedList),
            ),
          )
          .color,
      scheme.surfaceContainerHighest,
    );
    // M3 对话框内容边距 24dp（列表组外沿正好落在 24dp 上）
    expect(
      (tester.widget<AlertDialog>(find.byType(AlertDialog)).contentPadding!
              as EdgeInsets)
          .left,
      24,
    );
    // 未选中项同样无填充
    expect(tester.widget<Material>(pickRow('English')).color, isNull);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('English'),
      ),
    );
    await tester.pumpAndSettle();
    expect(app.settingsState.store.language, 'en');
  });

  testWidgets('多选弹窗：底栏显示项也是列表组 + tonal 选中态，确认后生效', (tester) async {
    final app = await pumpSettings(tester);

    final entry = find.text('底栏显示项');
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    // ensureVisible 会把条目贴到浮层顶栏下面（点不到）：往回滚一点再点
    await tester.drag(find.byType(SettingsCategoryPage), const Offset(0, 240));
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('未勾选的视图不显示在底栏，仍可从首页快捷操作栏打开')).dy,
      lessThan(tester.getTopLeft(find.text('传输')).dy),
      reason: '提示文案应位于选项列表之前',
    );
    // 关闭状态：checkbox 未勾选；打开后：checkbox 勾选（行的底色始终不变化）
    expect(tester.widget<Material>(pickRow('传输')).color, isNull);
    expect(
      tester
          .widget<Checkbox>(
            find.descendant(of: pickRow('传输'), matching: find.byType(Checkbox)),
          )
          .value,
      isFalse,
    );
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('传输')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Material>(pickRow('传输')).color, isNull);
    expect(
      tester
          .widget<Checkbox>(
            find.descendant(of: pickRow('传输'), matching: find.byType(Checkbox)),
          )
          .value,
      isTrue,
    );

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(app.settingsState.store.navShowTransfers, isTrue);
  });

  testWidgets('设置页分组小标题：title 角色 + 强调字重，与列表项左边对齐', (tester) async {
    await pumpSettings(tester);

    final headerFinder = find.byType(M3eSectionHeader).first;
    final header = tester.widget<Text>(
      find.descendant(of: headerFinder, matching: find.byType(Text)),
    );
    // M3E 强调排版：尺寸不变、字重更重（title small → w700）
    expect(header.style?.fontWeight, FontWeight.w700);

    // 左右 4dp 的缩进正好和列表项（组外边距 4dp）对齐
    final headerLeft = tester
        .getTopLeft(
          find.descendant(of: headerFinder, matching: find.byType(Text)),
        )
        .dx;
    final itemLeft = tester
        .getTopLeft(
          find
              .descendant(
                of: find.byType(SegmentedList).first,
                matching: find.byType(ListTile),
              )
              .first,
        )
        .dx;
    expect(headerLeft, itemLeft);
  });

  testWidgets('高级覆盖项：提示卡片带 info 图标，容器用次级容器色 + 16dp 圆角', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      appTestTree(
        app: app,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: AdvancedContent(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const message = '正常情况下不宜更改这些选项，否则可能导致相关功能故障';
    expect(find.text(message), findsOneWidget);
    // 带 info 图标（提示卡片里唯一一个 info）
    expect(
      find.descendant(
        of: find.byType(AdvancedContent),
        matching: find.byIcon(Icons.info_outline),
      ),
      findsOneWidget,
    );

    // 卡片容器：次级容器色 + 16dp 圆角；文字用配对的 on 角色
    final scheme = Theme.of(tester.element(find.text(message))).colorScheme;
    final card = tester.widget<Container>(
      find
          .ancestor(of: find.text(message), matching: find.byType(Container))
          .first,
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.color, scheme.secondaryContainer);
    expect(
      (decoration.borderRadius! as BorderRadius).topLeft.x,
      moreOrLessEquals(16),
    );
    expect(
      tester.widget<Text>(find.text(message)).style?.color,
      scheme.onSecondaryContainer,
    );
  });
}
