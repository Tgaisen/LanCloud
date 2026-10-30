import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lanzou_client.dart';

/// 可注入的客户端创建函数，测试无需访问网络或账号存储。
typedef LanzouClientFactory = LanzouClient Function(String uid);

LanzouClient _defaultClientFactory(String uid) => LanzouClient(uid: uid);

/// 按账号缓存 [LanzouClient]，并保留独立的公开分享客户端。
///
/// 注册表只负责生命周期和 Cookie 注入，不读取设置或账号状态；调用方决定何时
/// 创建、替换和移除客户端。
class LanzouClientRegistry {
  LanzouClientRegistry({LanzouClientFactory? factory})
    : _factory = factory ?? _defaultClientFactory;

  final LanzouClientFactory _factory;
  final Map<String, LanzouClient> _clients = {};
  LanzouClient? _publicClient;

  /// 创建但不缓存客户端，供登录验证完成前临时使用。
  LanzouClient create(String uid, {String? cookie}) {
    final client = _factory(uid);
    if (cookie != null) client.setCookieHeader(cookie);
    return client;
  }

  /// 获取并缓存账号客户端；[cookie] 只在该 uid 首次创建时注入。
  LanzouClient clientFor(String uid, {String? cookie}) =>
      _clients.putIfAbsent(uid, () => create(uid, cookie: cookie));

  /// 公开分享解析使用独立客户端，不携带任何账号 Cookie。
  LanzouClient get publicClient => _publicClient ??= create('0');

  /// 登录验证成功后把临时客户端放入缓存，避免重复创建。
  void store(String uid, LanzouClient client) {
    _clients[uid] = client;
  }

  void remove(String uid) {
    _clients.remove(uid);
  }

  /// 备份恢复只重建账号客户端；公开分享客户端与账号状态无关，继续保留。
  void clearAccounts() {
    _clients.clear();
  }

  void clear() {
    clearAccounts();
    _publicClient = null;
  }
}

/// 应用级客户端注册表；与 `AppController` 共用同一实例，不使用 `autoDispose`。
final lanzouClientRegistryProvider = Provider<LanzouClientRegistry>(
  (ref) => LanzouClientRegistry(),
);
