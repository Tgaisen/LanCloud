import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/backup/backup_dependencies.dart';
import 'package:lancloud/core/backup/backup_sections.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/webdav_client.dart';
import 'package:lancloud/core/backup/webdav_store.dart';
import 'package:lancloud/core/foreground_task_coordinator.dart';
import 'package:lancloud/core/notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MemoryWebdavStore extends WebdavStore {
  Map<String, String>? _secureAccount;

  @override
  Future<Map<String, String>?> readSecureAccount() async =>
      _secureAccount == null ? null : Map.of(_secureAccount!);

  @override
  Future<void> writeSecureAccount(Map<String, String> value) async {
    _secureAccount = Map.of(value);
  }

  @override
  Future<void> deleteSecureAccount() async => _secureAccount = null;
}

class _FakeWebdavClient extends WebdavClient {
  _FakeWebdavClient() : super(url: 'https://dav.example.com/blue/');

  final Completer<void> uploadStarted = Completer<void>();
  Completer<void>? uploadGate;
  Object? failure;
  int uploadCalls = 0;

  @override
  Future<void> ensureDirectory({CancelToken? cancelToken}) async {}

  @override
  Future<void> upload(
    String name,
    String content, {
    CancelToken? cancelToken,
  }) async {
    uploadCalls += 1;
    if (!uploadStarted.isCompleted) uploadStarted.complete();
    final gate = uploadGate;
    if (gate != null) await gate.future;
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<List<WebdavEntry>> list({CancelToken? cancelToken}) async =>
      const <WebdavEntry>[];
}

class _RecordingNotificationSink implements WebdavBackupNotificationSink {
  int shown = 0;
  int canceled = 0;

  @override
  Future<void> showWebdavBackupProgress() async {
    shown += 1;
  }

  @override
  Future<void> cancelWebdavBackupProgress() async {
    canceled += 1;
  }
}

class _RecordingBackend implements ForegroundTaskBackend {
  final List<String> events = [];

  @override
  void start({required String title, required String text}) {
    events.add('start');
  }

  @override
  void update({required String title, required String text}) {
    events.add('update');
  }

  @override
  void stop() {
    events.add('stop');
  }
}

Future<void> _noopReload() async {}

BackupDependencies _dependencies(AppEnvironment environment) =>
    BackupStoreDependencies(
      accounts: environment.accountState.store,
      settings: environment.settingsState.store,
      db: environment.db,
      reloadCallback: _noopReload,
    );

Future<
  ({
    BackupService service,
    _MemoryWebdavStore store,
    _FakeWebdavClient client,
    _RecordingNotificationSink notifications,
    ForegroundTaskCoordinator foregroundTasks,
    _RecordingBackend backend,
  })
>
_configuredService({
  required DateTime Function() clock,
  bool autoBackup = true,
}) async {
  final environment = AppEnvironment();
  addTearDown(environment.dispose);
  await environment.settingsState.store.load();
  final store = _MemoryWebdavStore();
  await store.saveServer(
    url: 'https://dav.example.com/blue/',
    username: 'user',
    password: 'password',
    path: '/LanCloud',
  );
  await store.setBackupSections({
    BackupSection.favorites,
    BackupSection.settings,
  });
  await store.setAutoBackup(autoBackup);

  final client = _FakeWebdavClient();
  final notifications = _RecordingNotificationSink();
  final backend = _RecordingBackend();
  final foregroundTasks = ForegroundTaskCoordinator(backend);
  final service = BackupService(
    _dependencies(environment),
    webdav: store,
    notifications: notifications,
    foregroundTasks: foregroundTasks,
    clientFactory: () => client,
    clock: clock,
  );
  return (
    service: service,
    store: store,
    client: client,
    notifications: notifications,
    foregroundTasks: foregroundTasks,
    backend: backend,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('手动备份期间自动备份不重复，成功后更新 lastSuccessAt', () async {
    final now = DateTime(2026, 11, 16, 10);
    final harness = await _configuredService(clock: () => now);
    harness.client.uploadGate = Completer<void>();

    final manual = harness.service.uploadNow(now: now);
    await harness.client.uploadStarted.future;
    expect(harness.service.webdavBackupRunning.value, isTrue);
    expect(harness.foregroundTasks.activeReasons, {
      ForegroundTaskReason.webdavBackup,
    });
    expect(harness.notifications.shown, 1);

    await expectLater(
      harness.service.uploadNow(),
      throwsA(isA<BackupBusyException>()),
    );
    await harness.service.maybeAutoBackup();
    expect(harness.client.uploadCalls, 1);

    harness.client.uploadGate!.complete();
    expect(await manual, 'lancloud-backup-20261116-100000.json');
    expect(harness.client.uploadCalls, 2);
    expect(harness.store.lastSuccessAt, now.millisecondsSinceEpoch);
    expect(harness.store.lastAttemptAt, now.millisecondsSinceEpoch);
    expect(harness.service.webdavBackupRunning.value, isFalse);
    expect(harness.foregroundTasks.activeReasons, isEmpty);
    expect(harness.notifications.canceled, 1);
    expect(harness.backend.events, ['start', 'stop']);
  });

  test('自动备份期间手动入口被 single-flight 拒绝', () async {
    final now = DateTime(2026, 11, 16, 10);
    final harness = await _configuredService(clock: () => now);
    harness.client.uploadGate = Completer<void>();

    final automatic = harness.service.maybeAutoBackup();
    await harness.client.uploadStarted.future;
    expect(harness.service.webdavBackupRunning.value, isTrue);

    await expectLater(
      harness.service.uploadNow(),
      throwsA(isA<BackupBusyException>()),
    );
    expect(harness.client.uploadCalls, 1);

    harness.client.uploadGate!.complete();
    await automatic;
    expect(harness.store.lastSuccessAt, now.millisecondsSinceEpoch);
    expect(harness.service.webdavBackupRunning.value, isFalse);
  });

  test('自动备份失败只记尝试时间，并按一小时冷却重试', () async {
    var now = DateTime(2026, 11, 16, 10);
    final harness = await _configuredService(clock: () => now);
    final oldSuccess = now.subtract(const Duration(days: 2));
    await harness.store.markBackup(now: oldSuccess);
    harness.client.failure = const BackupException('network failed');

    await harness.service.maybeAutoBackup();
    expect(harness.client.uploadCalls, 1);
    expect(harness.store.lastSuccessAt, oldSuccess.millisecondsSinceEpoch);
    expect(harness.store.lastAttemptAt, now.millisecondsSinceEpoch);
    expect(harness.store.lastBackupError, 'network failed');

    now = now.add(const Duration(minutes: 30));
    await harness.service.maybeAutoBackup();
    expect(harness.client.uploadCalls, 1);

    now = now.add(const Duration(minutes: 31));
    await harness.service.maybeAutoBackup();
    expect(harness.client.uploadCalls, 2);
  });

  test('未到成功备份周期时不发起自动备份', () async {
    var now = DateTime(2026, 11, 16, 10);
    final harness = await _configuredService(clock: () => now);
    await harness.store.markBackup(
      now: now.subtract(const Duration(hours: 23)),
    );

    await harness.service.maybeAutoBackup();
    expect(harness.client.uploadCalls, 0);

    now = now.add(const Duration(days: 1));
    await harness.service.maybeAutoBackup();
    expect(harness.client.uploadCalls, 2);
  });
}
