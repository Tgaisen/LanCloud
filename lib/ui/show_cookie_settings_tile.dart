import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:provider/provider.dart';

import '../core/account_state.dart';
import '../core/app_controller.dart';
import '../core/data/account_store.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'cookie_sheet.dart';

/// “显示 Cookie”设置行；只随当前账号切换重建。
class ShowCookieSettingsTile extends StatelessWidget {
  const ShowCookieSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    try {
      final accountState = ProviderScope.containerOf(
        context,
      ).read(accountStateProvider);
      return ListenableBuilder(
        listenable: accountState,
        builder: (context, _) =>
            _buildTile(context, accountState.store.active),
      );
    } on StateError {
      // 迁移期兼容尚未挂 ProviderScope 的旧测试宿主。
    } on ProviderException {
      // ProviderScope 存在但应用级状态未覆盖时，同样回退旧测试宿主。
    }
    final uid = context.select<AppController, String?>(
      (app) => app.activeUid,
    );
    final account = uid == null
        ? null
        : context.read<AppController>().activeAccount;
    return _buildTile(context, account);
  }

  Widget _buildTile(BuildContext context, Account? account) {
    final l10n = context.l10n;
    return ListTile(
      leading: const Icon(Icons.key_outlined),
      title: Text(l10n.showCookie),
      subtitle: Text(l10n.showCookieSubtitle),
      enabled: account != null,
      onTap: account == null ? null : () => showCookieFlow(context, account),
    );
  }
}
