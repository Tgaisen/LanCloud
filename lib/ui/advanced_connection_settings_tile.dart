import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/transfer_connection_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';

/// 高级连接覆盖项类型。
enum AdvancedConnectionSetting { apiHost, uploadPath, userAgent }

/// API 域名显示文本。
String apiHostLabel(String host) =>
    host == 'up' ? 'up.woozooo.com' : 'pc.woozooo.com';

/// User-Agent 显示文本；空字符串表示使用客户端默认值。
String userAgentLabel(AppLocalizations l10n, String userAgent) =>
    userAgent.isEmpty ? l10n.defaultUserAgent : userAgent;

/// 选择蓝奏云接口域名。
Future<String?> showApiHostPicker(
  BuildContext context, {
  required String current,
}) {
  return _showChoice(
    context,
    title: context.l10n.apiHost,
    options: const [('pc', 'pc.woozooo.com'), ('up', 'up.woozooo.com')],
    current: current,
  );
}

/// 选择上传接口路径。
Future<String?> showUploadPathPicker(
  BuildContext context, {
  required String current,
}) {
  return _showChoice(
    context,
    title: context.l10n.uploadPath,
    options: const [
      ('html5up.php', 'html5up.php'),
      ('fileup.php', 'fileup.php'),
    ],
    current: current,
  );
}

/// 编辑自定义 User-Agent；返回空字符串表示恢复客户端默认值。
Future<String?> showUserAgentEditor(
  BuildContext context, {
  required String current,
}) async {
  final l10n = context.l10n;
  var draft = current;
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => formDialog(
      dialogContext,
      title: Text(l10n.userAgent),
      content: TextFormField(
        initialValue: current,
        maxLines: 2,
        autofocus: true,
        onChanged: (value) => draft = value,
        decoration: InputDecoration(hintText: l10n.userAgentHint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(''),
          child: Text(l10n.restoreDefault),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(draft.trim()),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
}

Future<T?> _showChoice<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T current,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DialogListGroup(
              children: [
                for (final entry in options)
                  M3ePickTile(
                    label: entry.$2,
                    selected: current == entry.$1,
                    singleSelect: true,
                    onTap: () => Navigator.of(dialogContext).pop<T>(entry.$1),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 单个高级连接覆盖项。
class AdvancedConnectionSettingsTile extends ConsumerWidget {
  const AdvancedConnectionSettingsTile({super.key, required this.setting});

  final AdvancedConnectionSetting setting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(transferConnectionSettingsStateProvider);
    final l10n = context.l10n;
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => switch (setting) {
        AdvancedConnectionSetting.apiHost => ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text(l10n.apiHost),
          subtitle: Text(apiHostLabel(settings.apiHost)),
          onTap: () => unawaited(_pickApiHost(context, settings)),
        ),
        AdvancedConnectionSetting.uploadPath => ListTile(
          leading: const Icon(Icons.cloud_upload_outlined),
          title: Text(l10n.uploadPath),
          subtitle: Text(
            settings.uploadPath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => unawaited(_pickUploadPath(context, settings)),
        ),
        AdvancedConnectionSetting.userAgent => ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: Text(l10n.userAgent),
          subtitle: Text(
            userAgentLabel(l10n, settings.userAgent),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => unawaited(_editUserAgent(context, settings)),
        ),
      },
    );
  }

  Future<void> _pickApiHost(
    BuildContext context,
    TransferConnectionSettingsState settings,
  ) async {
    final selected = await showApiHostPicker(
      context,
      current: settings.apiHost,
    );
    if (selected != null) await settings.setApiHost(selected);
  }

  Future<void> _pickUploadPath(
    BuildContext context,
    TransferConnectionSettingsState settings,
  ) async {
    final selected = await showUploadPathPicker(
      context,
      current: settings.uploadPath,
    );
    if (selected != null) await settings.setUploadPath(selected);
  }

  Future<void> _editUserAgent(
    BuildContext context,
    TransferConnectionSettingsState settings,
  ) async {
    final value = await showUserAgentEditor(
      context,
      current: settings.userAgent,
    );
    if (value != null) await settings.setUserAgent(value);
  }
}
