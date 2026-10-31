import 'package:flutter/foundation.dart';

import '../app_info.dart';
import 'release_info.dart';

/// 更新页卡片要显示的几种情况。
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

/// 更新检测的时间策略。
abstract final class UpdatePolicy {
  /// 更新信息有效期：检测成功那一刻起 12 小时。
  static const Duration validFor = Duration(hours: 12);

  /// 失败冷却：自动检测失败后 1 小时内不再自动重试（手动检测不受限制）。
  static const Duration retryCooldown = Duration(hours: 1);
}

/// 更新服务的完整状态。
///
/// 状态只保存在这里，UI 通过 [statusAt] 派生卡片状态；这样检测结果、失败
/// 原因、持久化时间和一次性提醒不会散落在多个布尔字段里。
@immutable
class UpdateState {
  const UpdateState({
    this.checking = false,
    this.cachedRelease,
    this.lastCheckAt,
    this.lastAttemptAt,
    this.failureCode,
    this.autoUpdateNotice,
  });

  /// 当前是否正在请求更新信息。
  final bool checking;

  /// 最近一次检测成功选出的远端版本。
  final ReleaseInfo? cachedRelease;

  /// 最近一次检测成功的时间（跨重启保留）。
  final DateTime? lastCheckAt;

  /// 最近一次检测尝试的时间（无论成功失败，跨重启保留）。
  final DateTime? lastAttemptAt;

  /// 最近一次检测失败的简短原因；成功后会清空。
  final String? failureCode;

  /// 自动检测发现新版本后，等待 UI 消费的一次性提醒版本。
  final String? autoUpdateNotice;

  /// 检测结果是否还在有效期内。
  bool inValidityAt(DateTime now) {
    final checkedAt = lastCheckAt;
    return checkedAt != null &&
        now.difference(checkedAt) < UpdatePolicy.validFor;
  }

  /// 当前缓存里的远端版本是否比安装版本新。
  bool get hasUpdate {
    final release = cachedRelease;
    return release != null &&
        compareVersionNames(release.version, appVersion) > 0;
  }

  /// 按当前时间派生卡片状态。
  UpdateStatus statusAt(DateTime now) {
    if (checking) return UpdateStatus.checking;
    if (inValidityAt(now)) {
      return hasUpdate ? UpdateStatus.available : UpdateStatus.upToDate;
    }
    if (failureCode != null) return UpdateStatus.failed;
    return UpdateStatus.idle;
  }

  /// 返回替换部分字段后的新状态。
  ///
  /// 可空字段不能用 `null` 同时表达「不修改」和「清空」，所以清除操作使用
  /// 对应的 `clear...` 参数。
  UpdateState copyWith({
    bool? checking,
    ReleaseInfo? cachedRelease,
    bool clearCachedRelease = false,
    DateTime? lastCheckAt,
    bool clearLastCheckAt = false,
    DateTime? lastAttemptAt,
    String? failureCode,
    bool clearFailureCode = false,
    String? autoUpdateNotice,
    bool clearAutoUpdateNotice = false,
  }) {
    assert(!clearCachedRelease || cachedRelease == null);
    assert(!clearLastCheckAt || lastCheckAt == null);
    assert(!clearFailureCode || failureCode == null);
    assert(!clearAutoUpdateNotice || autoUpdateNotice == null);
    return UpdateState(
      checking: checking ?? this.checking,
      cachedRelease: clearCachedRelease
          ? null
          : cachedRelease ?? this.cachedRelease,
      lastCheckAt: clearLastCheckAt ? null : lastCheckAt ?? this.lastCheckAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      failureCode: clearFailureCode ? null : failureCode ?? this.failureCode,
      autoUpdateNotice: clearAutoUpdateNotice
          ? null
          : autoUpdateNotice ?? this.autoUpdateNotice,
    );
  }
}
