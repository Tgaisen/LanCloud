import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

import '../core/notification_settings_state.dart';
import '../core/notifications.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';

/// 单个传输通知设置行；权限申请结果可回传给“管理权限”入口。
class NotificationSettingsTile extends ConsumerStatefulWidget {
  const NotificationSettingsTile({
    super.key,
    required this.done,
    this.onPermissionChanged,
    this.requestPermission,
  });

  /// false = 进度通知；true = 完成/失败通知。
  final bool done;
  final ValueChanged<bool>? onPermissionChanged;

  /// 测试注入；默认请求系统通知权限。
  final Future<bool> Function()? requestPermission;

  @override
  ConsumerState<NotificationSettingsTile> createState() =>
      _NotificationSettingsTileState();
}

class _NotificationSettingsTileState
    extends ConsumerState<NotificationSettingsTile> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(notificationSettingsStateProvider);
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => SwitchListTile(
        secondary: Icon(widget.done ? Icons.task_alt : Icons.speed),
        title: Text(
          widget.done ? context.l10n.notifDone : context.l10n.notifProgress,
        ),
        subtitle: Text(
          widget.done
              ? context.l10n.notifDoneSubtitle
              : context.l10n.notifProgressSubtitle,
        ),
        value: widget.done ? settings.notifyDone : settings.notifyProgress,
        onChanged: (value) => unawaited(_setValue(settings, value)),
      ),
    );
  }

  Future<void> _setValue(NotificationSettingsState settings, bool value) async {
    if (value) {
      final messenger = ScaffoldMessenger.of(context);
      final deniedText = context.l10n.notifPermissionDeniedHint;
      final request =
          widget.requestPermission ??
          NotificationService.instance.requestPermission;
      final granted = await request();
      widget.onPermissionChanged?.call(granted);
      if (!granted) {
        messenger.showSnackBar(SnackBar(content: Text(deniedText)));
      }
    }
    if (widget.done) {
      await settings.setNotifyDone(value);
    } else {
      await settings.setNotifyProgress(value);
    }
  }
}
