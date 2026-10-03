import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/drive_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

CachedFolder _sample(String folderName) => CachedFolder(
      folders: [LzFolder(id: '1', name: folderName, desc: '')],
      files: const [],
      path: const [],
      page: 1,
      hasMore: false,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('绑定账号会清空上一个账号的内存缓存', () async {
    final cache = DriveCache();
    await cache.bindAccount('1');
    cache.put('-1', _sample('账号1的目录'));
    expect(cache.get('-1'), isNotNull);

    await cache.bindAccount('2');
    expect(cache.get('-1'), isNull, reason: '换账号后不应看到上一个账号的目录');
  });

  test('根目录快照按账号分开持久化', () async {
    final cache = DriveCache();
    await cache.bindAccount('1');
    cache.put('-1', _sample('账号1的目录'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await cache.bindAccount('2');
    cache.put('-1', _sample('账号2的目录'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // 换回账号 1：读到的应该是账号 1 自己的快照
    final again = DriveCache();
    await again.bindAccount('1');
    expect(again.get('-1')?.folders.first.name, '账号1的目录');

    final other = DriveCache();
    await other.bindAccount('2');
    expect(other.get('-1')?.folders.first.name, '账号2的目录');
  });
}
