import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/backup_service_provider.dart';

void main() {
  test('备份服务必须由应用入口覆盖并保持同一实例', () {
    final empty = ProviderContainer();
    addTearDown(empty.dispose);
    expect(
      () => empty.read(backupServiceProvider),
      throwsA(isA<ProviderException>()),
    );

    final app = AppController();
    final service = BackupService(app);
    final container = ProviderContainer(
      overrides: [
        backupServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(app.dispose);
    addTearDown(container.dispose);
    expect(container.read(backupServiceProvider), same(service));
  });
}
