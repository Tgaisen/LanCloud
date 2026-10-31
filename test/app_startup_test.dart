import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/app_startup.dart';
import 'package:lancloud/core/data/account_store.dart';

void main() {
  test('初始化先完成安全存储检查与同步加载，后台任务不阻塞 ready', () async {
    final order = <String>[];
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    final refresh = Completer<void>();
    final dynamicColor = Completer<void>();
    final startup = AppStartup(
      environment: environment,
      onChanged: () => order.add('changed'),
      secureStorageUpgradeCheck: () async {
        order.add('secure-storage');
        return null;
      },
      loadAccounts: () async => order.add('accounts'),
      loadSettings: () async => order.add('settings'),
      applyRuntimeSettings: () => order.add('runtime-settings'),
      bindDriveCache: (uid) async => order.add('bind-cache'),
      refreshActiveAccountInfo: () {
        order.add('refresh-account');
        return refresh.future;
      },
      enableDynamicColorIfUnset: () {
        order.add('dynamic-color');
        return dynamicColor.future;
      },
    );

    await startup.initialize();

    expect(environment.runtimeState.ready.value, isTrue);
    expect(order, [
      'secure-storage',
      'accounts',
      'settings',
      'runtime-settings',
      'bind-cache',
      'changed',
      'refresh-account',
      'dynamic-color',
    ]);
    expect(refresh.isCompleted, isFalse);
    expect(dynamicColor.isCompleted, isFalse);

    refresh.complete();
    dynamicColor.complete();
    await Future.wait([refresh.future, dynamicColor.future]);
  });

  test('备份恢复先重载存储再同步运行时并刷新账号', () async {
    final order = <String>[];
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    environment.runtimeState.secureStorageNeedsReauthentication.value = true;
    var accountChanges = 0;
    environment.accountState.addListener(() => accountChanges += 1);
    final startup = AppStartup(
      environment: environment,
      onChanged: () => order.add('changed'),
      loadAccounts: () async {
        order.add('accounts');
        environment.accountState.store.accounts = [
          Account(uid: '1', cookie: 'cookie'),
        ];
        environment.accountState.store.activeUid = '1';
      },
      loadSettings: () async => order.add('settings'),
      applyRuntimeSettings: () => order.add('runtime-settings'),
      bindDriveCache: (uid) async => order.add('bind-cache'),
      refreshActiveAccountInfo: () async => order.add('refresh-account'),
    );

    await startup.reloadFromStorage();

    expect(
      environment.runtimeState.secureStorageNeedsReauthentication.value,
      isFalse,
    );
    expect(accountChanges, 1);
    expect(order, [
      'accounts',
      'settings',
      'runtime-settings',
      'bind-cache',
      'changed',
      'refresh-account',
    ]);
  });
}
