import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:lancloud/core/data/app_db_provider.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/favorite_monitor_models.dart';
import 'package:lancloud/core/favorite_monitor_settings_state.dart';
import 'package:lancloud/core/favorites/favorite_check_gateway.dart';
import 'package:lancloud/core/favorites/favorite_monitor.dart';
import 'package:lancloud/core/favorites/favorite_monitor_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeGateway implements FavoriteCheckGateway {
  Object? folderError;
  FolderShareDetail folder = _folder('A');
  Object? fileError;
  bool fileValid = true;
  int folderCalls = 0;
  int fileCalls = 0;
  Completer<void>? folderGate;
  Completer<void>? folderStarted;

  @override
  Future<FolderShareDetail> resolveFolder({
    required String url,
    required String pwd,
    CancelToken? cancelToken,
  }) async {
    folderCalls += 1;
    if (folderStarted != null && !folderStarted!.isCompleted) {
      folderStarted!.complete();
    }
    final gate = folderGate;
    if (gate != null) {
      if (cancelToken == null) {
        await gate.future;
      } else {
        await Future.any([gate.future, cancelToken.whenCancel]);
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      }
    }
    final error = folderError;
    if (error != null) throw error;
    return folder;
  }

  @override
  Future<bool> validateFile({
    required String url,
    required String pwd,
    CancelToken? cancelToken,
  }) async {
    fileCalls += 1;
    final error = fileError;
    if (error != null) throw error;
    return fileValid;
  }
}

class _FakeReporter implements FavoriteMonitorReporter {
  final List<String> events = [];

  @override
  Future<void> start({
    required int total,
    required FavoriteCheckOperation operation,
  }) async {
    events.add('start:${operation.name}:$total');
  }

  @override
  Future<void> progress({
    required int completed,
    required int total,
    required String name,
    required FavoriteCheckOperation operation,
  }) async {
    events.add('progress:${operation.name}:$completed/$total:$name');
  }

  @override
  Future<void> folderUpdated({
    required FavoriteItem favorite,
    required FavoriteFolderHead? head,
  }) async {
    events.add('updated:${favorite.ref}:${head?.remoteId ?? 'empty'}');
  }

  @override
  Future<void> folderUpdateCleared({required String ref}) async {
    events.add('cleared:$ref');
  }

  @override
  Future<void> finish({
    required int total,
    required int succeeded,
    required int failed,
  }) async {
    events.add('finish:$total:$succeeded:$failed');
  }
}

FolderShareDetail _folder(String remoteId) => FolderShareDetail(
  name: '分享文件夹',
  files: [
    ShareFileItem(
      remoteId: remoteId,
      name: '$remoteId.zip',
      time: '2026-11-15',
      size: '3 M',
      url: 'https://share.example/$remoteId',
    ),
  ],
);

void main() {
  late AppDb db;
  late SettingsStore settingsStore;
  late FavoriteMonitorSettingsState settings;
  late _FakeGateway gateway;
  late _FakeReporter reporter;
  late ProviderContainer container;
  late DateTime now;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    try {
      await (await AppDb.instance.db).close();
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDb.instance;
    await db.importTables({'favorites': <Object?>[]});
    settingsStore = SettingsStore();
    await settingsStore.load();
    settings = FavoriteMonitorSettingsState(settingsStore);
    gateway = _FakeGateway();
    reporter = _FakeReporter();
    now = DateTime(2026, 11, 15, 10);
    container = ProviderContainer(
      overrides: [
        appDbProvider.overrideWithValue(db),
        favoriteMonitorSettingsStateProvider.overrideWithValue(settings),
        favoriteCheckGatewayProvider.overrideWithValue(gateway),
        favoriteMonitorReporterProvider.overrideWithValue(reporter),
        favoriteMonitorClockProvider.overrideWithValue(() => now),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<FavoriteItem> addFolder([
    String ref = 'https://share.example/folder',
  ]) async {
    await db.addFavorite(kind: 'shareFolder', name: '收藏目录', ref: ref);
    return (await db.favorites()).singleWhere((item) => item.ref == ref);
  }

  test('首次检测只建立首项基线，不产生更新和完成通知', () async {
    final favorite = await addFolder();
    final monitor = container.read(favoriteMonitorProvider.notifier);

    final result = await monitor.checkFolder(favorite);

    final saved = await db.favoriteByRef(favorite.ref);
    expect(result?.succeeded, 1);
    expect(result?.updated, 0);
    expect(saved?.folderSnapshot, isA<HeadFavoriteFolderSnapshot>());
    expect(saved?.folderHasUpdate, isFalse);
    expect(
      (saved?.folderSnapshot! as HeadFavoriteFolderSnapshot).head.remoteId,
      'A',
    );
    expect(
      reporter.events.where((event) => event.startsWith('updated:')),
      isEmpty,
    );
  });

  test('首项变化后标记有更新、计数并发送一次完成提醒', () async {
    final favorite = await addFolder();
    final monitor = container.read(favoriteMonitorProvider.notifier);
    await monitor.checkFolder(favorite);
    gateway.folder = _folder('B');
    now = now.add(const Duration(minutes: 1));

    final result = await monitor.checkFolder(favorite);

    final saved = await db.favoriteByRef(favorite.ref);
    expect(result?.succeeded, 1);
    expect(result?.updated, 1);
    expect(saved?.folderHasUpdate, isTrue);
    expect(saved?.folderUpdateAt, now.millisecondsSinceEpoch);
    expect(container.read(favoriteUpdateCountProvider), 1);
    expect(reporter.events, contains('updated:${favorite.ref}:B'));
    expect(
      reporter.events.where((event) => event.startsWith('updated:')),
      hasLength(1),
    );
  });

  test('旧首项变成空文件夹也算更新，清空后 badge 归零', () async {
    final favorite = await addFolder();
    final monitor = container.read(favoriteMonitorProvider.notifier);
    await monitor.checkFolder(favorite);
    gateway.folder = FolderShareDetail(name: '分享文件夹');

    await monitor.checkFolder(favorite);
    var saved = await db.favoriteByRef(favorite.ref);
    expect(saved?.folderSnapshot, isA<EmptyFavoriteFolderSnapshot>());
    expect(saved?.folderHasUpdate, isTrue);
    expect(container.read(favoriteUpdateCountProvider), 1);

    await monitor.markFolderOpened(saved!, FolderShareDetail(name: '分享文件夹'));
    saved = await db.favoriteByRef(favorite.ref);
    expect(saved?.folderHasUpdate, isFalse);
    expect(container.read(favoriteUpdateCountProvider), 0);
    expect(reporter.events, contains('cleared:${favorite.ref}'));
  });

  test('菜单批量消除更新标志会清空 badge 并撤掉全部通知', () async {
    final first = await addFolder('https://share.example/read-all-a');
    final second = await addFolder('https://share.example/read-all-b');
    const firstSnapshot = HeadFavoriteFolderSnapshot(
      head: FavoriteFolderHead(
        remoteId: 'A',
        name: 'A.zip',
        time: '2026-11-15',
        size: '3 M',
      ),
      checkedAt: 101,
    );
    const secondSnapshot = HeadFavoriteFolderSnapshot(
      head: FavoriteFolderHead(
        remoteId: 'B',
        name: 'B.zip',
        time: '2026-11-16',
        size: '4 M',
      ),
      checkedAt: 202,
    );
    await db.saveFavoriteFolderSnapshot(
      id: first.id,
      snapshot: firstSnapshot,
      hasUpdate: true,
      updateAt: 301,
    );
    await db.saveFavoriteFolderSnapshot(
      id: second.id,
      snapshot: secondSnapshot,
      hasUpdate: true,
      updateAt: 302,
    );
    final monitor = container.read(favoriteMonitorProvider.notifier);
    await monitor.initialize();
    expect(container.read(favoriteUpdateCountProvider), 2);

    expect(await monitor.markAllFolderUpdatesRead(), 2);

    final firstSaved = await db.favoriteByRef(first.ref);
    final secondSaved = await db.favoriteByRef(second.ref);
    expect(firstSaved?.folderHasUpdate, isFalse);
    expect(firstSaved?.folderUpdateAt, isNull);
    expect(firstSaved?.folderSnapshot?.sameAs(firstSnapshot), isTrue);
    expect(secondSaved?.folderHasUpdate, isFalse);
    expect(secondSaved?.folderUpdateAt, isNull);
    expect(secondSaved?.folderSnapshot?.sameAs(secondSnapshot), isTrue);
    expect(container.read(favoriteUpdateCountProvider), 0);
    expect(
      reporter.events.where((event) => event.startsWith('cleared:')),
      unorderedEquals(['cleared:${first.ref}', 'cleared:${second.ref}']),
    );
    expect(await monitor.markAllFolderUpdatesRead(), 0);
  });

  test('提取码错误和取消分享分别保存为提取码变更与失效', () async {
    final favorite = await addFolder();
    final monitor = container.read(favoriteMonitorProvider.notifier);

    gateway.folderError = const WrongPasswordException();
    await monitor.checkFolder(favorite);
    var saved = await db.favoriteByRef(favorite.ref);
    expect(saved?.shareStatus, FavoriteShareStatus.passwordChanged);
    expect(container.read(favoriteShareIssueCountProvider), 1);

    gateway.folderError = const LanzouException(
      '文件夹不存在',
      code: LanzouErrorCode.folderShareUnavailable,
    );
    await monitor.checkFolder(favorite);
    saved = await db.favoriteByRef(favorite.ref);
    expect(saved?.shareStatus, FavoriteShareStatus.unavailable);
  });

  test('普通网络错误不会把收藏标成失效', () async {
    final favorite = await addFolder();
    final monitor = container.read(favoriteMonitorProvider.notifier);

    gateway.folderError = StateError('network down');
    final result = await monitor.checkFolder(favorite);

    final saved = await db.favoriteByRef(favorite.ref);
    expect(result?.hasFailures, isTrue);
    expect(saved?.shareStatus, FavoriteShareStatus.unchecked);
    expect(container.read(favoriteShareIssueCountProvider), 0);
  });

  test('批量任务互斥，运行中再次触发返回 null', () async {
    await addFolder();
    final monitor = container.read(favoriteMonitorProvider.notifier);
    final gate = Completer<void>();
    gateway.folderGate = gate;

    final first = monitor.checkFolders();
    await Future<void>.delayed(Duration.zero);
    final second = await monitor.checkFolders();
    expect(second, isNull);

    gate.complete();
    expect((await first)?.succeeded, 1);
  });

  test('取消批量检测后停止后续项目且不把剩余项计为失败', () async {
    await addFolder('https://share.example/folder-a');
    await addFolder('https://share.example/folder-b');
    final monitor = container.read(favoriteMonitorProvider.notifier);
    gateway.folderGate = Completer<void>();
    gateway.folderStarted = Completer<void>();
    final cancelToken = CancelToken();
    final progress = <String>[];

    final checking = monitor.checkFolders(
      cancelToken: cancelToken,
      onProgress: (completed, total, name) {
        progress.add('$completed/$total:$name');
      },
    );
    await gateway.folderStarted!.future;
    cancelToken.cancel('用户取消');

    final result = await checking;
    expect(result?.total, 2);
    expect(result?.succeeded, 0);
    expect(result?.failed, 0);
    expect(gateway.folderCalls, 1);
    expect(progress, ['1/2:收藏目录']);
    expect(reporter.events, contains('start:folderUpdates:2'));
  });

  test('手动失效检测覆盖文件和文件夹，但不改已有文件夹快照', () async {
    final folder = await addFolder();
    await db.addFavorite(
      kind: 'shareFile',
      name: '收藏文件',
      ref: 'https://share.example/file',
    );
    final monitor = container.read(favoriteMonitorProvider.notifier);
    await monitor.checkFolder(folder);
    final before = (await db.favoriteByRef(folder.ref))!.folderSnapshot!
        .encode();
    gateway.folder = _folder('NEW');

    final result = await monitor.checkAllShareAccess();

    final savedFolder = await db.favoriteByRef(folder.ref);
    expect(reporter.events, contains('start:shareAccess:2'));
    expect(result?.succeeded, 2);
    expect(gateway.fileCalls, 1);
    expect(savedFolder?.folderSnapshot!.encode(), before);
    expect(savedFolder?.folderHasUpdate, isFalse);
  });

  test('手动失效检测统计明确失效项目，提取码问题仍算检测失败', () async {
    await addFolder();
    await db.addFavorite(
      kind: 'shareFile',
      name: '失效文件',
      ref: 'https://share.example/invalid-file',
    );
    final monitor = container.read(favoriteMonitorProvider.notifier);
    gateway.fileError = const LanzouException(
      '文件不存在',
      code: LanzouErrorCode.fileShareUnavailable,
    );

    final result = await monitor.checkAllShareAccess();

    expect(result?.succeeded, 1);
    expect(result?.failed, 1);
    expect(result?.invalid, 1);
    expect(container.read(favoriteShareIssueCountProvider), 1);
  });

  test('自动检测只在开启、到期且不运行时执行', () async {
    await addFolder();
    final monitor = container.read(favoriteMonitorProvider.notifier);
    await monitor.initialize();

    expect(await monitor.maybeAutoCheck(), isFalse);

    await settings.setAutoCheck(true);
    expect(await monitor.maybeAutoCheck(), isTrue);
    now = now.add(const Duration(days: 1));
    expect(await monitor.maybeAutoCheck(), isFalse);

    await settings.setFrequency(FavoriteCheckFrequency.daily);
    expect(await monitor.maybeAutoCheck(), isTrue);
  });

  test('检测范围只包含指定收藏文件夹', () async {
    final first = await addFolder('https://share.example/a');
    await addFolder('https://share.example/b');
    await settings.setScope(all: false, refs: {first.ref});
    final monitor = container.read(favoriteMonitorProvider.notifier);

    final result = await monitor.checkFolders();

    expect(result?.total, 1);
    expect(gateway.folderCalls, 1);
    expect((await db.favoriteByRef(first.ref))?.folderSnapshot, isNotNull);
  });

  test('频率到期规则支持每天、每周和每月', () {
    final base = DateTime(2026, 11, 15, 10);
    expect(
      favoriteMonitorCheckDue(
        lastAttemptAt: base,
        now: base.add(const Duration(hours: 23)),
        frequency: FavoriteCheckFrequency.daily,
      ),
      isFalse,
    );
    expect(
      favoriteMonitorCheckDue(
        lastAttemptAt: base,
        now: base.add(const Duration(days: 7)),
        frequency: FavoriteCheckFrequency.weekly,
      ),
      isTrue,
    );
    expect(
      favoriteMonitorCheckDue(
        lastAttemptAt: base,
        now: DateTime(2026, 12, 15, 10),
        frequency: FavoriteCheckFrequency.monthly,
      ),
      isTrue,
    );
  });
}
