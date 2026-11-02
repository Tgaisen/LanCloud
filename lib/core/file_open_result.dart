/// 系统打开文件失败的原因。
enum FileOpenFailure {
  fileNotFound,
  permissionDenied,
  noAssociatedApp,
  systemError,
}

/// 类型化的系统打开结果，避免把权限、文件缺失等错误统一显示成“无关联应用”。
class FileOpenResult {
  const FileOpenResult.success() : this._(null);

  const FileOpenResult.failed(FileOpenFailure failure) : this._(failure);

  const FileOpenResult._(this.failure);

  final FileOpenFailure? failure;

  bool get isSuccess => failure == null;
}
