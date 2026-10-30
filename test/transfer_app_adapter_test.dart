import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:lancloud/core/transfer/transfer_app_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AppController 实现 TransferManager 的最小依赖边界', () {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final app = AppController();
    addTearDown(app.dispose);

    expect(app, isA<TransferAppAdapter>());
    expect(app.db, same(AppDb.instance));
    expect(app.accounts, same(app.accountState.store));
    expect(app.settings, same(app.settingsState.store));
    expect(app.publicClient, same(app.clientRegistry.publicClient));
  });
}
