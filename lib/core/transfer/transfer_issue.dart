/// 应用自己生成、需要在显示时按当前界面语言翻译的传输问题。
enum TransferIssueCode {
  skippedOversize,
  skippedUnsupported,
  uploadSourceMissing,
  uploadPermissionExpired,
  uploadSourceUnavailable,
  uploadNeedLogin,
}

/// 存在现有 `transfer.error` 字段里的稳定错误码，不随界面语言变化。
class TransferIssue {
  const TransferIssue(this.code, [this.detail = '']);

  static const _prefix = '@lancloud-transfer-issue:';

  final TransferIssueCode code;
  final String detail;

  String encode() => '$_prefix${code.name}:${Uri.encodeComponent(detail)}';

  static TransferIssue? decode(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith(_prefix)) {
      final payload = value.substring(_prefix.length);
      final separator = payload.indexOf(':');
      if (separator < 0) return null;
      final code = _codeFromName(payload.substring(0, separator));
      if (code == null) return null;
      try {
        return TransferIssue(
          code,
          Uri.decodeComponent(payload.substring(separator + 1)),
        );
      } catch (_) {
        return null;
      }
    }
    return _legacyIssue(value);
  }

  static TransferIssueCode? _codeFromName(String name) => switch (name) {
    'skippedOversize' => TransferIssueCode.skippedOversize,
    'skippedUnsupported' => TransferIssueCode.skippedUnsupported,
    'uploadSourceMissing' => TransferIssueCode.uploadSourceMissing,
    'uploadPermissionExpired' => TransferIssueCode.uploadPermissionExpired,
    'uploadSourceUnavailable' => TransferIssueCode.uploadSourceUnavailable,
    'uploadNeedLogin' => TransferIssueCode.uploadNeedLogin,
    _ => null,
  };

  static TransferIssue? _legacyIssue(String value) {
    const unsupported = {
      '此类文件不允许上传',
      '文件类型不在允许上传列表中',
      'This type of file cannot be uploaded',
      'File type is not in the allowed upload list',
    };
    if (unsupported.contains(value)) {
      return const TransferIssue(TransferIssueCode.skippedUnsupported);
    }
    const permissionExpired = {
      '文件访问授权已过期，请重新选择文件上传',
      'File access permission has expired. Please choose the file again.',
    };
    if (permissionExpired.contains(value)) {
      return const TransferIssue(TransferIssueCode.uploadPermissionExpired);
    }
    const sourceMissing = {
      '源文件已不存在，请重新选择文件上传',
      'The source file is gone; please pick the file again',
    };
    if (sourceMissing.contains(value)) {
      return const TransferIssue(TransferIssueCode.uploadSourceMissing);
    }
    const sourceUnavailable = {
      '应用重启后无法继续该上传，请重新上传',
      "This upload can't continue after an app restart; please upload again",
    };
    if (sourceUnavailable.contains(value)) {
      return const TransferIssue(TransferIssueCode.uploadSourceUnavailable);
    }
    const needLogin = {'请先登录后再上传', 'Please sign in before uploading'};
    if (needLogin.contains(value)) {
      return const TransferIssue(TransferIssueCode.uploadNeedLogin);
    }

    final chineseCurrent = RegExp(r'^文件超过 (.+) 限制$').firstMatch(value);
    final chineseLegacy = RegExp(r'^超过单文件大小限制（(.+)）$').firstMatch(value);
    final englishCurrent = RegExp(r'^File exceeds the (.+) limit$')
        .firstMatch(value);
    final englishLegacy = RegExp(r'^Exceeds the per-file limit \((.+)\)$')
        .firstMatch(value);
    final limit =
        chineseCurrent?.group(1) ??
        chineseLegacy?.group(1) ??
        englishCurrent?.group(1) ??
        englishLegacy?.group(1);
    if (limit != null && limit.isNotEmpty) {
      return TransferIssue(TransferIssueCode.skippedOversize, limit);
    }
    return null;
  }
}
