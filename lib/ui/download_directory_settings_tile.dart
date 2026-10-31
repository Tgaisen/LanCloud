import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:path_provider/path_provider.dart';

import '../core/download_dir.dart';
import '../core/download_directory_settings_state.dart';
import '../core/download_path_service.dart';
import '../core/platform_support.dart';
import '../core/saf_storage.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';

/// 下载目录弹窗动作。
enum DownloadDirectoryAction { restoreDefault, change }

/// 显示当前下载目录并让用户选择操作。
Future<DownloadDirectoryAction?> showDownloadDirectoryDialog(
  BuildContext context, {
  required String current,
  required bool android,
}) {
  final l10n = context.l10n;
  return showDialog<DownloadDirectoryAction>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.downloadDir),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(current),
          if (android) ...[
            const SizedBox(height: 12),
            Text(
              l10n.downloadDirHint,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext)
                  .pop(DownloadDirectoryAction.restoreDefault),
          child: Text(l10n.restoreDefault),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(DownloadDirectoryAction.change),
          child: Text(l10n.change),
        ),
      ],
    ),
  );
}

/// 下载目录入口：默认路径解析、目录分类和系统选择器都由本组件管理。
class DownloadDirectorySettingsTile extends ConsumerStatefulWidget {
  const DownloadDirectorySettingsTile({
    super.key,
    this.android,
    this.pickSafDirectory,
    this.pickDirectoryPath,
  });

  /// 测试注入；生产环境按平台能力判断。
  final bool? android;
  final Future<SafDirectory?> Function(String? initialUri)? pickSafDirectory;
  final Future<String?> Function()? pickDirectoryPath;

  @override
  ConsumerState<DownloadDirectorySettingsTile> createState() =>
      _DownloadDirectorySettingsTileState();
}

class _DownloadDirectorySettingsTileState
    extends ConsumerState<DownloadDirectorySettingsTile> {
  String? _defaultPath;
  List<String> _privateRoots = const [];
  String? _publicRoot;

  bool get _isAndroid => widget.android ?? PlatformSupport.isAndroid;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDefaultPath());
  }

  Future<void> _loadDefaultPath() async {
    try {
      final path = await ref
          .read(downloadPathServiceProvider)
          .defaultDownloadDirPath();
      if (_isAndroid) {
        final roots = <String>{};
        try {
          final external = await getExternalStorageDirectory();
          if (external != null && external.path.isNotEmpty) {
            roots.add(external.path);
          }
        } catch (_) {
          // 拿不到外部专属目录就少一个私有根，不影响判断。
        }
        try {
          roots.add((await getApplicationDocumentsDirectory()).path);
        } catch (_) {
          // 拿不到内部文档目录就少一个私有根，不影响判断。
        }
        _privateRoots = roots.where((root) => root.isNotEmpty).toList();
        _publicRoot = publicStorageRootFrom(path);
      }
      if (mounted) setState(() => _defaultPath = path);
    } catch (_) {
      // 取不到路径时保持占位符，不影响设置页其余内容。
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(downloadDirectorySettingsStateProvider);
    final l10n = context.l10n;
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(l10n.downloadDir),
        subtitle: Text(
          _directoryLabel(l10n, settings, _defaultPath),
          // 默认目录会带上真实路径，比较长：允许换行显示完整路径。
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => unawaited(_changeDirectory(context, settings)),
      ),
    );
  }

  String _directoryLabel(
    AppLocalizations l10n,
    DownloadDirectorySettingsState settings,
    String? defaultPath,
  ) {
    final treeUri = settings.safariTreeUri;
    if (treeUri != null && treeUri.isNotEmpty) {
      final label = settings.safariLabel;
      final path = (label == null || label.isEmpty) ? treeUri : label;
      return _isAndroid ? l10n.customDownloadDir(path) : path;
    }
    final custom = settings.directoryPath;
    if (custom != null && custom.isNotEmpty) {
      if (!_isAndroid) return custom;
      return switch (classifyDownloadDir(
        custom,
        privateRoots: _privateRoots,
        publicRoot: _publicRoot,
      )) {
        DownloadDirKind.privateDir => l10n.privateDownloadDir(custom),
        DownloadDirKind.publicDir => l10n.publicDownloadDir(custom),
        DownloadDirKind.customDir => l10n.customDownloadDir(custom),
      };
    }
    return l10n.defaultDownloadDir(defaultPath ?? '…');
  }

  Future<void> _changeDirectory(
    BuildContext context,
    DownloadDirectorySettingsState settings,
  ) async {
    final l10n = context.l10n;
    var defaultPath = _defaultPath;
    if (defaultPath == null && _isAndroid) {
      try {
        defaultPath = await ref
            .read(downloadPathServiceProvider)
            .defaultDownloadDirPath();
      } catch (_) {
        // 取不到默认路径时用占位符，不影响弹窗其它信息。
      }
    }
    if (!context.mounted) return;
    final action = await showDownloadDirectoryDialog(
      context,
      current: _directoryLabel(l10n, settings, defaultPath),
      android: _isAndroid,
    );
    if (action == null || !context.mounted) return;
    if (action == DownloadDirectoryAction.restoreDefault) {
      await settings.selectDirectoryPath(null);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.restoredDefaultDir)));
      }
      return;
    }

    try {
      if (_isAndroid) {
        final pick =
            widget.pickSafDirectory ??
            ((initialUri) => SafStorage.pickDirectory(initialUri: initialUri));
        final dir = await pick(settings.safariTreeUri);
        if (dir == null) return;
        final direct = dir.directPath;
        if (direct != null) {
          await settings.selectDirectoryPath(direct);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.downloadDirSet(direct))),
            );
          }
          return;
        }
        await settings.selectSafariDirectory(dir);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.downloadDirSet(dir.label))),
          );
        }
        return;
      }

      final pick = widget.pickDirectoryPath ?? FilePicker.getDirectoryPath;
      final dir = await pick();
      if (dir == null || dir.isEmpty) return;
      await settings.selectDirectoryPath(dir);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.downloadDirSet(dir))));
      }
    } catch (error) {
      if (!context.mounted) return;
      final message = error is PlatformException
          ? (error.message ?? error.code)
          : '$error';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.pickDirFailed(message))));
    }
  }
}
