import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'cookie_sheet.dart';

/// “显示 Cookie”设置行；只随当前账号切换重建。
class ShowCookieSettingsTile extends StatelessWidget {
  const ShowCookieSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.select<AppController, String?>(
      (app) => app.activeUid,
    );
    final account = uid == null
        ? null
        : context.read<AppController>().activeAccount;
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
