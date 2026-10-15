import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import '../app_log.dart';
import '../data/settings_store.dart';
import '../platform_support.dart';
import 'release_info.dart';

/// 更新检测状态（更新页卡片上显示的几种情况）。
enum UpdateStatus {
  /// 未检测更新：不在更新信息有效期内，本次启动也还没检测过。
  idle,

  /// 正在检测更新。
  checking,

  /// 已是最新版本：有效期内，远端没有比当前安装版本更新的版本。
  upToDate,

  /// 检测到新版本：有效期内，远端有更新的版本。
  available,

  /// 检测更新失败：不在有效期内，且本次启动检测过但失败。
  failed,
}

/// 更新检测服务：拉取 GitHub Release、缓存结果、维护卡片要显示的状态。
///
/// 规则（与需求一致）：
/// - **更新信息有效期 12 小时**：检测成功那一刻起算，超过就当作没检测过；
/// - **启动时自动检测**：只有「开着自动检查、不在有效期内」才请求；
/// - **失败不占有效期**：失败只影响本次会话的显示（[UpdateStatus.failed]），
///   但会记下尝试时间做冷却，避免 GitHub 不可达时每次启动都打请求；
/// - 缓存与冷却记录进 SharedPreferences，重启后仍生效。
///
/// 请求 GitHub REST API（未认证限 60 次/小时/IP，国内还有可达性问题）：
/// 靠 12 小时有效期 + 失败冷却把请求压到最低；失败对用户静默（自动检测）
/// 或只体现在卡片状态上，细节写进运行日志。
class UpdateService extends ChangeNotifier {
  /// 更新信息有效期：检测成功那一刻起 12 小时。
  static const Duration validFor = Duration(hours: 12);

  /// 失败冷却：自动检测失败后 1 小时内不再自动重试（手动检测不受限制）。
  static const Duration retryCooldown = Duration(hours: 1);

  /// GitHub Release 列表接口。用列表而不是 `/releases/latest`：
  /// latest 只返回正式版，仓库全是预发布时直接 404；列表还能按通道自己挑。
  static const String releasesApi =
      'https://api.github.com/repos/Tgaisen/LanCloud/releases';

  static const int _perPage = 10;

  static const _keyLastCheck = 'update_last_check_at';
  static const _keyLastAttempt = 'update_last_attempt_at';
  static const _keyCache = 'update_cache';

  SettingsStore? _settings;
  bool _bound = false;
  bool _checking = false;
  bool _failedThisSession = false;
  String? _failureCode;
  ReleaseInfo? _cached;
  DateTime? _lastCheckAt;
  DateTime? _lastAttemptAt;

  /// 测试注入用：替换真实网络请求。
  @visibleForTesting
  static Future<List<ReleaseInfo>> Function()? debugFetchReleases;

  /// 测试注入用：替换「现在」的时间源（有效期 / 冷却判断）。
  @visibleForTesting
  static DateTime Function() debugNow = DateTime.now;

  DateTime get _now => debugNow();

  /// 当前平台有没有可用的更新包：Android（按 ABI 分装）与 Windows（便携
  /// 版 zip）有；iOS 没有产物，也不算更新通道（页面按 [supported] 降级）。
  bool get supported => PlatformSupport.isAndroid || PlatformSupport.isWindows;

  bool get checking => _checking;

  /// 最近一次检测成功的时间（跨重启保留）。
  DateTime? get lastCheckAt => _lastCheckAt;

  /// 最近一次检测失败的简短原因（`TIMEOUT` / `NETWORK` / `HTTP 403` 这类），
  /// 卡片副标题里的「连接错误码」。
  String? get failureCode => _failureCode;

  /// 最近一次检测成功时远端的最新版本（可能比当前安装版本旧甚至为空）。
  ReleaseInfo? get latestRelease => _cached;

  String? get remoteVersion => _cached?.version;

  /// 检测结果是否还在有效期内。
  bool get inValidity {
    final last = _lastCheckAt;
    return last != null && _now.difference(last) < validFor;
  }

  /// 有效期内检测到的远端版本比当前安装版本新。
  bool get hasUpdate {
    final release = _cached;
    return release != null &&
        compareVersionNames(release.version, appVersion) > 0;
  }

  /// 卡片当前要显示的状态（五种情况按需求定义）。
  UpdateStatus get status {
    if (!supported) return UpdateStatus.idle;
    if (_checking) return UpdateStatus.checking;
    if (inValidity) {
      return hasUpdate ? UpdateStatus.available : UpdateStatus.upToDate;
    }
    if (_failedThisSession) return UpdateStatus.failed;
    return UpdateStatus.idle;
  }

  /// 绑定设置（读取更新通道 / 自动检查开关），并从磁盘恢复缓存。
  /// 首次调用读缓存；之后只更新设置引用（备份恢复后 settings 会换一份）。
  Future<void> bind(SettingsStore settings) async {
    _settings = settings;
    if (_bound) return;
    _bound = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final checkAt = prefs.getInt(_keyLastCheck);
      if (checkAt != null) {
        _lastCheckAt = DateTime.fromMillisecondsSinceEpoch(checkAt);
      }
      final attemptAt = prefs.getInt(_keyLastAttempt);
      if (attemptAt != null) {
        _lastAttemptAt = DateTime.fromMillisecondsSinceEpoch(attemptAt);
      }
      final raw = prefs.getString(_keyCache);
      if (raw != null) _cached = ReleaseInfo.tryFromJson(raw);
    } catch (_) {
      // 存储不可用（测试 / 异常）：当作没有缓存
    }
  }

  /// 启动时的自动检测：开着自动检查、不在有效期内、且过了失败冷却才请求。
  Future<void> maybeAutoCheck() async {
    if (!supported) return;
    final settings = _settings;
    if (settings == null || !settings.updateAutoCheck) return;
    if (inValidity) return;
    final lastAttempt = _lastAttemptAt;
    if (lastAttempt != null && _now.difference(lastAttempt) < retryCooldown) {
      return;
    }
    await check();
  }

  /// 执行一次检测（手动 / 自动共用）。返回是否成功——手动检测失败时页面
  /// 会补一条提示，自动检测失败静默（状态留在卡片上，细节进日志）。
  Future<bool> check() async {
    final settings = _settings;
    if (!supported || settings == null || _checking) return false;
    _checking = true;
    _failedThisSession = false;
    notifyListeners();
    var ok = false;
    try {
      final releases = await _fetch();
      _cached = pickLatest(releases, channel: settings.updateChannel);
      _lastCheckAt = _now;
      _failureCode = null;
      ok = true;
    } catch (error) {
      _failedThisSession = true;
      _failureCode = failureCodeOf(error);
      // 失败细节进运行日志（用户可在设置里导出），界面只显示状态
      AppLog.instance.error('update', error, null);
    } finally {
      _lastAttemptAt = _now;
      await _persist();
      _checking = false;
      notifyListeners();
    }
    return ok;
  }

  /// 切换更新通道：清掉上一通道的检测结果（缓存与「上次检测于」），
  /// 开着自动检查时立即重新检测一次。
  Future<void> onChannelChanged() async {
    _cached = null;
    _lastCheckAt = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyCache);
      await prefs.remove(_keyLastCheck);
    } catch (_) {
      // 存储不可用：内存里已经清掉，行为一致
    }
    notifyListeners();
    if (_settings?.updateAutoCheck ?? false) {
      unawaited(check());
    }
  }

  /// 「更新」按钮要打开的下载地址：优先当前平台 / 架构对应的安装包；
  /// 认不出 ABI、资产缺失或平台不支持时退回 Release 页面（用户自己挑）。
  Future<String> downloadUrl() async {
    final release = _cached;
    if (release == null) return '';
    if (PlatformSupport.isAndroid) {
      final abis = await PlatformSupport.loadSupportedAbis() ?? const [];
      final asset = release.androidAssetFor(abis);
      return asset?.url ?? release.htmlUrl;
    }
    if (PlatformSupport.isWindows) {
      return release.windowsAsset?.url ?? release.htmlUrl;
    }
    return release.htmlUrl;
  }

  Future<List<ReleaseInfo>> _fetch() async {
    final override = debugFetchReleases;
    if (override != null) return override();
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          // GitHub 要求请求带 User-Agent；顺带让对方能识别流量来源
          'User-Agent': 'LanCloud/$appVersion (+$projectUrl)',
          'Accept': 'application/vnd.github+json',
        },
      ),
    );
    final response = await dio.get<List<dynamic>>(
      releasesApi,
      queryParameters: {'per_page': '$_perPage'},
    );
    final data = response.data ?? const [];
    return [
      for (final item in data)
        if (item is Map) ReleaseInfo.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_lastCheckAt != null) {
        await prefs.setInt(_keyLastCheck, _lastCheckAt!.millisecondsSinceEpoch);
      }
      if (_lastAttemptAt != null) {
        await prefs.setInt(
          _keyLastAttempt,
          _lastAttemptAt!.millisecondsSinceEpoch,
        );
      }
      final release = _cached;
      if (release == null) {
        await prefs.remove(_keyCache);
      } else {
        await prefs.setString(_keyCache, jsonEncode(release.toJson()));
      }
    } catch (_) {
      // 写不进去（存储异常）不影响本次会话的显示
    }
  }
}

/// 失败原因 → 卡片副标题里那个简短的「连接错误码」。
String failureCodeOf(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return 'TIMEOUT';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        return code == null ? 'HTTP' : 'HTTP $code';
      case DioExceptionType.badCertificate:
        return 'TLS';
      case DioExceptionType.cancel:
        return 'CANCELED';
      case DioExceptionType.connectionError:
        return 'NETWORK';
      case DioExceptionType.unknown:
        // Dart 的 SocketException（DNS / 连接失败）会包在 unknown 里
        return error.error is SocketException ? 'NETWORK' : 'UNKNOWN';
    }
  }
  if (error is FormatException || error is TypeError) return 'PARSE';
  return 'UNKNOWN';
}
