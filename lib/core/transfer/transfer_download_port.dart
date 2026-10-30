import '../download_target.dart';

/// `TransferManager` 需要的下载目标与路径解析能力。
abstract interface class TransferDownloadPort {
  Future<DownloadTargetMode> targetMode();
  String? get safTreeUri;
  Future<String> safTempFilePath(String taskId, String name);
  Future<String> uniqueSavePath(String name);
}

/// 用回调包装迁移期现有下载路径实现。
class CallbackTransferDownloadPort implements TransferDownloadPort {
  factory CallbackTransferDownloadPort({
    required Future<DownloadTargetMode> Function() targetMode,
    required String? Function() safTreeUri,
    required Future<String> Function(String taskId, String name)
    safTempFilePath,
    required Future<String> Function(String name) uniqueSavePath,
  }) => CallbackTransferDownloadPort._(
    targetMode,
    safTreeUri,
    safTempFilePath,
    uniqueSavePath,
  );

  CallbackTransferDownloadPort._(
    this._targetMode,
    this._safTreeUri,
    this._safTempFilePath,
    this._uniqueSavePath,
  );

  final Future<DownloadTargetMode> Function() _targetMode;
  final String? Function() _safTreeUri;
  final Future<String> Function(String taskId, String name) _safTempFilePath;
  final Future<String> Function(String name) _uniqueSavePath;

  @override
  Future<DownloadTargetMode> targetMode() => _targetMode();

  @override
  String? get safTreeUri => _safTreeUri();

  @override
  Future<String> safTempFilePath(String taskId, String name) =>
      _safTempFilePath(taskId, name);

  @override
  Future<String> uniqueSavePath(String name) => _uniqueSavePath(name);
}
