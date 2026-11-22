import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/backup/backup_dependencies.dart';
import 'package:lancloud/core/backup/backup_sections.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  });

  group('BackupService', () {
    testWidgets('should restore favorites through a local backup round-trip', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final databaseDirectory = Directory.systemTemp.createTempSync(
        'lancloud_integration_backup_db_',
      );
      AppDb.debugDatabaseDirectory = databaseDirectory.path;
      addTearDown(() {
        AppDb.debugDatabaseDirectory = null;
        try {
          if (databaseDirectory.existsSync()) {
            databaseDirectory.deleteSync(recursive: true);
          }
        } catch (_) {}
      });

      final environment = AppEnvironment();
      addTearDown(environment.dispose);
      final service = BackupService(
        BackupStoreDependencies(
          accounts: environment.accountState.store,
          settings: environment.settingsState.store,
          db: environment.db,
          reloadCallback: () async {},
        ),
      );

      await environment.db.addFavorite(
        kind: 'shareFile',
        name: '备份往返.txt',
        ref: 'https://example.com/backup-roundtrip',
        size: '2 M',
      );
      final content = await service.encode(
        sections: const {BackupSection.favorites},
      );

      expect(
        (await environment.db.favorites()).map((item) => item.ref),
        contains('https://example.com/backup-roundtrip'),
      );

      await environment.db.removeFavorite(
        'https://example.com/backup-roundtrip',
      );
      expect(
        (await environment.db.favorites()).map((item) => item.ref),
        isNot(contains('https://example.com/backup-roundtrip')),
      );

      await service.restoreFromString(content, restoreAccounts: false);

      final restored = (await environment.db.favorites()).singleWhere(
        (item) => item.ref == 'https://example.com/backup-roundtrip',
      );
      expect(restored.name, '备份往返.txt');
      expect(restored.size, '2 M');
    });
  });
}
