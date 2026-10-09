import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/api/lanzou_client.dart';
import '../core/app_controller.dart';
import '../core/drag_drop.dart';
import '../core/lanzou_link.dart';
import '../core/transfer/transfer_manager.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'drive_page.dart';
import 'share_page.dart';

/// 拖入文件的处理目标。
enum DropFileTarget {
  /// 网盘页：确认条 → 上传到当前所在目录
  currentFolder,

  /// 其它页面：走「选择目标文件夹」弹窗
  folderPicker,
}

/// 拖入链接的处理目标。
enum DropLinkTarget {
  /// 收藏页：确认条 → 解析后直接收藏
  favorites,

  /// 其它页面：打开「打开链接」弹窗
  linkDialog,
}

DropFileTarget dropFileTarget({required bool onDrivePage}) =>
    onDrivePage ? DropFileTarget.currentFolder : DropFileTarget.folderPicker;

DropLinkTarget dropLinkTarget({required bool onFavoritesPage}) =>
    onFavoritesPage ? DropLinkTarget.favorites : DropLinkTarget.linkDialog;

/// 一次拖拽的处理结果（用来拼汇总提示）。
class DropOutcome {
  const DropOutcome({
    this.uploaded = 0,
    this.favorited = 0,
    this.needsPassword = 0,
    this.duplicated = 0,
    this.failed = 0,
    this.canceled = false,
  });

  /// 用户取消了处理（不弹汇总提示）。
  static const userCanceled = DropOutcome(canceled: true);

  final int uploaded;
  final int favorited;
  final int needsPassword;
  final int duplicated;
  final int failed;
  final bool canceled;

  bool get isEmpty =>
      uploaded == 0 && favorited == 0 && needsPassword == 0 && duplicated == 0;

  DropOutcome merge(DropOutcome other) => DropOutcome(
    uploaded: uploaded + other.uploaded,
    favorited: favorited + other.favorited,
    needsPassword: needsPassword + other.needsPassword,
    duplicated: duplicated + other.duplicated,
    failed: failed + other.failed,
  );
}

/// 处理一次拖拽落下。返回 null 表示用户取消、或没有可导入的内容。
Future<DropOutcome?> handleExternalDrop(
  BuildContext context,
  DropPayload payload, {
  required bool onDrivePage,
  required bool onFavoritesPage,
}) async {
  final l10n = context.l10n;
  final files = payload.files;
  final links = LanzouLink.parseAll(payload.texts.join('\n'));

  if (files.isEmpty && links.isEmpty) {
    if (payload.hasText && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.shareTargetUnsupported)));
    }
    return null;
  }

  // 文件和链接混在一起时需要分开处理（各自复用下面的流程）
  if (files.isNotEmpty && links.isNotEmpty) {
    if (!context.mounted) return null;
    final go = await _confirmMixed(context);
    if (go != true) return DropOutcome.userCanceled;
  }

  var outcome = const DropOutcome();
  var canceled = false;
  if (files.isNotEmpty) {
    if (!context.mounted) return null;
    final fileOutcome = await _handleDroppedFiles(
      context,
      files,
      target: dropFileTarget(onDrivePage: onDrivePage),
    );
    if (fileOutcome == null) {
      // 文件这步被取消：混合拖拽里链接仍然要继续处理（两步分开走）
      canceled = true;
    } else {
      outcome = outcome.merge(fileOutcome);
    }
  }
  if (links.isNotEmpty) {
    if (!context.mounted) {
      return outcome.isEmpty ? DropOutcome.userCanceled : outcome;
    }
    final linkOutcome = await _handleDroppedLinks(
      context,
      links,
      target: dropLinkTarget(onFavoritesPage: onFavoritesPage),
    );
    if (linkOutcome == null || linkOutcome.canceled) {
      // 链接这一步被取消：文件已经处理过就照常汇总
      if (outcome.isEmpty) return DropOutcome.userCanceled;
      return outcome;
    }
    outcome = outcome.merge(linkOutcome);
  }
  if (outcome.isEmpty && canceled) return DropOutcome.userCanceled;
  return outcome;
}

/// 汇总提示：已上传 N 个文件 · 已收藏 N 条 · N 条需要提取码 · N 条已在收藏中 · N 条失败。
void showDropSummary(BuildContext context, DropOutcome outcome) {
  final l10n = context.l10n;
  final parts = <String>[
    if (outcome.uploaded > 0) l10n.dropUploaded(outcome.uploaded),
    if (outcome.favorited > 0) l10n.dropFavorited(outcome.favorited),
    if (outcome.needsPassword > 0)
      l10n.dropNeedsPassword(outcome.needsPassword),
    if (outcome.duplicated > 0) l10n.dropDuplicated(outcome.duplicated),
    if (outcome.failed > 0) l10n.dropFailed(outcome.failed),
  ];
  if (parts.isEmpty) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(parts.join('，'))));
}

/// 拖拽悬停提示条。
///
/// 挂在 App 顶层（Navigator 之上），所以包括设置、分享浏览这些二级页面
/// 在内的所有页面都能看到；内容常驻在树里，靠滑入 / 淡出过渡。
class DropHoverBanner extends StatelessWidget {
  const DropHoverBanner({super.key});

  String _hintText(AppController app, AppLocalizations l10n, DropHover hover) {
    if (hover.isMixed) return l10n.dropHoverMixed;
    if (hover.hasFiles) {
      return app.driveVisible
          ? l10n.dropHoverUpload(drivePathLabel(l10n, app.driveLocation.value))
          : l10n.dropHoverPickFolder;
    }
    return app.favoritesVisible
        ? l10n.dropHoverFavorite
        : l10n.dropHoverOpenLink;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<DropHover?>(
      valueListenable: DragDropChannel.instance.hover,
      builder: (context, hover, _) {
        final visible = hover != null && !hover.isEmpty;
        return Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            bottom: false,
            child: IgnorePointer(
              ignoring: !visible,
              child: AnimatedSlide(
                offset: visible ? Offset.zero : const Offset(0, -1.4),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Material(
                      elevation: 3,
                      borderRadius: BorderRadius.circular(16),
                      color: scheme.inverseSurface,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.trackpad_input,
                              size: 20,
                              color: scheme.onInverseSurface,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                hover == null
                                    ? ''
                                    : _hintText(app, l10n, hover),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: scheme.onInverseSurface),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- 文件

/// 返回 null 表示用户取消（未登录 / 取消选目录）。
Future<DropOutcome?> _handleDroppedFiles(
  BuildContext context,
  List<DropFile> files, {
  required DropFileTarget target,
}) async {
  final app = context.read<AppController>();
  final l10n = context.l10n;
  final client = app.client;
  if (client == null || app.activeUid == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.notLoggedIn)));
    return null;
  }

  String? folderId;
  String? rename;
  if (target == DropFileTarget.currentFolder) {
    final location = app.driveLocation.value;
    final choice = await _confirmUploadToCurrentFolder(
      context,
      files,
      pathLabel: drivePathLabel(l10n, location),
    );
    if (choice == null || choice == _UploadChoice.cancel) return null;
    if (choice == _UploadChoice.currentFolder) {
      folderId = location.id;
    }
  }
  if (folderId == null) {
    if (!context.mounted) return null;
    final picked = await showFolderPicker(
      context,
      client: client,
      confirmLabel: l10n.uploadHere,
      initialName: files.length == 1 ? files.first.name : null,
    );
    if (picked == null) return null;
    folderId = picked.folderId;
    rename = picked.fileName;
  }

  if (!context.mounted) return null;
  final transfers = context.read<TransferManager>();
  var uploaded = 0;
  var failed = 0;
  for (final file in files) {
    if (!context.mounted) break;
    // 原生在 drop 那一刻已经复制到缓存；为空说明当时没读到，再试一次
    var path = file.path;
    if (path.isEmpty) {
      path = await DragDropChannel.instance.copyToCache(file) ?? '';
    }
    if (path.isEmpty) {
      // 读取失败（URI 权限过期 / 源应用异常）：计入汇总，不静默丢
      failed += 1;
      continue;
    }
    final name = files.length == 1 && rename != null && rename.isNotEmpty
        ? rename
        : (file.name.isEmpty ? 'file' : file.name);
    transfers.addUpload(name: name, folderId: folderId, path: path);
    uploaded += 1;
  }
  return DropOutcome(uploaded: uploaded, failed: failed);
}

enum _UploadChoice { currentFolder, pickFolder, cancel }

Future<_UploadChoice?> _confirmUploadToCurrentFolder(
  BuildContext context,
  List<DropFile> files, {
  required String pathLabel,
}) {
  final l10n = context.l10n;
  return showDialog<_UploadChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.dropFilesCount(files.length)),
      // 一行显示：只问目标目录，文件名清单不再展开（标题里已有数量）
      content: Text(
        l10n.dropUploadConfirm(pathLabel),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_UploadChoice.cancel),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_UploadChoice.pickFolder),
          child: Text(l10n.dropPickAnotherFolder),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_UploadChoice.currentFolder),
          child: Text(l10n.confirm),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- 链接

Future<DropOutcome?> _handleDroppedLinks(
  BuildContext context,
  List<LanzouLink> links, {
  required DropLinkTarget target,
}) async {
  if (target == DropLinkTarget.favorites) {
    if (!context.mounted) return null;
    final go = await _confirmAddFavorites(context, links.length);
    if (go != true) return DropOutcome.userCanceled;
    if (!context.mounted) return null;
    return _addFavoritesFromLinks(context, links);
  }

  // 其它页面：多条链接先问「打开 / 批量收藏」；单条直接打开「打开链接」弹窗
  if (links.length > 1) {
    if (!context.mounted) return null;
    final action = await _confirmLinkActions(context, links.length);
    if (action == null || action == _LinkAction.cancel) {
      return DropOutcome.userCanceled;
    }
    if (action == _LinkAction.favorite) {
      if (!context.mounted) return null;
      return _addFavoritesFromLinks(context, links);
    }
  }
  for (final link in links) {
    if (!context.mounted) return const DropOutcome();
    await openShareSheet(context, initialLink: link.url, initialPwd: link.pwd);
  }
  return const DropOutcome();
}

Future<DropOutcome> _addFavoritesFromLinks(
  BuildContext context,
  List<LanzouLink> links,
) async {
  final app = context.read<AppController>();
  final client = app.publicClient;
  var favorited = 0;
  var duplicated = 0;
  var failed = 0;
  final needPassword = <LanzouLink>[];

  for (final link in links) {
    if (!context.mounted) break;
    if (await app.db.isFavorite(link.url)) {
      duplicated += 1;
      continue;
    }
    try {
      // 与「打开链接」弹窗同序：先按文件解析，失败再按文件夹试一次
      try {
        final file = await client.resolveFileShare(
          link.url,
          pwd: link.pwd ?? '',
        );
        await app.db.addFavorite(
          kind: 'shareFile',
          name: file.name,
          ref: link.url,
          pwd: link.pwd ?? '',
          size: file.size,
        );
        favorited += 1;
      } on NeedPasswordException {
        rethrow;
      } on WrongPasswordException {
        rethrow;
      } on LanzouException {
        final folder = await client.resolveFolderShare(
          link.url,
          pwd: link.pwd ?? '',
        );
        await app.db.addFavorite(
          kind: 'shareFolder',
          name: folder.name,
          ref: link.url,
          pwd: link.pwd ?? '',
          sharer: folder.sharer,
        );
        favorited += 1;
      }
    } on NeedPasswordException {
      needPassword.add(link);
    } on WrongPasswordException {
      needPassword.add(link);
    } on LanzouException {
      failed += 1;
    } catch (_) {
      failed += 1;
    }
  }

  // 需要提取码的：回退到「打开链接」弹窗，让用户补密码后收藏
  for (final link in needPassword) {
    if (!context.mounted) break;
    await openShareSheet(
      context,
      initialLink: link.url,
      initialPwd: link.pwd,
      addFavoriteOnResolve: true,
    );
  }

  return DropOutcome(
    favorited: favorited,
    needsPassword: needPassword.length,
    duplicated: duplicated,
    failed: failed,
  );
}

// ---------------------------------------------------------------- 确认弹窗

Future<bool?> _confirmMixed(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.dropMixedTitle),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.dropContinue),
        ),
      ],
    ),
  );
}

Future<bool?> _confirmAddFavorites(BuildContext context, int count) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.dropLinksCount(count)),
      content: Text(
        l10n.dropAddFavoritesHint,
        style: Theme.of(dialogContext).textTheme.bodyMedium,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.dropAddFavorites),
        ),
      ],
    ),
  );
}

enum _LinkAction { open, favorite, cancel }

/// 非收藏页拖入多条链接：逐个打开，或者直接批量收藏。
Future<_LinkAction?> _confirmLinkActions(BuildContext context, int count) {
  final l10n = context.l10n;
  return showDialog<_LinkAction>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.dropLinksCount(count)),
      content: Text(
        l10n.dropOpenLinksHint,
        style: Theme.of(dialogContext).textTheme.bodyMedium,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(_LinkAction.cancel),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_LinkAction.favorite),
          child: Text(l10n.dropBatchFavorite),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(_LinkAction.open),
          child: Text(l10n.dropOpenLinks),
        ),
      ],
    ),
  );
}
