import 'package:flutter/widgets.dart';

import '../core/api/lanzou_client.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// 快捷访问当前语言的本地化文案：`context.l10n.xxx`。
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
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
