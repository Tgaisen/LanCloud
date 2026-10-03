import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/cookie_auth.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/cookie_sheet.dart';
import 'package:local_auth/local_auth.dart';

class _FakeAuth extends CookieAuth {
  _FakeAuth(this.result);

  final CookieAuthResult result;
  int calls = 0;

  @override
  Future<CookieAuthResult> verify(String reason) async {
    calls += 1;
    return result;
  }
}

const _cookie =
    'ylogin=1234567; phpdisk_info=AbCdEfGhIjKlMnOpQrStUvWxYz0123456789';

final _account = Account(uid: '1234567', cookie: _cookie, nickname: '测试账号');

Future<void> pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showCookieFlow(context, _account),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> openFlow(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  late _FakeAuth fake;

  setUp(() {
    fake = _FakeAuth(CookieAuthResult.ok);
    CookieAuth.instance = fake;
  });

  tearDown(() {
    CookieAuth.instance = CookieAuth();
  });

  testWidgets('风险提示取消后不做身份验证，也不显示 Cookie', (tester) async {
    await pumpHost(tester);
    await openFlow(tester);

    expect(find.text('显示 Cookie？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(fake.calls, 0);
    expect(find.text(_cookie), findsNothing);
  });

  testWidgets('确认并验证通过后展示 Cookie，复制写入剪贴板', (tester) async {
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );

    await pumpHost(tester);
    await openFlow(tester);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(fake.calls, 1);
    expect(find.text('账号 Cookie'), findsOneWidget);
    expect(find.text(_cookie), findsOneWidget);

    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    final setData = platformCalls.lastWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    expect((setData.arguments as Map)['text'], _cookie);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('验证失败提示后不显示 Cookie', (tester) async {
    fake = _FakeAuth(CookieAuthResult.failed);
    CookieAuth.instance = fake;

    await pumpHost(tester);
    await openFlow(tester);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(find.text('身份验证未通过，已取消显示'), findsOneWidget);
    expect(find.text(_cookie), findsNothing);
  });

  testWidgets('设备未设置锁屏时提示不可用', (tester) async {
    fake = _FakeAuth(CookieAuthResult.unavailable);
    CookieAuth.instance = fake;

    await pumpHost(tester);
    await openFlow(tester);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(
      find.text('当前设备未设置锁屏密码或生物识别，无法验证身份'),
      findsOneWidget,
    );
  });

  testWidgets('导出把 Cookie 交给系统分享通道', (tester) async {
    MethodCall? shared;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('lancloud/share'),
      (call) async {
        shared = call;
        return true;
      },
    );

    await pumpHost(tester);
    await openFlow(tester);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();

    expect(shared?.method, 'shareText');
    expect((shared!.arguments as Map)['text'], _cookie);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('lancloud/share'),
      null,
    );
  });

  test('身份验证错误码映射：取消 / 不可用 / 失败', () {
    expect(
      cookieAuthResultFor(LocalAuthExceptionCode.userCanceled),
      CookieAuthResult.canceled,
    );
    expect(
      cookieAuthResultFor(LocalAuthExceptionCode.noCredentialsSet),
      CookieAuthResult.unavailable,
    );
    expect(
      cookieAuthResultFor(LocalAuthExceptionCode.temporaryLockout),
      CookieAuthResult.failed,
    );
  });
}
