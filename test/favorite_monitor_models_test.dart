import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/favorite_monitor_models.dart';

void main() {
  const first = FavoriteFolderHead(
    remoteId: 'iabc123',
    name: '首发.zip',
    time: '2026-11-15',
    size: '3 M',
  );
  const renamed = FavoriteFolderHead(
    remoteId: 'iabc123',
    name: '改名.zip',
    time: '2026-11-15',
    size: '3 M',
  );

  group('收藏文件夹首项快照', () {
    test('无旧快照时只建立基线，不产生更新', () {
      const current = HeadFavoriteFolderSnapshot(head: first, checkedAt: 100);

      expect(favoriteFolderHasChanged(null, current), isFalse);
    });

    test('首项相同不产生更新，任一指纹字段变化都产生更新', () {
      const previous = HeadFavoriteFolderSnapshot(head: first, checkedAt: 100);
      const same = HeadFavoriteFolderSnapshot(head: first, checkedAt: 200);
      const changed = HeadFavoriteFolderSnapshot(head: renamed, checkedAt: 200);

      expect(favoriteFolderHasChanged(previous, same), isFalse);
      expect(favoriteFolderHasChanged(previous, changed), isTrue);
    });

    test('空文件夹与首项互相切换都算更新', () {
      const empty = EmptyFavoriteFolderSnapshot(checkedAt: 100);
      const head = HeadFavoriteFolderSnapshot(head: first, checkedAt: 200);

      expect(favoriteFolderHasChanged(empty, head), isTrue);
      expect(favoriteFolderHasChanged(head, empty), isTrue);
      expect(favoriteFolderHasChanged(empty, empty), isFalse);
    });

    test('快照可持久化还原，损坏数据按未检测处理', () {
      const empty = EmptyFavoriteFolderSnapshot(checkedAt: 100);
      const head = HeadFavoriteFolderSnapshot(head: first, checkedAt: 200);

      expect(
        FavoriteFolderSnapshot.tryDecode(empty.encode()),
        isA<EmptyFavoriteFolderSnapshot>(),
      );
      final decoded = FavoriteFolderSnapshot.tryDecode(head.encode());
      expect(decoded, isA<HeadFavoriteFolderSnapshot>());
      expect((decoded! as HeadFavoriteFolderSnapshot).head.remoteId, 'iabc123');
      expect(FavoriteFolderSnapshot.tryDecode('{bad json'), isNull);
      expect(FavoriteFolderSnapshot.tryDecode('{"state":"head"}'), isNull);
    });
  });
}
