import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/account_state.dart';
import '../core/data/account_store.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'cookie_sheet.dart';

/// “显示 Cookie”设置行；只随当前账号切换重建。
class ShowCookieSettingsTile extends ConsumerWidget {
  const ShowCookieSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountState = ref.watch(accountStateProvider);
    return ListenableBuilder(
      listenable: accountState,
      builder: (context, _) => _buildTile(context, accountState.store.active),
    );
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
