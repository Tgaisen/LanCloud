import 'package:flutter/widgets.dart';

import '../core/app_info.dart';
import '../core/api/lanzou_client.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// 快捷访问当前语言的本地化文案：`context.l10n.xxx`。
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension AppBuildL10n on AppLocalizations {
  /// 当前构建类型的用户可见名称；Release 不追加后缀。
  String get currentAppBuildModeLabel => switch (currentAppBuildMode) {
    AppBuildMode.debug => appBuildDebug,
    AppBuildMode.profile => appBuildProfile,
    AppBuildMode.release => appBuildRelease,
  };

  String get currentAppDisplayName =>
      currentAppBuildMode == AppBuildMode.release
      ? appName
      : '$appName $currentAppBuildModeLabel';
}

/// 把可预期的 API 错误映射成当前界面语言；服务端原文仍原样兜底。
extension LanzouErrorL10n on AppLocalizations {
  String lanzouError(Object error) {
    if (error is! LanzouException) return '$error';
    final detail = error.detail?.trim() ?? '';
    return switch (error.code) {
      LanzouErrorCode.passwordRequired => shareNeedsPassword,
      LanzouErrorCode.wrongPassword => wrongPassword,
      LanzouErrorCode.invalidResponse => lanzouInvalidResponse,
      LanzouErrorCode.createFolderFailed => lanzouCreateFolderFailed,
      LanzouErrorCode.deleteFailed => lanzouDeleteFailed,
      LanzouErrorCode.moveFileFailed => lanzouMoveFileFailed,
      LanzouErrorCode.moveToCurrentFolder => lanzouMoveToCurrentFolder,
      LanzouErrorCode.moveFolderWithSubfoldersUnsupported =>
        lanzouMoveFolderWithSubfoldersUnsupported,
      LanzouErrorCode.readFolderInfoFailed => lanzouReadFolderInfoFailed,
      LanzouErrorCode.sameTargetFolder => lanzouSameTargetFolder,
      LanzouErrorCode.updateDescriptionFailed => lanzouUpdateDescriptionFailed,
      LanzouErrorCode.fileNameRequired => lanzouFileNameRequired,
      LanzouErrorCode.renameRequiresMembership =>
        lanzouRenameRequiresMembership,
      LanzouErrorCode.updateFilePasswordFailed =>
        lanzouUpdateFilePasswordFailed,
      LanzouErrorCode.folderNameRequired => lanzouFolderNameRequired,
      LanzouErrorCode.updateFolderInfoFailed => lanzouUpdateFolderInfoFailed,
      LanzouErrorCode.updateFolderPasswordFailed =>
        lanzouUpdateFolderPasswordFailed,
      LanzouErrorCode.uploadContentMissing => lanzouUploadContentMissing,
      LanzouErrorCode.uploadFailed => lanzouUploadFailed(
        detail.isEmpty ? lanzouUnknownError : detail,
      ),
      LanzouErrorCode.fileShareInfoFailed => lanzouFileShareInfoFailed,
      LanzouErrorCode.folderShareInfoFailed =>
        detail.isEmpty ? lanzouFolderShareInfoFailed : detail,
      LanzouErrorCode.resolveShareFailed => lanzouResolveShareFailed(detail),
      LanzouErrorCode.fileShareUnavailable => lanzouFileShareUnavailable,
      LanzouErrorCode.passwordParameterParseFailed =>
        lanzouPasswordParameterParseFailed,
      LanzouErrorCode.downloadParameterParseFailed =>
        lanzouDownloadParameterParseFailed,
      LanzouErrorCode.downloadUrlFailed => lanzouDownloadUrlFailed(detail),
      LanzouErrorCode.directLinkMissing => lanzouDirectLinkMissing,
      LanzouErrorCode.folderShareUnavailable => lanzouFolderShareUnavailable,
      LanzouErrorCode.sharePageParseFailed => lanzouSharePageParseFailed,
      LanzouErrorCode.shareFileListFailed => lanzouShareFileListFailed,
      null => error.message,
    };
  }
}

extension TransferFailureL10n on AppLocalizations {
  /// 传输页和通知栏共用的失败文案，保证上传 / 下载状态只显示一层前缀。
  String transferFailure({required bool upload, required String? error}) =>
      formatTransferFailure(this, upload: upload, error: error);
}

String formatTransferFailure(
  AppLocalizations? strings, {
  required bool upload,
  required String? error,
}) {
  var detail = error?.trim() ?? '';
  final genericPrefixes = <String>{
    '失败：',
    '失败:',
    'Failed: ',
    if (strings != null) strings.failedWithError(''),
  };
  var stripped = true;
  while (stripped) {
    stripped = false;
    for (final prefix in genericPrefixes) {
      if (detail.startsWith(prefix)) {
        detail = detail.substring(prefix.length).trimLeft();
        stripped = true;
      }
    }
  }
  final chineseFailurePrefix = RegExp(r'^[^：:\r\n]{1,32}失败[：:]\s*');
  while (chineseFailurePrefix.hasMatch(detail)) {
    detail = detail.replaceFirst(chineseFailurePrefix, '');
  }
  final englishFailurePrefix = RegExp(
    r'^[^:\r\n]{1,48}failed:\s*',
    caseSensitive: false,
  );
  while (englishFailurePrefix.hasMatch(detail)) {
    detail = detail.replaceFirst(englishFailurePrefix, '');
  }
  if (detail.isEmpty) detail = strings?.unknownError ?? '未知错误';
  return upload
      ? (strings?.uploadFailedWithError(detail) ?? '上传失败：$detail')
      : (strings?.downloadFailedWithError(detail) ?? '下载失败：$detail');
}
