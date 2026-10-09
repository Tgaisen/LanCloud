import 'dart:ui' as ui;
import 'dart:typed_data';

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';

void main() {
  // m3e_core 的 M3EBottomSheet 在面板下面垫了一条「overshoot skirt」实底色块
  // （Stack 里位于内容之后、不参与它自带的入场动画）。自带入场还在跑时内容
  // 是半透明 / 偏下的，这条色块就会从弹窗底部露出来——看起来就是「弹窗底部
  // 多出一条和弹窗同宽的白色矩形」，动画播完才消失。
  testWidgets('底部弹窗入场：面板底部不会提前露出一条垫色', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                onPressed: () => showAppSheet<void>(
                  context,
                  // 内容留空：面板底色要能按像素直接比对
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
    await tester.pump();
    // 入场中段：面板已经露出屏幕底部，外壳自带入场（若还有）还在跑
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(M3EBottomSheet), findsOneWidget);
    final Rect sheet = tester.getRect(find.byType(M3EBottomSheet));
    final Size logical = tester.getSize(find.byType(MaterialApp));

    // 截图（取色）要跑在真实事件循环里，不能待在测试的 fake async 中
    final (Color body, Color bottom) = (await tester.runAsync(() async {
      final ui.Image image = await captureImage(
        tester.element(find.byType(MaterialApp)),
      );
      try {
        final ByteData bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        // 截图是物理像素（测试默认 DPR=3），按逻辑坐标换算
        final double scale = image.width / logical.width;
        Color pixelAt(double dx, double dy) {
          final int offset =
              ((dy * scale).round() * image.width + (dx * scale).round()) * 4;
          return Color.fromARGB(
            bytes.getUint8(offset + 3),
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2),
          );
        }

        // 面板里贴着底部一条带的上方（同一块 Material 涂的底色）
        // vs 屏幕最底部一条（overshoot 垫色露出的位置）
        return (
          pixelAt(sheet.center.dx, math.min(sheet.bottom, logical.height) - 60),
          pixelAt(sheet.center.dx, logical.height - 6),
        );
      } finally {
        image.dispose();
      }
    }))!;
    expect(
      bottom.toARGB32(),
      body.toARGB32(),
      reason:
          '入场过程中面板底部露出了一条更实的垫色：'
          'body=${body.toARGB32().toRadixString(16)} '
          'bottom=${bottom.toARGB32().toRadixString(16)}',
    );
  });
}
