import '../core/file_open_result.dart';
import '../l10n/l10n.dart';

String fileOpenFailureMessage(AppLocalizations l10n, FileOpenFailure failure) =>
    switch (failure) {
      FileOpenFailure.fileNotFound => l10n.openFileMissing,
      FileOpenFailure.permissionDenied => l10n.openFilePermissionDenied,
      FileOpenFailure.noAssociatedApp => l10n.openFileFailed,
      FileOpenFailure.systemError => l10n.openFileSystemError,
    };
