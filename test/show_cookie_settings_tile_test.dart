import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/account_state.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/show_cookie_settings_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('显示 Cookie 行只随当前账号变化局部刷新', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final app = AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountStateProvider.overrideWithValue(app.accountState),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: ShowCookieSettingsTile()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.byType(ListTile);
    expect(tester.widget<ListTile>(tile).enabled, isFalse);

    app.accounts.accounts.add(
      Account(uid: '556911', cookie: 'c', nickname: '土豆'),
    );
    app.accounts.activeUid = '556911';
    await app.setSortMode('name');
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(tile).enabled, isFalse);

    app.accountState.notifyAccountChanged();
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(tile).enabled, isTrue);
  });
}
