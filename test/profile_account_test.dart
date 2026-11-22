import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/transfer/transfer_issue.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'support/profile_page_test_support.dart';

void main() {
  testWidgets('「我的」账号卡片：普通用户不显示等级卡片，会员等级显示', (tester) async {
    Widget tree(AppEnvironment app) => ProfileTestProviders.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const ProfilePage(),
      ),
    );

    final app = AppEnvironment();
    addTearDown(app.dispose);
    app.accountState.store.accounts.add(
      Account(uid: '556911', cookie: 'c', nickname: '土豆'),
    );
    app.accountState.store.activeUid = '556911';
    await tester.pumpWidget(tree(app));
    await tester.pumpAndSettle();

    expect(find.text('土豆'), findsOneWidget);
    // 头像首字母是装饰：读屏跳过它（账号信息由标题 / 副标题播报）
    expect(
      find.ancestor(
        of: find.byType(CircleAvatar),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    // 等级还没取到（按普通用户「普」处理）：不显示卡片
    expect(find.text('普'), findsNothing);

    // 截取到会员等级后显示小卡片
    app.accountState.store.byUid('556911')!.level = '白';
    app.accountState.notifyAccountChanged();
    await tester.pumpAndSettle();
    expect(find.text('白'), findsOneWidget);

    // 调成普通用户「普」：卡片隐藏
    app.accountState.store.byUid('556911')!.level = '普';
    app.accountState.notifyAccountChanged();
    await tester.pumpAndSettle();
    expect(find.text('普'), findsNothing);
  });

  testWidgets('管理账号弹窗：两个列表组，容器色比弹窗底高一档、窗体边距 16dp', (tester) async {
    final app = AppEnvironment();
    addTearDown(app.dispose);
    final manager = buildTransferManagerForEnvironment(app);
    addTearDown(manager.dispose);
    app.accountState.store.accounts.add(
      Account(uid: '556911', cookie: 'c', nickname: '土豆'),
    );
    app.accountState.store.activeUid = '556911';
    await tester.pumpWidget(
      ProfileTestProviders.value(
        value: app,
        transferManager: manager,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('切换'));
    await tester.pumpAndSettle();

    // 弹窗里：账号组 + 退出登录组，共 2 组
    final lists = tester
        .widgetList<SegmentedList>(
          find.descendant(
            of: find.byType(M3EBottomSheet),
            matching: find.byType(SegmentedList),
          ),
        )
        .toList();
    expect(lists, hasLength(2));
    final scheme = Theme.of(tester.element(find.byType(ProfilePage)))
        .colorScheme;
    for (final list in lists) {
      // 比弹窗底（surfaceContainerLow）高一档容器色
      expect(list.color, scheme.surfaceContainer);
    }
    // 组 1 是普通组外边距；组 2 是弹窗内容的最后一块：底边与左右同值（16dp）
    expect(lists[0].margin, const EdgeInsets.fromLTRB(16, 4, 16, 4));
    expect(lists[1].margin, SheetListGroup.endMargin);
    // 退出登录单独一组（第二组只有它一项）
    expect(
      find.descendant(
        of: find.byType(M3EBottomSheet),
        matching: find.text('退出登录'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('切换账号会确认中断上传，并把任务保留为可重试失败记录', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final app = AppEnvironment();
    addTearDown(app.dispose);
    final manager = buildTransferManagerForEnvironment(app);
    addTearDown(manager.dispose);
    app.accountState.store.accounts.addAll([
      Account(uid: 'a', cookie: 'cookie-a', nickname: '账号 A'),
      Account(uid: 'b', cookie: 'cookie-b', nickname: '账号 B'),
    ]);
    app.accountState.store.activeUid = 'a';
    final upload =
        TransferTask(
            id: 'u1',
            kind: TransferKind.upload,
            name: 'running.zip',
            accountUid: 'a',
          )
          ..status = TransferStatus.running
          ..total = 100
          ..received = 30;
    manager.tasks.add(upload);
    await tester.pumpWidget(
      ProfileTestProviders.value(
        value: app,
        transferManager: manager,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('切换'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('账号 B'));
    await tester.pumpAndSettle();
    expect(find.text('切换账号并中断上传'), findsOneWidget);
    expect(find.textContaining('当前有 1 个上传任务'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(app.accountState.store.activeUid, 'a');
    expect(upload.status, TransferStatus.running);

    await tester.tap(find.text('切换'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('账号 B'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('switch-account-upload-confirm')),
    );
    await tester.pumpAndSettle();

    expect(app.accountState.store.activeUid, 'b');
    expect(upload.status, TransferStatus.failed);
    expect(
      TransferIssue.decode(upload.error)?.code,
      TransferIssueCode.uploadInterruptedByAccountSwitch,
    );
  });

  testWidgets('移除账号弹窗：列表组复选行「清除使用数据」，勾选后确认即移除账号', (tester) async {
    // 移除账号会写安全存储：测试里换成内存实现
    FlutterSecureStorage.setMockInitialValues({});
    final app = AppEnvironment();
    addTearDown(app.dispose);
    final manager = buildTransferManagerForEnvironment(app);
    addTearDown(manager.dispose);
    app.accountState.store.accounts.add(
      Account(uid: '556911', cookie: 'c', nickname: '土豆'),
    );
    app.accountState.store.activeUid = '556911';
    await tester.pumpWidget(
      ProfileTestProviders.value(
        value: app,
        transferManager: manager,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('切换'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    // 确认弹窗：消息 + 「清除使用数据」复选行（列表组样式）
    expect(find.text('移除账号'), findsOneWidget);
    expect(find.text('清除使用数据'), findsOneWidget);
    expect(find.text('清除此账号相关数据，如快速访问、最近使用'), findsOneWidget);
    Checkbox checkbox() => tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox().value, isFalse);

    // 点行勾选（默认没勾：移除账号不动使用数据）
    await tester.tap(find.text('清除使用数据'));
    await tester.pumpAndSettle();
    expect(checkbox().value, isTrue);

    // 取消：账号还在
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(app.accountState.store.accounts, hasLength(1));

    // 重新打开并确认移除：账号从本机删掉
    await tester.tap(find.text('切换'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除使用数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    expect(app.accountState.store.accounts, isEmpty);
    expect(app.accountState.store.activeUid, isNull);
  });
}
