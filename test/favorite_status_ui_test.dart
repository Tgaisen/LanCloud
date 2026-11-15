import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:lancloud/core/favorite_monitor_models.dart';
import 'package:lancloud/core/favorites/favorite_monitor.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/favorites_page.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

void main() {
  final l10n = lookupAppLocalizations(const Locale('zh'));

  test('收藏副标题：更新、提取码变更和失效状态按优先级展示', () {
    FavoriteItem folder({
      FavoriteFolderSnapshot? snapshot,
      FavoriteShareStatus status = FavoriteShareStatus.valid,
      bool hasUpdate = false,
    }) => FavoriteItem(
      id: 1,
      kind: 'shareFolder',
      name: '文件夹',
      ref: 'https://share.example/folder',
      folderSnapshot: snapshot,
      folderHasUpdate: hasUpdate,
      shareStatus: status,
    );

    expect(
      favoriteItemSubtitle(
        folder(
          snapshot: const HeadFavoriteFolderSnapshot(
            head: FavoriteFolderHead(
              remoteId: 'ihead',
              name: '最新.zip',
              time: '2026-11-15',
              size: '3 M',
            ),
            checkedAt: 1,
          ),
          hasUpdate: true,
        ),
        l10n,
      ),
      '有更新 · 2026-11-15',
    );
    expect(
      favoriteItemSubtitle(
        folder(
          snapshot: const EmptyFavoriteFolderSnapshot(checkedAt: 1),
          hasUpdate: true,
        ),
        l10n,
      ),
      '有更新',
    );
    expect(
      favoriteItemSubtitle(
        folder(hasUpdate: true, status: FavoriteShareStatus.passwordChanged),
        l10n,
      ),
      '提取码已变更',
    );
    expect(
      favoriteItemSubtitle(
        folder(hasUpdate: true, status: FavoriteShareStatus.unavailable),
        l10n,
      ),
      '已失效 · 不存在或已取消分享',
    );
  });

  group('检测结果文案', () {
    FavoriteMonitorRunResult result({
      int total = 1,
      int succeeded = 1,
      int failed = 0,
      int updated = 0,
      int invalid = 0,
    }) => FavoriteMonitorRunResult(
      total: total,
      succeeded: succeeded,
      failed: failed,
      updated: updated,
      invalid: invalid,
    );

    test('批量更新包含更新数量与失败后缀', () {
      expect(
        favoriteCheckResultMessage(
          l10n,
          result(total: 3, updated: 0),
          FavoriteCheckReportMode.batchUpdates,
        ),
        '检测完成，未检测到更新',
      );
      expect(
        favoriteCheckResultMessage(
          l10n,
          result(total: 3, updated: 2),
          FavoriteCheckReportMode.batchUpdates,
        ),
        '检测完成，检测到更新 2 项',
      );
      expect(
        favoriteCheckResultMessage(
          l10n,
          result(total: 3, failed: 1, updated: 2),
          FavoriteCheckReportMode.batchUpdates,
        ),
        '检测完成，检测到更新 2 项，检测失败 1 项',
      );
    });

    test('单项更新只显示三种简洁结果', () {
      expect(
        favoriteCheckResultMessage(
          l10n,
          result(),
          FavoriteCheckReportMode.singleUpdate,
        ),
        '未检测到更新',
      );
      expect(
        favoriteCheckResultMessage(
          l10n,
          result(updated: 1),
          FavoriteCheckReportMode.singleUpdate,
        ),
        '检测到更新',
      );
      expect(
        favoriteCheckResultMessage(
          l10n,
          result(failed: 1),
          FavoriteCheckReportMode.singleUpdate,
        ),
        '检测失败',
      );
    });

    test('失效检测包含失效数量与失败后缀', () {
      expect(
        favoriteCheckResultMessage(
          l10n,
          result(total: 3),
          FavoriteCheckReportMode.access,
        ),
        '未检测到失效项目',
      );
      expect(
        favoriteCheckResultMessage(
          l10n,
          result(total: 3, invalid: 2),
          FavoriteCheckReportMode.access,
        ),
        '检测到 2 个失效项目',
      );
      expect(
        favoriteCheckResultMessage(
          l10n,
          result(total: 3, failed: 1, invalid: 2),
          FavoriteCheckReportMode.access,
        ),
        '检测到 2 个失效项目，检测失败 1 项',
      );
    });
  });

  testWidgets('Md3ListItem 可在图标块上叠加状态标记', (tester) async {
    const indicatorKey = ValueKey('indicator');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Md3ListItem(
            icon: Icons.folder,
            title: '文件夹',
            iconIndicator: const SizedBox.square(
              key: indicatorKey,
              dimension: 10,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(indicatorKey), findsOneWidget);
  });
}
