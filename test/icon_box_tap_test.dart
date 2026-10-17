import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // Windows：点图标块 = 长按（进入多选并选中），不能同时触发整行的点击。
  testWidgets('点图标块只触发 onIconTap，不触发整行 onTap', (tester) async {
    var iconTaps = 0;
    var rowTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Md3ListItem(
            icon: Icons.folder,
            title: '条目',
            animateIn: false,
            onTap: () => rowTaps++,
            onIconTap: () => iconTaps++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.folder));
    await tester.pumpAndSettle();
    expect(iconTaps, 1);
    expect(rowTaps, 0, reason: '点图标不应同时打开条目');

    // 点文字区域仍然是整行的点击
    await tester.tap(find.text('条目'));
    await tester.pumpAndSettle();
    expect(rowTaps, 1);
    expect(iconTaps, 1);
  });

  testWidgets('没有 onIconTap 时图标块不额外响应', (tester) async {
    var rowTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Md3ListItem(
            icon: Icons.folder,
            title: '条目',
            animateIn: false,
            onTap: () => rowTaps++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 没有 onIconTap 时，点图标落在整行上（正常打开）
    await tester.tap(find.byIcon(Icons.folder));
    await tester.pumpAndSettle();
    expect(rowTaps, 1);
  });

  test('iconTapFor：未选中走长按、已选中走整行点击、无鼠标为 null', () {
    var rowTaps = 0;
    var longPresses = 0;
    void onTap() => rowTaps++;
    void onLongPress() => longPresses++;

    PointerSupport.hasMouse.value = false;
    expect(
      iconTapFor(selected: false, onTap: onTap, onLongPress: onLongPress),
      isNull,
      reason: '纯触摸时图标块不额外响应',
    );

    PointerSupport.hasMouse.value = true;
    try {
      iconTapFor(selected: false, onTap: onTap, onLongPress: onLongPress)!();
      expect(longPresses, 1, reason: '未选中 → 进入多选并选中');
      expect(rowTaps, 0);

      iconTapFor(selected: true, onTap: onTap, onLongPress: onLongPress)!();
      expect(rowTaps, 1, reason: '已选中 → 取消选中');
      expect(longPresses, 1);

      expect(
        iconTapFor(selected: false, onTap: onTap, onLongPress: null),
        isNull,
        reason: '该页不支持多选时不响应',
      );
    } finally {
      PointerSupport.hasMouse.value = false;
    }
  });

  testWidgets('检测到鼠标悬停后才启用鼠标交互', (tester) async {
    PointerSupport.hasMouse.value = false;
    addTearDown(() => PointerSupport.hasMouse.value = false);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            MousePresenceDetector(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Center(child: Text('内容'))),
      ),
    );

    // 触摸点击不算鼠标
    await tester.tap(find.text('内容'));
    await tester.pump();
    expect(PointerSupport.hasMouse.value, isFalse);

    // 鼠标悬停算
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('内容')));
    await tester.pump();
    expect(PointerSupport.hasMouse.value, isTrue);
    await gesture.removePointer();
  });
}
