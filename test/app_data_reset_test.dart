import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_data_reset.dart';
import 'package:path/path.dart' as p;

void main() {
  test('应用数据目录不存在时先创建再交给资源管理器打开', () async {
    final root = await Directory.systemTemp.createTemp('lancloud-reset-open');
    addTearDown(() async {
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    });
    final support = Directory(p.join(root.path, 'support'));
    final started = <({String executable, List<String> arguments})>[];
    final service = PlatformAppDataResetService(
      applicationSupportDirectory: () async => support,
      temporaryDirectory: () async => root,
      startProcess: (executable, arguments) async {
        started.add((executable: executable, arguments: arguments));
      },
    );

    expect(await service.openAppDataDirectory(), isTrue);
    expect(await support.exists(), isTrue);
    expect(started, hasLength(1));
    expect(started.single.executable, 'explorer.exe');
    expect(started.single.arguments, [support.path]);
  });

  test('删除所有数据会按顺序取消传输、删库并清理应用自有数据', () async {
    final root = await Directory.systemTemp.createTemp('lancloud-reset-all');
    addTearDown(() async {
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    });
    final support = Directory(p.join(root.path, 'support'));
    final documents = Directory(p.join(root.path, 'documents'));
    final logs = Directory(p.join(documents.path, 'logs'));
    await support.create(recursive: true);
    await File(p.join(support.path, 'lancloud.db')).writeAsString('db');
    await logs.create(recursive: true);
    await File(p.join(logs.path, 'lancloud.log')).writeAsString('log');
    final otherLog = File(p.join(logs.path, 'other-app.log'));
    await otherLog.writeAsString('keep');

    var cancelled = false;
    var databaseDeleted = false;
    var preferencesCleared = false;
    var secureStorageCleared = false;
    var cacheCleared = false;
    int? exitCode;
    final service = PlatformAppDataResetService(
      applicationSupportDirectory: () async => support,
      applicationDocumentsDirectory: () async => documents,
      temporaryDirectory: () async => root,
      clearPreferences: () async {
        preferencesCleared = true;
      },
      clearSecureStorage: () async {
        secureStorageCleared = true;
      },
      clearCache: () async {
        cacheCleared = true;
        return 0;
      },
      removeRegistryEntry: () => true,
      exitApplication: (code) => exitCode = code,
    );

    await service.resetAndExit(
      cancelTransfers: () async => cancelled = true,
      deleteDatabase: () async => databaseDeleted = true,
    );

    expect(cancelled, isTrue);
    expect(databaseDeleted, isTrue);
    expect(preferencesCleared, isTrue);
    expect(secureStorageCleared, isTrue);
    expect(cacheCleared, isTrue);
    expect(await support.exists(), isFalse);
    expect(await File(p.join(logs.path, 'lancloud.log')).exists(), isFalse);
    expect(await otherLog.readAsString(), 'keep');
    expect(exitCode, 0);
    expect(
      await File(p.join(root.path, 'lancloud_reset_pending')).exists(),
      isFalse,
    );
  });

  test('立即清理未完全成功时，下次启动会继续补清理', () async {
    final root = await Directory.systemTemp.createTemp('lancloud-reset-retry');
    addTearDown(() async {
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    });
    final support = Directory(p.join(root.path, 'support'));
    final documents = Directory(p.join(root.path, 'documents'));
    final logs = Directory(p.join(documents.path, 'logs'));
    await support.create(recursive: true);
    await logs.create(recursive: true);
    int? exitCode;
    final first = PlatformAppDataResetService(
      applicationSupportDirectory: () async => support,
      applicationDocumentsDirectory: () async => documents,
      temporaryDirectory: () async => root,
      clearPreferences: () async {},
      clearSecureStorage: () async {},
      clearCache: () async => 0,
      removeDirectory: (directory) async => false,
      removeRegistryEntry: () => true,
      exitApplication: (code) => exitCode = code,
    );

    await first.resetAndExit(
      cancelTransfers: () async {},
      deleteDatabase: () async {},
    );

    final marker = File(p.join(root.path, 'lancloud_reset_pending'));
    expect(exitCode, 0);
    expect(await marker.exists(), isTrue);

    final retry = PlatformAppDataResetService(
      applicationSupportDirectory: () async => support,
      applicationDocumentsDirectory: () async => documents,
      temporaryDirectory: () async => root,
      clearCache: () async => 0,
      removeRegistryEntry: () => true,
    );
    expect(await retry.completePendingReset(), isTrue);
    expect(await marker.exists(), isFalse);
  });
}
