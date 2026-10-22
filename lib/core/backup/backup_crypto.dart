import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// 备份密码错误，或密文 / 认证标签已经损坏。
///
/// 两种情况刻意使用同一条提示，避免给离线暴力破解提供区分信息。
class BackupCryptoException implements Exception {
  const BackupCryptoException([this.message = '备份密码错误或备份已损坏']);

  final String message;

  @override
  String toString() => message;
}

/// 备份文件的整体口令加密。
///
/// 使用 AES-256-GCM 加密完整 JSON，而不是逐字段加密：账号、收藏地址、
/// WebDAV 配置、设置等都不会以明文留在文件里，同时 GCM 还能发现篡改。
///
/// PBKDF2 是 `cryptography` 在 Android / iOS / Windows 上稳定支持的 KDF。
/// 格式里会记录迭代次数和随机 salt，后续可以在保持旧文件可读的前提下升级。
abstract final class BackupCrypto {
  static const algorithm = 'aes-256-gcm';
  static const kdf = 'pbkdf2-hmac-sha256';
  static const encryptionVersion = 1;
  static const defaultIterations = 600000;

  // 防止恶意备份通过极端 KDF 参数让应用长时间卡死。
  static const _minIterations = 1000;
  static const _maxIterations = 2000000;
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _macLength = 16;

  /// 判断已解析的外层对象是否使用新的口令加密封装。
  static bool isEncryptedEnvelope(Map<String, dynamic> envelope) =>
      envelope['encryption'] is Map;

  /// 将完整明文 JSON 加密成可写入备份文件的外层对象。
  static Future<Map<String, Object?>> encrypt(
    String plaintext, {
    required String passphrase,
    int iterations = defaultIterations,
  }) async {
    final normalized = _validatePassphrase(passphrase);
    if (iterations < _minIterations || iterations > _maxIterations) {
      throw ArgumentError.value(iterations, 'iterations');
    }

    final random = Random.secure();
    final salt = List<int>.generate(_saltLength, (_) => random.nextInt(256));
    final nonce = List<int>.generate(_nonceLength, (_) => random.nextInt(256));
    final key = await _deriveKey(
      normalized,
      salt: salt,
      iterations: iterations,
    );
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );

    return {
      'version': encryptionVersion,
      'algorithm': algorithm,
      'kdf': {
        'algorithm': kdf,
        'iterations': iterations,
        'salt': base64Encode(salt),
      },
      'nonce': base64Encode(nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    };
  }

  /// 验证口令、认证密文并返回完整明文 JSON。
  static Future<String> decrypt(
    Map<String, dynamic> envelope, {
    required String passphrase,
  }) async {
    final normalized = _validatePassphrase(passphrase);
    try {
      if ((envelope['version'] as num?)?.toInt() != encryptionVersion ||
          envelope['algorithm'] != algorithm) {
        throw const BackupCryptoException();
      }
      final rawKdf = envelope['kdf'];
      if (rawKdf is! Map) throw const BackupCryptoException();
      if (rawKdf['algorithm'] != kdf) throw const BackupCryptoException();

      final iterations = (rawKdf['iterations'] as num?)?.toInt();
      if (iterations == null ||
          iterations < _minIterations ||
          iterations > _maxIterations) {
        throw const BackupCryptoException();
      }
      final salt = _decodeBytes(rawKdf['salt'], expectedLength: _saltLength);
      final nonce = _decodeBytes(
        envelope['nonce'],
        expectedLength: _nonceLength,
      );
      final mac = _decodeBytes(envelope['mac'], expectedLength: _macLength);
      final cipherText = _decodeBytes(envelope['ciphertext']);
      if (cipherText.isEmpty) throw const BackupCryptoException();

      final key = await _deriveKey(
        normalized,
        salt: salt,
        iterations: iterations,
      );
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      return utf8.decode(clear);
    } on BackupCryptoException {
      rethrow;
    } catch (_) {
      // 口令错误、认证标签不匹配、UTF-8 损坏都归为同一种用户可见结果。
      throw const BackupCryptoException();
    }
  }

  static Future<SecretKey> _deriveKey(
    String passphrase, {
    required List<int> salt,
    required int iterations,
  }) => Pbkdf2.hmacSha256(
    iterations: iterations,
    bits: 256,
  ).deriveKeyFromPassword(password: passphrase, nonce: salt);

  static String _validatePassphrase(String passphrase) {
    if (passphrase.trim().isEmpty) {
      throw const BackupCryptoException('请输入备份密码');
    }
    return passphrase;
  }

  static List<int> _decodeBytes(Object? value, {int? expectedLength}) {
    if (value is! String || value.isEmpty) {
      throw const BackupCryptoException();
    }
    late final List<int> bytes;
    try {
      bytes = base64Decode(value);
    } catch (_) {
      throw const BackupCryptoException();
    }
    if (expectedLength != null && bytes.length != expectedLength) {
      throw const BackupCryptoException();
    }
    return bytes;
  }
}
