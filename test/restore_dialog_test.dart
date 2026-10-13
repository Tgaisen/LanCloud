import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/backup_page.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  testWidgets('恢复确认弹窗：复选行在列表组里，组沿距内容边距 24dp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showRestoreConfirmDialog(
                context,
                label: 'lancloud-backup.json',
                hasFavorites: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 弹窗真正的内容面板（AlertDialog 自身是铺满屏幕的布局盒子）
    final surface = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Material),
        )
        .first;

    // 选项行放进列表组（与选择弹窗同一套样式）：行铺满组宽，组沿距弹窗
    // 内容边距 24dp（M3 对话框规范）
    final group = find.byType(DialogListGroup);
    expect(group, findsOneWidget);
    final row = find.descendant(of: group, matching: find.byType(M3ePickTile));
    expect(
      tester.getSize(row).width,
      moreOrLessEquals(tester.getSize(group).width, epsilon: 0.5),
    );
    expect(
      tester.getTopLeft(group).dx - tester.getTopLeft(surface).dx,
      moreOrLessEquals(24, epsilon: 0.5),
    );
  });
}
