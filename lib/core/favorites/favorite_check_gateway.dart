import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/lanzou_client.dart';
import '../api/models.dart';
import '../api/lanzou_client_registry.dart';

/// 收藏检测使用的公开分享探测端口。
///
/// 收藏不依赖当前登录账号，生产实现固定走注册表里的 publicClient；测试可注入
/// 不访问网络的实现。
abstract interface class FavoriteCheckGateway {
  Future<FolderShareDetail> resolveFolder({
    required String url,
    required String pwd,
  });

  /// 返回 true 表示能明确确认分享仍可访问；提取码问题通过异常向上抛出。
  Future<bool> validateFile({required String url, required String pwd});
}

class LanzouFavoriteCheckGateway implements FavoriteCheckGateway {
  const LanzouFavoriteCheckGateway(this.clients);

  final LanzouClientRegistry clients;

  LanzouClient get _client => clients.publicClient;

  @override
  Future<FolderShareDetail> resolveFolder({
    required String url,
    required String pwd,
  }) => _client.resolveFolderShare(url, pwd: pwd);

  @override
  Future<bool> validateFile({required String url, required String pwd}) async {
    final details = await _client.fetchFileShareDetails(url, pwd: pwd);
    if (details.requiresPassword) {
      // fetchFileShareDetails 只确认分享页存在，不校验提取码；再走一次完整
      // 解析，才能区分密码已变更与真正失效。
      await _client.resolveFileShare(url, pwd: pwd);
    }
    return true;
  }
}

final favoriteCheckGatewayProvider = Provider<FavoriteCheckGateway>(
  (ref) => LanzouFavoriteCheckGateway(ref.watch(lanzouClientRegistryProvider)),
);
