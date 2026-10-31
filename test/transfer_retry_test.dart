import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart' show LanzouException;
import 'package:lancloud/core/api/models.dart' show DirectFile;
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/account_store.dart' show Account;
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'transfer_dependencies_test.dart' show buildTransferManager;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // 恢复用例要真的读写数据库：桌面端测试要先把 ffi 工厂装上
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// 模拟「应用被杀后重启」的下载任务：直链丢了，只剩分享链接 + 密码。
  TransferTask restartedTask({
    String referer = 'https://share.example/f1',
    String pwd = '1abc',
  }) {
    return TransferTask(
      id: 'd1',
      kind: TransferKind.download,
      name: 'a.zip',
      accountUid: '',
      referer: referer,
      pwd: pwd,
    )..status = TransferStatus.failed;
  }

  test('重启后的下载任务：重试重新解析分享链接并重新入队', () async {
    final app = AppController();
    addTearDown(app.dispose);
    final manager = buildTransferManager(app);
    String? gotUrl;
    String? gotPwd;
    manager.debugResolveShare = (url, pwd) async {
      gotUrl = url;
      gotPwd = pwd;
      return DirectFile(name: 'a.zip', url: 'https://cdn.example/a.zip');
    };
    final task = restartedTask();
    manager.tasks.add(task);

    final message = await manager.retry('d1');

    expect(message, isNull);
    expect(gotUrl, 'https://share.example/f1');
    expect(gotPwd, '1abc');
    expect(task.url, 'https://cdn.example/a.zip');
    expect(task.status, isNot(TransferStatus.failed));
    // 测试里的直链是假的：停掉入队后的下载
    manager.removeTask('d1');
  });

  test('重启后的下载任务：解析失败时保留提示，任务仍可再试', () async {
    final app = AppController();
    addTearDown(app.dispose);
    final manager = buildTransferManager(app);
    manager.debugResolveShare = (url, pwd) async {
      throw const LanzouException('文件不存在或已取消分享');
    };
    final task = restartedTask();
    manager.tasks.add(task);

    final message = await manager.retry('d1');

    expect(message, contains('重新解析下载链接失败'));
    expect(task.status, TransferStatus.failed);
    expect(task.error, message);
  });

  test('没留分享链接的旧记录：仍然提示重新发起下载', () async {
    final app = AppController();
    addTearDown(app.dispose);
    final manager = buildTransferManager(app);
    final task = restartedTask(referer: '');
    manager.tasks.add(task);

    final message = await manager.retry('d1');

    expect(message, '应用重启后请重新发起下载');
    expect(task.status, TransferStatus.failed);
  });

  test('本会话内失败的任务（直链还在）：重试不重新解析', () async {
    final app = AppController();
    addTearDown(app.dispose);
    final manager = buildTransferManager(app);
    var resolved = 0;
    manager.debugResolveShare = (url, pwd) async {
      resolved += 1;
      throw StateError('不该走到解析');
    };
    final task = TransferTask(
      id: 'd2',
      kind: TransferKind.download,
      name: 'b.zip',
      accountUid: '',
      url: 'https://cdn.example/b.zip',
      referer: 'https://share.example/f2',
    )..status = TransferStatus.failed;
    manager.tasks.add(task);

    final message = await manager.retry('d2');

    expect(message, isNull);
    expect(resolved, 0);
    expect(task.url, 'https://cdn.example/b.zip');
    manager.removeTask('d2');
  });

  test('重启后的上传任务：源文件 + 账号都在时直接重新入队', () async {
    final app = AppController();
    addTearDown(app.dispose);
    // 上传要带账号 Cookie：内存里塞一个账号（不走安全存储）
    app.accounts.accounts.add(Account(uid: '12345', cookie: 'phpdisk_info=x'));
    app.accounts.activeUid = '12345';
    final manager = buildTransferManager(app);
    final dir = Directory.systemTemp.createTempSync('lancloud-upload');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final file = File('${dir.path}/up.zip')..writeAsStringSync('x');
    final task = TransferTask(
      id: 'u1',
      kind: TransferKind.upload,
      name: 'up.zip',
      accountUid: '12345',
      folderId: '-1',
      localFilePath: file.path,
    )..status = TransferStatus.failed;
    manager.tasks.add(task);

    final message = await manager.retry('u1');

    expect(message, isNull);
    expect(task.status, isNot(TransferStatus.failed));
    // 测试里的上传连不通：停掉入队后的请求
    manager.removeTask('u1');
  });

  test('重启后的上传任务：账号不可用时提示先登录（不再发出无 Cookie 请求）', () async {
    final app = AppController();
    addTearDown(app.dispose);
    final manager = buildTransferManager(app);
    final dir = Directory.systemTemp.createTempSync('lancloud-upload');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final file = File('${dir.path}/up.zip')..writeAsStringSync('x');
    final task = TransferTask(
      id: 'u4',
      kind: TransferKind.upload,
      name: 'up.zip',
      // 账号已被移除（或旧记录里没存账号）
      accountUid: '99999',
      folderId: '-1',
      localFilePath: file.path,
    )..status = TransferStatus.failed;
    manager.tasks.add(task);

    final message = await manager.retry('u4');

    expect(message, '请先登录后再上传');
    expect(task.status, TransferStatus.failed);
  });

  test('重启恢复：任务带回原账号（上传鉴权用）', () async {
    final app = AppController();
    addTearDown(app.dispose);
    await app.db.saveTransfer(
      id: 'u9',
      kind: 'upload',
      name: 'a.zip',
      status: 'running',
      account: '12345',
    );
    addTearDown(() => app.db.deleteTransfer('u9'));

    final manager = buildTransferManager(app);
    TransferTask? restored;
    for (var i = 0; i < 100 && restored == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      for (final task in manager.tasks) {
        if (task.id == 'u9') restored = task;
      }
    }

    expect(restored, isNotNull);
    expect(restored!.accountUid, '12345');
  });

  test('重启后的上传任务：源文件被清掉时提示重新选择', () async {
    final app = AppController();
    addTearDown(app.dispose);
    final manager = buildTransferManager(app);
    final dir = Directory.systemTemp.createTempSync('lancloud-upload');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final task = TransferTask(
      id: 'u2',
      kind: TransferKind.upload,
      name: 'gone.zip',
      accountUid: '',
      folderId: '-1',
      localFilePath: '${dir.path}/gone.zip',
    )..status = TransferStatus.failed;
    manager.tasks.add(task);

    final message = await manager.retry('u2');

    expect(message, '源文件已不存在，请重新选择文件上传');
    expect(task.status, TransferStatus.failed);
  });

  test('没留源文件路径的旧上传记录：仍提示重新上传', () async {
    final app = AppController();
    addTearDown(app.dispose);
    final manager = buildTransferManager(app);
    final task = TransferTask(
      id: 'u3',
      kind: TransferKind.upload,
      name: 'old.zip',
      accountUid: '',
    )..status = TransferStatus.failed;
    manager.tasks.add(task);

    final message = await manager.retry('u3');

    expect(message, '应用重启后无法继续该上传，请重新上传');
    expect(task.status, TransferStatus.failed);
  });
}
