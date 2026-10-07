/// 应用信息：发版时与 pubspec.yaml 的 version 一起更新（版本号规范见 README）。
const String appVersion = '26.1.0-pre.2';
const int appBuild = 260102002;

/// 开源协议与项目地址。
const String projectUrl = 'https://github.com/Tgaisen/LanCloud';

/// 构建信息：打包脚本（tools/release.ps1）用 --dart-define 注入；
/// [gitCommit] 是完整 hash（40 位），本地直接运行 / 普通构建时为空，
/// 关于页显示为「—」且不显示「详情」按钮。
const String buildTime = String.fromEnvironment('BUILD_TIME');
const String gitCommit = String.fromEnvironment('GIT_COMMIT');

/// 用户协议 / 隐私政策版本：条款有实质修改时 +1，会重新请求用户同意。
const int termsVersion = 1;
