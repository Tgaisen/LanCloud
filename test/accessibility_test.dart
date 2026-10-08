import 'package:flutter/material.dart' hide Icons;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';

Widget host(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: Center(child: child)),
  );
}

/// 语义树里是否存在包含 [target] 的文本（label 或 tooltip，节点位置不重要）。
/// IconButton 的 tooltip 走的是 SemanticsData.tooltip，TalkBack 会把它当
/// 控件名称读出来，所以这里两种都要看。
bool hasLabel(WidgetTester tester, String target) {
  // ignore: deprecated_member_use
  final owner = tester.binding.pipelineOwner.semanticsOwner!;
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
    // ignore: deprecated_member_use
    final owner = tester.binding.pipelineOwner.semanticsOwner!;
    final root = owner.rootSemanticsNode!;
    expect(root.getSemanticsData().label, isNot(contains('下载')));
    handle.dispose();
  });

  // 分区标题与展开/收起按钮共用一个可点区域，读屏读成连贯的一项。
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

    expect(hasLabel(tester, '收起快速访问'), isTrue);
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
}
