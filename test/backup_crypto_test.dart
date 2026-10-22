import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/backup/backup_crypto.dart';

void main() {
  test('整包加密可以往返，密文不含原文明文', () async {
    const plaintext =
        '{"app":"lancloud","accounts":[{"cookie":"ylogin=secret"}]}';
    final envelope = await BackupCrypto.encrypt(
      plaintext,
      passphrase: 'correct horse battery staple',
      iterations: 1000,
    );

    final serialized = jsonEncode(envelope);
    expect(serialized, isNot(contains('ylogin=secret')));
    expect(serialized, isNot(contains('accounts')));
    expect(
      await BackupCrypto.decrypt(
        envelope,
        passphrase: 'correct horse battery staple',
      ),
      plaintext,
    );
  });

  test('错误口令和篡改密文使用同一类失败结果', () async {
    final envelope = await BackupCrypto.encrypt(
      '{"app":"lancloud"}',
      passphrase: 'a strong backup passphrase',
      iterations: 1000,
    );

    await expectLater(
      BackupCrypto.decrypt(envelope, passphrase: 'wrong passphrase'),
      throwsA(isA<BackupCryptoException>()),
    );

    final tampered = Map<String, dynamic>.from(envelope);
    tampered['ciphertext'] = base64Encode([1, 2, 3, 4]);
    await expectLater(
      BackupCrypto.decrypt(tampered, passphrase: 'a strong backup passphrase'),
      throwsA(isA<BackupCryptoException>()),
    );
  });

  test('拒绝过高的 KDF 迭代次数，避免恶意文件造成长时间卡顿', () async {
    final envelope = await BackupCrypto.encrypt(
      '{"app":"lancloud"}',
      passphrase: 'a strong backup passphrase',
      iterations: 1000,
    );
    final malicious = Map<String, dynamic>.from(envelope);
    malicious['kdf'] = {
      'algorithm': BackupCrypto.kdf,
      'iterations': 100000000,
      'salt': (envelope['kdf'] as Map)['salt'],
    };

    await expectLater(
      BackupCrypto.decrypt(malicious, passphrase: 'a strong backup passphrase'),
      throwsA(isA<BackupCryptoException>()),
    );
  });
}
