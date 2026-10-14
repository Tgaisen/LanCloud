import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/settings_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lancloud/l10n/delegates.dart';

Widget host(Widget child) {
  return MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: Center(child: child)),
  );
}

/// 语义树里是否存在包含 [target] 的文本（label 或 tooltip，节点位置不重要）。
/// IconButton 的 tooltip 走的是 SemanticsData.tooltip，TalkBack 会把它当
/// 控件名称读出来，所以这里两种都要看。
bool hasLabel(WidgetTester tester, String target) {
  // 语义树挂在 RenderView 的 PipelineOwner 上（binding.pipelineOwner 已弃用）。
  final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
  var found = false;
  void walk(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.label.contains(target) || data.tooltip.contains(target)) {
      found = true;
    }
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(owner.rootSemanticsNode!);
  return found;
}

/// 语义树里第一个「label 或 tooltip 包含 [target]」的节点数据。
SemanticsData? semanticsData(WidgetTester tester, String target) {
  // 语义树挂在 RenderView 的 PipelineOwner 上（binding.pipelineOwner 已弃用）。
  final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
  SemanticsData? found;
  void walk(SemanticsNode node) {
    if (found != null) return;
    final data = node.getSemanticsData();
    if (data.label.contains(target) || data.tooltip.contains(target)) {
      found = data;
      return;
    }
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(owner.rootSemanticsNode!);
  return found;
}

/// 语义树里的全部节点（先序遍历）。
List<SemanticsNode> semanticsNodes(WidgetTester tester) {
  final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
  final result = <SemanticsNode>[];
  void walk(SemanticsNode node) {
    result.add(node);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(owner.rootSemanticsNode!);
  return result;
}

void main() {
  // 首页快捷操作栏：图标按钮的文字标签在可点区域下面，必须显式合成语义节点，
  // 否则 TalkBack 聚焦到按钮上读不出名称（读屏用户反馈过的问题）。
  testWidgets('快捷操作按钮读出名称且可激活', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      host(
        ExpressiveIconButton(
          icon: Icons.open_in_new,
          label: '打开链接',
          onPressed: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final data = tester
        .getSemantics(find.byType(ExpressiveIconButton))
        .getSemanticsData();
    expect(data.label, '打开链接');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('带角标的快捷操作把数量并进标签', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      host(
        ExpressiveIconButton(
          icon: Icons.swap_vert,
          label: '传输',
          badge: '2',
          onPressed: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final label = tester
        .getSemantics(find.byType(ExpressiveIconButton))
        .getSemanticsData()
        .label;
    expect(label, contains('传输'));
    expect(label, contains('2'));
    handle.dispose();
  });

  // 置灰的操作项（onPressed == null）此前没有自己的语义节点，文字会冒泡到
  // 上层：读屏聚焦窗口最外层会念出「下载」。这里钉住「有自己的节点 + 带停用状态」。
  testWidgets('置灰的多选操作项有自己的标签与停用状态', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      host(
        BatchAction(
          icon: Icons.download_outlined,
          label: '下载',
          onPressed: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final data = tester
        .getSemantics(find.byType(BatchAction))
        .getSemanticsData();
    expect(data.label, '下载');
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    // 读屏据此播报「已停用」
    expect(data.flagsCollection.isEnabled.name, 'isFalse');

    // 根节点不应把「下载」吸上去（修复前正是这个症状）
    // 语义树挂在 RenderView 的 PipelineOwner 上（binding.pipelineOwner 已弃用）。
    final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
    final root = owner.rootSemanticsNode!;
    expect(root.getSemanticsData().label, isNot(contains('下载')));
    handle.dispose();
  });

  // 分区标题与展开/收起按钮读屏读成连贯的一项，且语义节点自带切换动作
  // （触摸仍然只有右侧按钮能点，见 home_section_test）。
  testWidgets('分区标题读作「收起/展开 + 标题」且可点', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      host(
        SectionCard(
          title: '快速访问',
          expanded: true,
          onToggle: () {},
          child: const SizedBox(height: 10),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final data = semanticsData(tester, '收起快速访问');
    expect(data, isNotNull);
    expect(data!.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('返回按钮读得出名称', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      host(Builder(builder: (context) => AppBarBackButton(onPressed: () {}))),
    );
    await tester.pumpAndSettle();

    // 名称来自 MaterialLocalizations 的返回按钮 tooltip
    expect(hasLabel(tester, '返回'), isTrue);
    handle.dispose();
  });

  // 多选选中态（选中只换了图标，读屏看不出来）。
  testWidgets('多选选中的条目带 selected 状态', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      host(
        Md3ListItem(
          icon: Icons.folder_outlined,
          title: '测试文件夹',
          subtitle: '文件夹',
          selected: true,
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final data = tester
        .getSemantics(find.byType(Md3ListItem))
        .getSemanticsData();
    expect(data.flagsCollection.isSelected.name, 'isTrue');
    handle.dispose();
  });

  // 「进入多选」的播报文案走本地化，且只有真正进入多选那一刻才发。
  testWidgets('进入多选播报本地化文案', (tester) async {
    final announcements = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
          message,
        ) async {
          final event = message as Map<dynamic, dynamic>;
          if (event['type'] == 'announce') {
            announcements.add(
              (event['data'] as Map<dynamic, dynamic>)['message'] as String,
            );
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );

    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => announceEnteredMultiSelect(context),
            child: const Text('进入'),
          ),
        ),
      ),
    );
    // 只是把界面搭起来（多选条常驻在树里）不能有播报
    expect(announcements, isEmpty);

    await tester.tap(find.text('进入'));
    await tester.pumpAndSettle();
    // 播报延后到「下一帧 + 250ms」：等这一帧的语义树更新落地后再发，
    // 否则读屏会把刚排队的播报冲掉。
    await tester.pump(const Duration(milliseconds: 400));
    expect(announcements, ['进入多选']);
  });

  // 设置页滑杆：M3ESlider 是自绘控件，滑杆语义是在 _SliderTile 外面合成的。
  // 钉住「TalkBack 按 SeekBar 读出标题与当前值 + 上/下滑可调」；同时钉住
  // 内部手势语义已被屏蔽——暴露的 tap 会让读屏双击按中心点按、跳到中间档。
  testWidgets('设置页滑杆：读出滑杆角色与当前值，上/下滑调节并落盘', (tester) async {
    final handle = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({});
    final app = AppController();
    addTearDown(app.dispose);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.text('网络请求间隔');
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    // ensureVisible 会把条目贴到浮层顶栏下面（语义节点被裁剪）：往回滚一点
    await tester.drag(find.byType(SettingsPage), const Offset(0, 240));
    await tester.pumpAndSettle();

    final slider = find.descendant(
      of: find.widgetWithText(ListTile, '网络请求间隔'),
      matching: find.byType(M3ESlider),
    );
    expect(slider, findsOneWidget);

    SemanticsData data() => tester.getSemantics(slider).getSemanticsData();
    expect(data().flagsCollection.isSlider, isTrue);
    expect(data().label, '网络请求间隔');
    expect(data().value, '100 ms');
    expect(data().increasedValue, '150 ms');
    expect(data().decreasedValue, '75 ms');
    expect(data().hasAction(SemanticsAction.increase), isTrue);
    expect(data().hasAction(SemanticsAction.decrease), isTrue);
    // 内部手势语义不再暴露：读屏双击不会把值按到中间档
    expect(data().hasAction(SemanticsAction.tap), isFalse);
    expect(data().hasAction(SemanticsAction.scrollRight), isFalse);

    // 模拟 TalkBack 上滑：+1 档、写设置，节点值跟着更新
    final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
    owner.performAction(
      tester.getSemantics(slider).id,
      SemanticsAction.increase,
    );
    await tester.pumpAndSettle();
    expect(app.settings.requestInterval, 150);
    expect(data().value, '150 ms');

    // 下滑：回到原档并写回
    owner.performAction(
      tester.getSemantics(slider).id,
      SemanticsAction.decrease,
    );
    await tester.pumpAndSettle();
    expect(app.settings.requestInterval, 100);
    expect(data().value, '100 ms');

    handle.dispose();
  });

  // 按钮组（网盘页「布局 / 排序」、收藏页排序、设置页主题模式等）：
  // m3e_core 的 M3EToggleButton 会在按钮外再套一层 `Semantics(checked:)`，
  // 每个按钮因此有两个重叠节点——先「复选框」（无名称无动作）、再「按钮」。
  // 组件层（m3e.dart）现在合成一个节点：名称 + 选中态 + 点击。这里钉住
  // 「一个按钮一个节点」以及节点几何与真实按钮一致。
  testWidgets('连接式按钮组：一个按钮一个语义节点（名称 + 选中 + 点击）', (tester) async {
    final handle = tester.ensureSemantics();
    String? picked;
    await tester.pumpWidget(
      host(
        M3eConnectedButtonGroup<String>(
          values: const ['系统', '浅色', '深色'],
          selected: '系统',
          onSelected: (value) => picked = value,
          labelOf: (value) => Text(value),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nodes = semanticsNodes(tester);
    List<SemanticsNode> nodesOf(String label) => [
      for (final node in nodes)
        if (node.getSemanticsData().label == label) node,
    ];
    for (final label in ['系统', '浅色', '深色']) {
      final matches = nodesOf(label);
      expect(matches, hasLength(1), reason: '每个按钮应只有一个语义节点（$label）');
      final data = matches.single.getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isChecked.name, isNot('none'));
    }
    // 选中态只在当前项
    expect(
      nodesOf('系统').single.getSemanticsData().flagsCollection.isChecked.name,
      'isTrue',
    );
    expect(
      nodesOf('浅色').single.getSemanticsData().flagsCollection.isChecked.name,
      'isFalse',
    );
    // 单选组（与列表选择 M3ePickTile 同一套语义：checked + 互斥组）
    expect(
      nodesOf('系统').single
          .getSemanticsData()
          .flagsCollection
          .isInMutuallyExclusiveGroup,
      isTrue,
    );

    // 几何：语义节点与真实按钮一一对齐（宽度、间距一致）
    // 组内部还有一组 Opacity(0) 的测量用按钮，用 hitTestable 过滤掉。
    final buttons = find.byType(M3EToggleButton).hitTestable();
    expect(buttons, findsNWidgets(3));
    final buttonRects = [
      for (var i = 0; i < 3; i++) tester.getRect(buttons.at(i)),
    ];
    final nodeRects = [
      for (final label in ['系统', '浅色', '深色']) nodesOf(label).single.rect,
    ];
    // 节点 rect 是自身坐标系，相对父节点的位置在 transform 的平移里。
    final nodePos = [
      for (final label in ['系统', '浅色', '深色'])
        nodesOf(label).single.transform!.getTranslation(),
    ];
    final dx = buttonRects[0].left - nodePos[0].x;
    final dy = buttonRects[0].top - nodePos[0].y;
    for (var i = 0; i < 3; i++) {
      expect(
        nodePos[i].x + dx,
        moreOrLessEquals(buttonRects[i].left, epsilon: 0.5),
      );
      expect(
        nodePos[i].y + dy,
        moreOrLessEquals(buttonRects[i].top, epsilon: 0.5),
      );
      expect(
        nodeRects[i].width,
        moreOrLessEquals(buttonRects[i].width, epsilon: 0.5),
      );
      expect(
        nodeRects[i].height,
        moreOrLessEquals(buttonRects[i].height, epsilon: 0.5),
      );
    }

    // 读屏点击（SemanticsAction.tap）能选中另一项
    final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
    owner.performAction(nodesOf('浅色').single.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(picked, '浅色');
    handle.dispose();
  });

  // 图标按钮组（属性菜单「下载 / 复制链接 / 二维码 / 收藏 / 访问密码」）：
  // 动作按钮报「按钮」，开关按钮带选中态，置灰不可点；每个按钮同样只有一个
  // 语义节点，且读屏点击按和触摸一致的路由派发。
  testWidgets('图标按钮组：动作/开关/置灰各自一个语义节点，点击按语义派发', (tester) async {
    final handle = tester.ensureSemantics();
    final pressed = <String>[];
    final toggled = <(String, bool)>[];
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 300,
          child: M3EIconButtonGroup<String>(
            items: const [
              M3EIconAction<String>(
                value: 'dl',
                icon: Icons.download_outlined,
                checkedIcon: Icons.download_done,
                tooltip: '下载',
              ),
              M3EIconAction<String>(
                value: 'fav',
                icon: Icons.star_outline,
                checkedIcon: Icons.star_border,
                tooltip: '收藏',
                isToggle: true,
              ),
              M3EIconAction<String>(
                value: 'off',
                icon: Icons.file_download_off,
                checkedIcon: Icons.file_download_off,
                tooltip: '离线',
                enabled: false,
              ),
            ],
            onPressed: pressed.add,
            onToggled: (value, checked) => toggled.add((value, checked)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nodes = semanticsNodes(tester);
    List<SemanticsNode> nodesOf(String label) => [
      for (final node in nodes)
        if (node.getSemanticsData().label == label) node,
    ];
    SemanticsNode nodeOf(String label) {
      final matches = nodesOf(label);
      expect(matches, hasLength(1), reason: '每个按钮应只有一个语义节点（$label）');
      return matches.single;
    }

    final dl = nodeOf('下载').getSemanticsData();
    expect(dl.flagsCollection.isChecked.name, 'none'); // 动作按钮：不报选中态
    expect(dl.hasAction(SemanticsAction.tap), isTrue);

    final fav = nodeOf('收藏').getSemanticsData();
    expect(fav.flagsCollection.isChecked.name, 'isFalse');
    expect(fav.hasAction(SemanticsAction.tap), isTrue);

    final off = nodeOf('离线').getSemanticsData();
    expect(off.hasAction(SemanticsAction.tap), isFalse); // 置灰不可点
    expect(off.flagsCollection.isEnabled.name, 'isFalse');

    // 几何：语义节点与真实按钮对齐（等宽 + spacing 一致）
    final buttons = find.byType(M3EToggleButton).hitTestable();
    expect(buttons, findsNWidgets(3));
    final buttonRects = [
      for (var i = 0; i < 3; i++) tester.getRect(buttons.at(i)),
    ];
    final nodeRects = [
      for (final label in ['下载', '收藏', '离线']) nodeOf(label).rect,
    ];
    final nodePos = [
      for (final label in ['下载', '收藏', '离线'])
        nodeOf(label).transform!.getTranslation(),
    ];
    final dx = buttonRects[0].left - nodePos[0].x;
    final dy = buttonRects[0].top - nodePos[0].y;
    for (var i = 0; i < 3; i++) {
      expect(
        nodePos[i].x + dx,
        moreOrLessEquals(buttonRects[i].left, epsilon: 0.5),
      );
      expect(
        nodePos[i].y + dy,
        moreOrLessEquals(buttonRects[i].top, epsilon: 0.5),
      );
      expect(
        nodeRects[i].width,
        moreOrLessEquals(buttonRects[i].width, epsilon: 0.5),
      );
      expect(
        nodeRects[i].height,
        moreOrLessEquals(buttonRects[i].height, epsilon: 0.5),
      );
    }

    // 读屏点击：动作按钮 → onPressed；开关按钮 → onToggled(切换后状态)
    final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
    owner.performAction(nodesOf('下载').single.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    owner.performAction(nodesOf('收藏').single.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(pressed, ['dl']);
    expect(toggled, [('fav', true)]);
    handle.dispose();
  });
}
