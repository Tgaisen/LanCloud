import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';

void main() {
  testWidgets('批量进度弹窗：内容居中、显示进度条与 1/20 计数，完成后自动关闭', (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              pageContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final gate = Completer<void>();
    late BatchProgressReport reportRef;
    final future = runBatchWithProgress(
      pageContext,
      title: '批量下载',
      total: 20,
      run: (report) async {
        reportRef = report;
        report(1, 'a.zip');
        await gate.future;
        report(5, 'e.zip');
      },
    );

    await tester.pump();
    // 标题居中
    expect(tester.widget<Text>(find.text('批量下载')).textAlign, TextAlign.center);
    // 进度条 + 计数 + 当前项
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('1/20'), findsOneWidget);
    expect(find.text('a.zip'), findsOneWidget);

    // 进度条、计数、当前项在同一中轴线上
    final barCenter = tester
        .getRect(find.byType(LinearProgressIndicator))
        .center
        .dx;
    expect(
      (tester.getCenter(find.text('1/20')).dx - barCenter).abs(),
      lessThan(1),
    );
    expect(
      (tester.getCenter(find.text('a.zip')).dx - barCenter).abs(),
      lessThan(1),
    );
    // 进度条是确定值（不是无限循环）
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, isNotNull);

    // 汇报进度后计数与当前项更新
    reportRef(5, 'e.zip');
    await tester.pump();
    expect(find.text('5/20'), findsOneWidget);
    expect(find.text('e.zip'), findsOneWidget);

    // 完成后自动关闭
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await future;
  });
}
