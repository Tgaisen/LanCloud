import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:lancloud/core/data/app_db_provider.dart';

void main() {
  test('appDbProvider 暴露应用唯一的数据库实例', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final first = container.read(appDbProvider);
    final second = container.read(appDbProvider);

    expect(identical(first, AppDb.instance), isTrue);
    expect(identical(first, second), isTrue);
  });
}
