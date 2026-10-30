import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import '../app_log.dart';
import '../data/settings_store.dart';
import '../platform_support.dart';
import 'release_info.dart';
import 'update_state.dart';

export 'update_state.dart';

/// 可注入的「现在」时间源，供有效期与失败冷却判断使用。
typedef UpdateClock = DateTime Function();

/// 可注入的 Release 拉取函数，测试无需访问真实网络。
typedef UpdateFetcher = Future<List<ReleaseInfo>> Function();

/// 更新服务读取的现有设置对象；生产环境由 `main()` 覆盖成已加载的实例。
final updateSettingsProvider = Provider<SettingsStore>((ref) {
  throw StateError('updateSettingsProvider 必须由应用入口覆盖');
});

/// 更新服务的时间源。
final updateClockProvider = Provider<UpdateClock>((ref) => DateTime.now);

/// GitHub Release 数据源。
final updateFetcherProvider = Provider<UpdateFetcher>(
  (ref) => _fetchGitHubReleases,
);

/// 当前平台是否有可安装的更新产物。
final updateSupportedProvider = Provider<bool>(
  (ref) => PlatformSupport.isAndroid || PlatformSupport.isWindows,
);

/// 应用级更新状态；固定常驻，不使用 `autoDispose`。
final updateServiceProvider =
    NotifierProvider<UpdateService, UpdateState>(UpdateService.new);

/// 由更新状态与当前时间派生的卡片状态。
final updateStatusProvider = Provider<UpdateStatus>((ref) {
  if (!ref.watch(updateSupportedProvider)) return UpdateStatus.idle;
  final state = ref.watch(updateServiceProvider);
  return state.statusAt(ref.read(updateClockProvider)());
});

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
class UpdateService extends Notifier<UpdateState> {
  /// 更新信息有效期：检测成功那一刻起 12 小时。
  static const Duration validFor = UpdatePolicy.validFor;

  /// 失败冷却：自动检测失败后 1 小时内不再自动重试（手动检测不受限制）。
  static const Duration retryCooldown = UpdatePolicy.retryCooldown;

  /// GitHub Release 列表接口。用列表而不是 `/releases/latest`：
  /// latest 只返回正式版，仓库全是预发布时直接 404；列表还能按通道自己挑。
  static const String releasesApi =
      'https://api.github.com/repos/Tgaisen/LanCloud/releases';

  static const int _perPage = 10;

  static const _keyLastCheck = 'update_last_check_at';
  static const _keyLastAttempt = 'update_last_attempt_at';
  static const _keyCache = 'update_cache';

  bool _initialized = false;

  SettingsStore get _settings => ref.read(updateSettingsProvider);

  DateTime get _now => ref.read(updateClockProvider)();

  @override
  UpdateState build() => const UpdateState();

  /// 当前平台有没有可用的更新包：Android（按 ABI 分装）与 Windows（便携
  /// 版 zip）有；iOS 没有产物，也不算更新通道（页面按 [supported] 降级）。
  bool get supported => ref.read(updateSupportedProvider);

  bool get checking => state.checking;

  /// 最近一次检测成功的时间（跨重启保留）。
  DateTime? get lastCheckAt => state.lastCheckAt;

  /// 最近一次检测失败的简短原因（`TIMEOUT` / `NETWORK` / `HTTP 403` 这类），
  /// 卡片副标题里的「连接错误码」。
  String? get failureCode => state.failureCode;

  /// 最近一次检测成功时远端的最新版本（可能比当前安装版本旧甚至为空）。
  ReleaseInfo? get latestRelease => state.cachedRelease;

  String? get remoteVersion => state.cachedRelease?.version;

  String? get autoUpdateNotice => state.autoUpdateNotice;

  void clearAutoUpdateNotice() {
    if (state.autoUpdateNotice == null) return;
    state = state.copyWith(clearAutoUpdateNotice: true);
  }

  /// 检测结果是否还在有效期内。
  bool get inValidity => state.inValidityAt(_now);

  /// 有效期内检测到的远端版本比当前安装版本新。
  bool get hasUpdate => state.hasUpdate;

  /// 卡片当前要显示的状态（五种情况按需求定义）。
  UpdateStatus get status =>
      supported ? state.statusAt(_now) : UpdateStatus.idle;

  /// 从磁盘恢复缓存；启动时只执行一次，不发起网络请求。
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      var next = state;
      final checkAt = prefs.getInt(_keyLastCheck);
      if (checkAt != null) {
        next = next.copyWith(
          lastCheckAt: DateTime.fromMillisecondsSinceEpoch(checkAt),
        );
      }
      final attemptAt = prefs.getInt(_keyLastAttempt);
      if (attemptAt != null) {
        next = next.copyWith(
          lastAttemptAt: DateTime.fromMillisecondsSinceEpoch(attemptAt),
        );
      }
      final raw = prefs.getString(_keyCache);
      final cached = raw == null ? null : ReleaseInfo.tryFromJson(raw);
      if (cached != null) {
        next = next.copyWith(cachedRelease: cached);
      }
      state = next;
    } catch (_) {
      // 存储不可用（测试 / 异常）：当作没有缓存
    }
  }

  /// 启动时的自动检测：开着自动检查、不在有效期内、且过了失败冷却才请求。
  Future<void> maybeAutoCheck() async {
    if (!supported) return;
    final settings = _settings;
    if (!settings.updateAutoCheck) return;
    if (inValidity) return;
    final lastAttempt = state.lastAttemptAt;
    if (lastAttempt != null && _now.difference(lastAttempt) < retryCooldown) {
      return;
    }
    final ok = await check();
    // 自动检测到新版本：留一个一次性标记，界面在任意页面提醒一次
    if (ok && status == UpdateStatus.available) {
      state = state.copyWith(autoUpdateNotice: remoteVersion);
    }
  }

  /// 执行一次检测（手动 / 自动共用）。返回是否成功——手动检测失败时页面
  /// 会补一条提示，自动检测失败静默（状态留在卡片上，细节进日志）。
  Future<bool> check() async {
    final settings = _settings;
    if (!supported || state.checking) return false;
    state = state.copyWith(checking: true);
    var ok = false;
    ReleaseInfo? latest;
    String? failure;
    try {
      final releases = await ref.read(updateFetcherProvider)();
      latest = pickLatest(releases, channel: settings.updateChannel);
      ok = true;
    } catch (error) {
      failure = failureCodeOf(error);
      // 失败细节进运行日志（用户可在设置里导出），界面只显示状态
      AppLog.instance.error('update', error, null);
    }
    final checkedAt = ok ? _now : null;
    final attemptedAt = _now;
    await _persist(
      lastCheckAt: checkedAt,
      lastAttemptAt: attemptedAt,
      cachedRelease: latest,
      writeCache: ok,
    );
    var next = state.copyWith(
      checking: false,
      lastAttemptAt: attemptedAt,
    );
    if (ok) {
      next = next.copyWith(
        cachedRelease: latest,
        clearCachedRelease: latest == null,
        lastCheckAt: checkedAt,
        clearFailureCode: true,
      );
    } else {
      next = next.copyWith(failureCode: failure);
    }
    state = next;
    return ok;
  }

  /// 切换更新通道：清掉上一通道的检测结果（缓存与「上次检测于」），
  /// 开着自动检查时立即重新检测一次。
  Future<void> onChannelChanged() async {
    state = state.copyWith(
      clearCachedRelease: true,
      clearLastCheckAt: true,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyCache);
      await prefs.remove(_keyLastCheck);
    } catch (_) {
      // 存储不可用：内存里已经清掉，行为一致
    }
    if (_settings.updateAutoCheck) {
      unawaited(check());
    }
  }

  /// 「更新」按钮要打开的下载地址：优先当前平台 / 架构对应的安装包；
  /// 认不出 ABI、资产缺失或平台不支持时退回 Release 页面（用户自己挑）。
  Future<String> downloadUrl() async {
    final release = state.cachedRelease;
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

  Future<void> _persist({
    required DateTime? lastCheckAt,
    required DateTime lastAttemptAt,
    required ReleaseInfo? cachedRelease,
    required bool writeCache,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (lastCheckAt != null) {
        await prefs.setInt(_keyLastCheck, lastCheckAt.millisecondsSinceEpoch);
      }
      await prefs.setInt(_keyLastAttempt, lastAttemptAt.millisecondsSinceEpoch);
      if (writeCache) {
        if (cachedRelease == null) {
          await prefs.remove(_keyCache);
        } else {
          await prefs.setString(_keyCache, jsonEncode(cachedRelease.toJson()));
        }
      }
    } catch (_) {
      // 写不进去（存储异常）不影响本次会话的显示
    }
  }
}

Future<List<ReleaseInfo>> _fetchGitHubReleases() async {
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
    UpdateService.releasesApi,
    queryParameters: {'per_page': '${UpdateService._perPage}'},
  );
  final data = response.data ?? const [];
  return [
    for (final item in data)
      if (item is Map) ReleaseInfo.fromJson(Map<String, dynamic>.from(item)),
  ];
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
