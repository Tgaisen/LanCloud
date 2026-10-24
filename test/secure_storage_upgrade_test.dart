import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v9 安全存储残留只检查并提示一次', () async {
    SharedPreferences.setMockInitialValues({});
    var checks = 0;

    Future<SecureStorageUpgradeStatus> check() async {
      checks += 1;
      return const SecureStorageUpgradeStatus(
        state: SecureStorageUpgradeState.legacyDataUnreadable,
        reason: SecureStorageUpgradeReason.missingAlgorithmMarkers,
        entryCount: 3,
        willDiscardOnNextAccess: true,
      );
    }

    final first = await checkSecureStorageUpgradeOnce(check: check);
    final second = await checkSecureStorageUpgradeOnce(check: check);

    expect(first?.hasDataLoss, isTrue);
    expect(second, isNull);
    expect(checks, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(secureStorageUpgradeCheckKey), isTrue);
  });

  test('检查失败时不写入完成标记，下次启动可以重试', () async {
    SharedPreferences.setMockInitialValues({});

    await expectLater(
      checkSecureStorageUpgradeOnce(
        check: () => Future.error(StateError('platform unavailable')),
      ),
      throwsStateError,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(secureStorageUpgradeCheckKey), isNull);
  });
}
