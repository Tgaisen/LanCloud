import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications_provider.dart';
import '../shared_downloads_gateway.dart';
import 'transfer_dependencies.dart';
import 'transfer_manager.dart';

/// 应用级传输依赖；生产入口必须注入显式依赖集合。
final transferDependenciesProvider = Provider<TransferDependencies>((ref) {
  throw StateError('transferDependenciesProvider 必须由应用入口覆盖');
});

/// 应用级传输管理器：非 autoDispose，由 ProviderContainer 负责释放。
final transferManagerProvider = Provider<TransferManager>((ref) {
  final manager = TransferManager.withDependencies(
    ref.watch(transferDependenciesProvider),
    notifications: ref.watch(notificationServiceProvider),
    sharedDownloads: ref.watch(sharedDownloadsGatewayProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});
