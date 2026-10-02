import 'package:local_auth/local_auth.dart';

/// 查看敏感信息前的身份验证结果。
enum CookieAuthResult {
  /// 验证通过。
  ok,

  /// 用户主动取消或系统打断（切到后台等）：静默返回即可。
  canceled,

  /// 设备既没设锁屏密码也没有生物识别，无法验证。
  unavailable,

  /// 验证失败（重试次数过多、系统错误等）。
  failed,
}

/// 显示 Cookie 前的身份验证。生产实现走系统生物识别 / 锁屏密码，
/// 测试中可替换 [instance] 注入桩实现。
class CookieAuth {
  CookieAuth();

  static CookieAuth instance = CookieAuth();

  Future<CookieAuthResult> verify(String reason) async {
    final auth = LocalAuthentication();
    bool supported;
    try {
      supported = await auth.isDeviceSupported();
    } catch (_) {
      return CookieAuthResult.unavailable;
    }
    if (!supported) return CookieAuthResult.unavailable;
    try {
      final ok = await auth.authenticate(localizedReason: reason);
      return ok ? CookieAuthResult.ok : CookieAuthResult.failed;
    } on LocalAuthException catch (e) {
      return cookieAuthResultFor(e.code);
    } catch (_) {
      return CookieAuthResult.failed;
    }
  }
}

/// 把插件的错误码映射为界面需要的三种非成功结果。
CookieAuthResult cookieAuthResultFor(LocalAuthExceptionCode code) {
  const canceled = {
    LocalAuthExceptionCode.userCanceled,
    LocalAuthExceptionCode.systemCanceled,
    LocalAuthExceptionCode.timeout,
    LocalAuthExceptionCode.userRequestedFallback,
    LocalAuthExceptionCode.authInProgress,
  };
  const unavailable = {
    LocalAuthExceptionCode.noCredentialsSet,
    LocalAuthExceptionCode.noBiometricsEnrolled,
    LocalAuthExceptionCode.noBiometricHardware,
    LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable,
    LocalAuthExceptionCode.uiUnavailable,
  };
  if (canceled.contains(code)) return CookieAuthResult.canceled;
  if (unavailable.contains(code)) return CookieAuthResult.unavailable;
  return CookieAuthResult.failed;
}
