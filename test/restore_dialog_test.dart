import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/backup_preview_view.dart';
import 'package:lancloud/ui/backup_page.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  test('保留收藏选项只在当前收藏与备份收藏都存在时出现', () {
    final withFavorites = BackupService.inspect(
      '{"app":"lancloud","tables":{"favorites":[{"ref":"a"}]}}',
    );
    final withoutFavorites = BackupService.inspect(
      '{"app":"lancloud","tables":{"favorites":[]}}',
    );

    expect(
      shouldShowKeepFavorites(preview: withFavorites, existingFavorites: 1),
      isTrue,
    );
    expect(
      shouldShowKeepFavorites(preview: withFavorites, existingFavorites: 0),
      isFalse,
    );
    expect(
      shouldShowKeepFavorites(preview: withoutFavorites, existingFavorites: 2),
      isFalse,
    );
  });

  testWidgets('恢复确认弹窗：复选行在列表组里，组沿距内容边距 24dp', (tester) async {
    const content =
        '{"app":"lancloud","format":2,"createdAt":1700000000000,'
        '"sections":["settings","favorites"],"tables":{'
        '"favorites":[{"ref":"existing"}]}}';
    final preview = BackupService.inspect(content);
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
                preview: preview,
                showKeepFavorites: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('创建时间：'), findsOneWidget);
    expect(find.text('包含内容：'), findsOneWidget);
    expect(find.text('账号：'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BackupPreviewDetails),
        matching: find.byType(ListTile),
      ),
      findsNothing,
    );
    expect(find.textContaining('将用备份里的内容覆盖本机'), findsNothing);
    expect(find.text('lancloud-backup.json'), findsNothing);
    final hint = tester.widget<InfoHintCard>(find.byType(InfoHintCard));
    expect(hint.margin, EdgeInsets.zero);
    final hintSurface = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(InfoHintCard),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (hintSurface.decoration! as BoxDecoration).color,
      Theme.of(tester.element(find.byType(InfoHintCard)))
          .colorScheme
          .secondaryContainer,
    );

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

  testWidgets('恢复摘要时间使用更新页同款相对时间', (tester) async {
    final now = DateTime(2026, 10, 20, 12);
    final createdAt = now.subtract(const Duration(minutes: 5));
    final preview = BackupService.inspect(
      '{"app":"lancloud","createdAt":${createdAt.millisecondsSinceEpoch},'
      '"sections":["settings"],"tables":{}}',
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: BackupPreviewDetails(
            preview: preview,
            plainText: true,
            now: now,
            infoText: '提示',
          ),
        ),
      ),
    );

    expect(find.text('5分钟前'), findsOneWidget);
  });

  testWidgets('恢复向导里的提示卡水平边距与选项组一致', (tester) async {
    final preview = BackupService.inspect(
      '{"app":"lancloud","sections":["settings"],"tables":{}}',
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: BackupPreviewDetails(preview: preview, infoText: '提示'),
        ),
      ),
    );

    expect(
      tester.widget<InfoHintCard>(find.byType(InfoHintCard)).margin,
      const EdgeInsets.only(left: 4, right: 4),
    );
  });
}
