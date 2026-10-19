import 'dart:convert';

/// GitHub Release 条目（只保留更新检测用得到的字段）。
///
/// 数据来自 `GET /repos/{owner}/{repo}/releases`（见 [UpdateService]）；
/// 缓存进 SharedPreferences 时用同一套键名（[toJson] / [fromJson] 配对）。
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.body,
    required this.htmlUrl,
    required this.prerelease,
    required this.draft,
    required this.publishedAt,
    required this.assets,
  });

  /// tag 名（`v26.1.0-pre.6`）。
  final String tag;

  /// 版本名：tag 去掉前缀 v（`26.1.0-pre.6`）。
  final String version;

  /// 发布说明正文（markdown，按约定含 `## 更新日志` 小节）。
  final String body;

  /// Release 页面地址（tag 页面），弹窗里的「详情」用它。
  final String htmlUrl;

  /// GitHub 的预发布标记：tools/release/publish.ps1 按版本名是否含 `-` 自动打标，
  /// 与本应用的版本号规范（snapshot / pre / beta / rc 都是预发布）口径一致。
  final bool prerelease;

  final bool draft;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String? ?? '';
    return ReleaseInfo(
      tag: tag,
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      body: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      prerelease: json['prerelease'] == true,
      draft: json['draft'] == true,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      assets: [
        for (final asset in (json['assets'] as List? ?? const []))
          if (asset is Map)
            ReleaseAsset.fromJson(Map<String, dynamic>.from(asset)),
      ],
    );
  }

  /// 缓存序列化：键名与 GitHub API 一致，还原时走同一个 [fromJson]。
  Map<String, dynamic> toJson() => {
    'tag_name': tag,
    'body': body,
    'html_url': htmlUrl,
    'prerelease': prerelease,
    'draft': draft,
    if (publishedAt != null) 'published_at': publishedAt!.toIso8601String(),
    'assets': [for (final asset in assets) asset.toJson()],
  };

  /// 从缓存的 JSON 文本还原；内容不完整 / 坏了时返回 null（当作没缓存）。
  static ReleaseInfo? tryFromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final release = ReleaseInfo.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        return release.tag.isEmpty ? null : release;
      }
    } catch (_) {
      // 缓存坏了：当作没有缓存，下次检测会整体覆盖
    }
    return null;
  }

  /// 按设备 ABI 优先级找 Android 安装包。
  ///
  /// 发布脚本的命名是 `LanCloud_android_{版本}_{abi}.apk`（见
  /// tools/release/build_android.ps1），
  /// 这里按「ABI 是文件名子串」匹配，不写死完整文件名——以后版本号规则变了
  /// 也照样能找。逐 ABI 尝试是为了兼容：设备的首选 ABI 没发对应包时，
  /// 退而求其次拿下一个能装的（例如 arm64 设备上的 x86 模拟器场景不会发生，
  /// 但模拟器列表里排在后面的 ABI 可能才是匹配的那个）。
  ReleaseAsset? androidAssetFor(List<String> abis) {
    for (final abi in abis) {
      for (final asset in assets) {
        final name = asset.name.toLowerCase();
        if (name.endsWith('.apk') && name.contains(abi.toLowerCase())) {
          return asset;
        }
      }
    }
    return null;
  }

  /// Windows 便携版（`LanCloud_windows_{版本}_x64_portable.zip`）。
  ReleaseAsset? get windowsAsset {
    for (final asset in assets) {
      final name = asset.name.toLowerCase();
      if (name.endsWith('.zip') && name.contains('windows')) return asset;
    }
    return null;
  }
}

/// Release 里的一个构建产物。
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;

  /// 下载地址（GitHub API 的 `browser_download_url`）。
  final String url;

  final int size;

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) => ReleaseAsset(
    name: json['name'] as String? ?? '',
    url: json['browser_download_url'] as String? ?? '',
    size: json['size'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'browser_download_url': url,
    'size': size,
  };
}

/// 版本号规范（docs/VERSIONING.md）的 Dart 实现，与 tools/release 下的脚本、
/// test/version_test.dart 的分段公式一致：
///
/// versionName = 年份.内容更新序号.热修号[-阶段.序号]，
/// versionCode = YY*10^7 + Drop*10^5 + Hotfix*10^4 + ABI*10^3
///               + Stage*10^2 + Seq
/// （ABI：universal=0 / v7a=4 / arm64=7 / x86_64=8；
///  Stage：snapshot=1 / pre、beta=2 / rc=3 / 正式版=9 且 Seq=99；
///  Seq 只有两位，01–99）。
///
/// 这里算的是 **ABI=0 的基准号**（pubspec / app_info 里存的值）；实际安装包
/// 由 Gradle 按 ABI 加上 digit*1000（arm64 的 pre.10 是 260107210）。
///
/// 版本比较直接比基准号：数字比较天然满足
/// `26.1.0-pre.6 < 26.1.0-rc.1 < 26.1.0 < 26.1.1-pre.1` 这套顺序。
///
/// 注：test/version_test.dart 故意保留一份自己的实现——它校验的是
/// pubspec / app_info 与发布脚本的口径，不该和被测代码共用同一份逻辑。
int? versionCodeOf(String version) {
  int code(int yy, int drop, int hotfix, int stage, int seq) =>
      yy * 10000000 + drop * 100000 + hotfix * 10000 + stage * 100 + seq;

  final release = RegExp(r'^(\d{2})\.(\d+)\.(\d+)$').firstMatch(version);
  if (release != null) {
    return code(
      int.parse(release.group(1)!),
      int.parse(release.group(2)!),
      int.parse(release.group(3)!),
      9,
      99,
    );
  }
  final pre = RegExp(r'^(\d{2})\.(\d+)\.(\d+)-(snapshot|pre|beta|rc)\.(\d+)$')
      .firstMatch(version);
  if (pre == null) return null;
  final seq = int.parse(pre.group(5)!);
  // Seq 只占两位（01–99）：再大的序号会和阶段位撞在一起
  if (seq > 99) return null;
  final stage = switch (pre.group(4)!) {
    'snapshot' => 1,
    'pre' || 'beta' => 2,
    'rc' => 3,
    _ => 0,
  };
  return code(
    int.parse(pre.group(1)!),
    int.parse(pre.group(2)!),
    int.parse(pre.group(3)!),
    stage,
    seq,
  );
}

/// 比较两个版本名（不含 versionCode 的 `26.1.0-pre.6` 这种）。
/// 返回值 > 0 表示 [a] 比 [b] 新。
///
/// 两个版本都符合规范时按 versionCode 比较；有不合规范的（例如以后改了
/// 命名规则）退化成字符串比较，保证不抛异常、也还能选出「不同的那个」。
int compareVersionNames(String a, String b) {
  final codeA = versionCodeOf(a);
  final codeB = versionCodeOf(b);
  if (codeA != null && codeB != null) return codeA.compareTo(codeB);
  return a.compareTo(b);
}

/// 版本名是不是预发布（与 tools/release/publish.ps1 的判定一致）。
bool isPrereleaseVersion(String version) => version.contains('-');

/// 从 Release 列表里挑出当前通道的最新一版；该通道一版都没有时返回 null。
///
/// [channel]：`stable` = 只认正式版（prerelease == false）；`beta` = 预发布
/// 也算。列表顺序（GitHub 按创建时间倒序）不参与判断，按版本号取最大。
ReleaseInfo? pickLatest(List<ReleaseInfo> releases, {required String channel}) {
  ReleaseInfo? best;
  for (final release in releases) {
    if (release.draft) continue;
    if (channel != 'beta' && release.prerelease) continue;
    if (best == null ||
        compareVersionNames(release.version, best.version) > 0) {
      best = release;
    }
  }
  return best;
}
