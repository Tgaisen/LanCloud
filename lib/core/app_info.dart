/// 应用信息：发版时与 pubspec.yaml 的 version 一起更新（版本号规范见 README）。
const String appVersion = '26.1.0-pre.18';
const int appBuild = 260100218;

/// 开源协议与项目地址。
const String projectUrl = 'https://github.com/Tgaisen/LanCloud';

/// 构建信息：发布脚本（tools/release/build_*.ps1）用 --dart-define 注入；
/// [gitCommit] 是完整 hash（40 位），本地直接运行 / 普通构建时为空，
/// 关于页显示为「—」且不显示「详情」按钮。
const String buildTime = String.fromEnvironment('BUILD_TIME');
const String gitCommit = String.fromEnvironment('GIT_COMMIT');

/// 构建时间的展示文本。
///
/// 发布脚本注入的是带 `Z` 的 UTC 时间（GitHub Actions runner 为 UTC），
/// 显示时转成本机时区；早期构建注入的 `yyyy-MM-dd HH:mm:ss`（无时区）按
/// 本地时间理解，原样显示；解析失败时原样返回。
String buildTimeForDisplay() => formatBuildTimeForDisplay(buildTime);

/// [buildTimeForDisplay] 的纯函数版本（便于单测）。
String formatBuildTimeForDisplay(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return text;
  final local = parsed.isUtc ? parsed.toLocal() : parsed;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

/// 用户协议 / 隐私政策版本：条款有实质修改时 +1，会重新请求用户同意。
const int termsVersion = 1;
