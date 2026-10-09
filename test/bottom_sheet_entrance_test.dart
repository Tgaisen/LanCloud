import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';

/// 取测试窗口里某个逻辑坐标上的实际渲染颜色（截图是物理像素，按逻辑坐标换算）。
Future<Color> renderedColor(WidgetTester tester, Offset point) async {
  final Size logical = tester.getSize(find.byType(MaterialApp));
  return (await tester.runAsync(() async {
    final ui.Image image = await captureImage(
      tester.element(find.byType(MaterialApp)),
    );
    try {
      final ByteData bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final double scale = image.width / logical.width;
      final int offset =
          ((point.dy * scale).round() * image.width +
              (point.dx * scale).round()) *
          4;
      return Color.fromARGB(
        bytes.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
    } finally {
      image.dispose();
    }
  }))!;
}

/// 打开一个内容留空的统一底部弹窗：面板底色要能按像素直接比对。
Future<void> openSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: ElevatedButton(
              onPressed: () => showAppSheet<void>(
                context,
                child: const SizedBox(height: 180, width: double.infinity),
              ),
              child: const Text('打开弹窗'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开弹窗'));
}

double sheetBottom(WidgetTester tester) =>
    tester.getRect(find.byType(M3EBottomSheet)).bottom;

void main() {
  // m3e_core 的 M3EBottomSheet 在面板下面垫了一条「overshoot skirt」实底色块
  // （Stack 里位于内容之后、不参与它自带的入场动画）。自带入场还在跑时内容
  // 是半透明 / 偏下的，这条色块就会从弹窗底部露出来——看起来就是「弹窗底部
  // 多出一条和弹窗同宽的白色矩形」，动画播完才消失。所以外壳关掉了自带入场，
  // 改由路由统一播放（见 lib/ui/common.dart 的 animateEntrance: false）。
  testWidgets('底部弹窗入场：面板底部不会提前露出一条垫色', (tester) async {
    await openSheet(tester);
    await tester.pump();
    // 入场中段：面板已经露出屏幕底部
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    final Size logical = tester.getSize(find.byType(MaterialApp));
    final Rect sheet = tester.getRect(find.byType(M3EBottomSheet));
    // 面板里贴着底部一条带的上方（同一块 Material 涂的底色）
    // vs 屏幕最底部一条（overshoot 垫色露出的位置）
    final Color body = await renderedColor(
      tester,
      Offset(sheet.center.dx, math.min(sheet.bottom, logical.height) - 60),
    );
    final Color bottom = await renderedColor(
      tester,
      Offset(sheet.center.dx, logical.height - 6),
    );
    expect(
      bottom.toARGB32(),
      body.toARGB32(),
      reason:
          '入场过程中面板底部露出了一条更实的垫色：'
          'body=${body.toARGB32().toRadixString(16)} '
          'bottom=${bottom.toARGB32().toRadixString(16)}',
    );
  });

  // 入场弹性改由路由的入场曲线给出：整块面板滑入时越过落位点一点点再回弹
  // （对应 m3e_core 原本 spring 的手感），幅度要小、且最终必须落准。
  testWidgets('底部弹窗入场带一点过冲，落位前轻微回弹', (tester) async {
    await openSheet(tester);
    await tester.pump();

    final double restBottom = tester.getSize(find.byType(MaterialApp)).height;
    double highestBottom = restBottom;
    for (int i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      highestBottom = math.min(highestBottom, sheetBottom(tester));
    }

    final double overshoot = restBottom - highestBottom;
    expect(overshoot, greaterThan(4), reason: '应该有可见的回弹（过冲 $overshoot dp）');
    expect(overshoot, lessThan(20), reason: '回弹不能过头（过冲 $overshoot dp）');

    await tester.pumpAndSettle();
    expect(sheetBottom(tester), moreOrLessEquals(restBottom, epsilon: 0.5));
  });

  // 回弹抬离屏幕底边时会露出面板与屏幕之间的缝，这条缝得由外壳垫在底部的
  // overshoot 垫色补上（同色），不能露出后面的遮罩。
  testWidgets('底部弹窗过冲露出的缝由垫色补住，不露遮罩', (tester) async {
    await openSheet(tester);
    await tester.pump();
    // 入场曲线峰值在 61% 处：250ms 的进场 → 约 152ms
    await tester.pump(const Duration(milliseconds: 152));

    final Size logical = tester.getSize(find.byType(MaterialApp));
    final Rect sheet = tester.getRect(find.byType(M3EBottomSheet));
    expect(
      sheet.bottom,
      lessThan(logical.height - 2),
      reason: '此刻面板应该已经抬离屏幕底边（过冲）',
    );

    final Color body = await renderedColor(
      tester,
      Offset(sheet.center.dx, sheet.bottom - 20),
    );
    final Color gap = await renderedColor(
      tester,
      Offset(sheet.center.dx, logical.height - 2),
    );
    expect(
      gap.toARGB32(),
      body.toARGB32(),
      reason:
          '过冲露出的缝应当是面板底色（垫色补缝）：'
          'body=${body.toARGB32().toRadixString(16)} '
          'gap=${gap.toARGB32().toRadixString(16)}',
    );
  });
}
