import 'package:lancloud/core/app_composition_root.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/download_path_service.dart';
import 'package:lancloud/core/shared_downloads_gateway.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';

TransferManager buildTransferManagerForEnvironment(AppEnvironment environment) {
  const sharedDownloads = PlatformSharedDownloadsGateway();
  final downloadPaths = PlatformDownloadPathService(
    sharedDownloads: sharedDownloads,
  );
  final composition = AppCompositionRoot(
    environment: environment,
    reloadFromStorage: () async {},
    sharedDownloads: sharedDownloads,
    downloadPaths: downloadPaths,
  );
  return TransferManager.withDependencies(
    composition.transferDependencies,
    sharedDownloads: sharedDownloads,
  );
}
