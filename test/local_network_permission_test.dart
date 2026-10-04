import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_permissions.dart';
import 'package:lancloud/core/backup/webdav_client.dart';

/// 只记录调用次数并返回固定结果的权限桩。
class FakePermissions extends AppPermissions {
  FakePermissions({required this.granted});

  final bool granted;
  int calls = 0;

  @override
  Future<bool> requestLocalNetwork() async {
    calls += 1;
    return granted;
  }
}

void main() {
  group('局域网地址判定', () {
    test('私有网段与链路本地地址算局域网', () {
      expect(isLocalNetworkHost('192.168.1.10'), isTrue);
      expect(isLocalNetworkHost('10.0.0.5'), isTrue);
      expect(isLocalNetworkHost('172.16.0.1'), isTrue);
      expect(isLocalNetworkHost('172.31.255.254'), isTrue);
      expect(isLocalNetworkHost('169.254.10.10'), isTrue);
      expect(isLocalNetworkHost('nas.local'), isTrue);
      expect(isLocalNetworkHost('fe80::1'), isTrue);
      expect(isLocalNetworkHost('fd00::1'), isTrue);
    });

    test('公网地址与普通域名不算局域网', () {
      expect(isLocalNetworkHost('8.8.8.8'), isFalse);
      expect(isLocalNetworkHost('172.32.0.1'), isFalse);
      expect(isLocalNetworkHost('11.0.0.1'), isFalse);
      expect(isLocalNetworkHost('dav.example.com'), isFalse);
      expect(isLocalNetworkHost('localhost'), isTrue); // 本机名按局域网处理
      expect(isLocalNetworkHost(''), isFalse);
    });
  });

  group('WebDAV 局域网权限', () {
    tearDown(() => AppPermissions.instance = AppPermissions());

    test('局域网地址未授权时抛出可读提示', () async {
      final fake = FakePermissions(granted: false);
      AppPermissions.instance = fake;

      final client = WebdavClient(url: 'http://192.168.1.5/dav');
      await expectLater(
        client.ensureLocalNetworkPermission(),
        throwsA(isA<BackupException>()),
      );
      expect(fake.calls, 1);
    });

    test('局域网地址已授权时放行', () async {
      final fake = FakePermissions(granted: true);
      AppPermissions.instance = fake;

      final client = WebdavClient(url: 'http://192.168.1.5/dav');
      await client.ensureLocalNetworkPermission();
      expect(fake.calls, 1);
    });

    test('公网地址不请求权限', () async {
      final fake = FakePermissions(granted: false);
      AppPermissions.instance = fake;

      final client = WebdavClient(url: 'https://dav.example.com/');
      await client.ensureLocalNetworkPermission();
      expect(fake.calls, 0);
    });
  });
}
