import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/backup_page.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  testWidgets('恢复确认弹窗：复选行铺满弹窗宽度（波纹不会被截断）', (tester) async {
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

    // 与「默认启动页」弹窗一致：选项行左右铺满弹窗，波纹覆盖整个宽度
    expect(
      tester.getSize(find.byType(CheckboxListTile)).width,
      moreOrLessEquals(tester.getSize(surface).width, epsilon: 0.5),
    );
    expect(
      tester.getTopLeft(find.byType(CheckboxListTile)).dx,
      moreOrLessEquals(tester.getTopLeft(surface).dx, epsilon: 0.5),
    );
  });
}
