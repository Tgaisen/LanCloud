import '../data/settings_store.dart';

/// `TransferManager` 需要的低频设置读取能力。
abstract interface class TransferSettingsPort {
  int get maxUploads;
  int get maxDownloads;
  bool get notifyProgress;
  bool get notifyDone;
}

/// 从既有设置存储实时读取传输相关设置。
class StoreTransferSettingsPort implements TransferSettingsPort {
  const StoreTransferSettingsPort(this.store);

  final SettingsStore store;

  @override
  int get maxUploads => store.maxUploads;

  @override
  int get maxDownloads => store.maxDownloads;

  @override
  bool get notifyProgress => store.notifyProgress;

  @override
  bool get notifyDone => store.notifyDone;
}
