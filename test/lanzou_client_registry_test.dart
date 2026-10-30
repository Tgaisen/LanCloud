import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';

void main() {
  test('注册表按 uid 缓存账号客户端，并保持公开客户端独立', () {
    final registry = LanzouClientRegistry();
    addTearDown(registry.clear);

    final first = registry.clientFor('1');
    final same = registry.clientFor('1');
    final other = registry.clientFor('2');
    final public = registry.publicClient;

    expect(identical(first, same), isTrue);
    expect(identical(first, other), isFalse);
    expect(identical(first, public), isFalse);
    expect(public.uid, '0');

    registry.remove('1');
    final recreated = registry.clientFor('1');
    expect(identical(recreated, first), isFalse);
  });

  test('登录验证后的客户端可以放回缓存，clear 同时清理公开客户端', () {
    final registry = LanzouClientRegistry();
    final originalPublic = registry.publicClient;
    final verified = registry.create('9');

    registry.store('9', verified);
    expect(identical(registry.clientFor('9'), verified), isTrue);

    registry.clear();
    expect(identical(registry.publicClient, originalPublic), isFalse);
  });

  test('备份恢复清账号客户端时保留公开客户端', () {
    final registry = LanzouClientRegistry();
    final accountClient = registry.clientFor('7');
    final publicClient = registry.publicClient;

    registry.clearAccounts();

    expect(identical(registry.clientFor('7'), accountClient), isFalse);
    expect(identical(registry.publicClient, publicClient), isTrue);
  });

  test('注册表 provider 可以被覆盖成应用共享实例', () {
    final registry = LanzouClientRegistry(
      factory: (uid) => LanzouClient(uid: uid),
    );
    final container = ProviderContainer(
      overrides: [
        lanzouClientRegistryProvider.overrideWithValue(registry),
      ],
    );
    addTearDown(container.dispose);

    expect(
      identical(container.read(lanzouClientRegistryProvider), registry),
      isTrue,
    );
  });
}
