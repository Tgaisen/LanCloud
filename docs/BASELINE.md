# 回归基线

> 当前快照日期：2026-11-13。
>
> 本文件只记录当前仓库状态；逐次迁移和增量测试历史见
> [BASELINE_HISTORY.md](BASELINE_HISTORY.md)。

## 当前自动化基线

| 命令 | 口径 | 结果 | 耗时 |
| --- | --- | --- | --- |
| `tools\agent.cmd analyze` | 增量（本次改动，3 个 Dart 文件） | No issues found | 约 10 s |
| `tools\agent.cmd test` | 全量（用例总数） | **899 tests, all passed** | 约 2 min 24 s |
| `tools\agent.cmd format` | 全量 | 335 files，0 changed | 约 4 s |
| `tools\agent.cmd build-apk` | debug | `app-debug.apk` | 首次构建约 5 min 46 s |

当前分析结果为 0 issue 是硬基线。出现红灯时，先判断是否为本次改动引入；
不要把增量结果当成全量结论。本轮升级未在修复后单独重跑全量 `analyze`，
CI 会按干净检出执行全量分析。

当前全量用例总数为 899，与升级前一致；Flutter 3.50.0 下已重跑全量并通过。
测试入口在受影响文件超过 60 个时自动回退全量，避免 Windows 命令行长度上限导致
测试尚未启动就报错。

## 规模

| 指标 | 当前值 |
| --- | ---: |
| `lib` Dart 文件 | 156 |
| `lib` 总行数 | 58,654 |
| `test` 测试文件 | 177（全部为 `*_test.dart`，平铺） |
| `test` 总行数 | 32,972 |
| `test` 用例数 | 899 |
| `lib/ui` 平铺文件 | 60 |
| `lib/core` | 55 个平铺文件 + 5 个子系统目录 |
| 文案（`app_zh.arb`） | 1,624 行 |

## 工具链与依赖

- Flutter `3.50.0` stable / Dart `3.14.0` / DevTools `2.61.0`。
- `flutter_riverpod: ^3.5.0`。
- `provider` 依赖和 `ChangeNotifierProvider` 已移除。
- `AppController` 已删除；应用级对象由 `AppEnvironment` 组装，
  `AppStartup` 编排启动与备份恢复后的状态同步。
- 应用级 provider 不使用 `autoDispose`；高频滚动、动画和传输进度继续使用
  `ValueNotifier` / `ValueListenableBuilder`。

## 测试安全网

- 当前全量总数为 899 个测试；项目仍没有
  `integration_test` 和 golden test。
- `tools\agent.cmd analyze|test` 默认走增量；全量结果必须按上表单独记录。
- 增量推断出超过 60 个测试文件时，`agent.cmd test` 自动回退全量。
- `tools\agent.cmd` 已内置 `--no-pub`；需要安装依赖时使用 `agent.cmd pubget`。

## 构建与安装快照

- Android：Flutter 3.50.0 下 debug APK 构建成功。此前 3.47.9 下已在
  `NOH AN00`（Android 12 / API 31 / arm64）覆盖安装成功，保留应用数据。
- Android arm64 release / profile / debug 三档在 3.47.9 下均构建成功；
  3.50.0 的 release / profile 构建仍待 CI 或人工补跑。
- Windows：x64 Release 构建成功，已启动 `lancloud.exe` 验证进程可正常运行。
- Windows x64 release / profile / debug 三档均构建成功；文件描述、产品名与
  构建类型图标已通过 EXE 产物核对。
- 以上只证明构建与安装链路正常；登录、分享解析、后台传输、备份恢复、返回手势、
  Windows 拖放等人工功能验收仍需单独记录。

## 已知偏差与风险

- Android 构建仍对 `desktop_drop`、`m3e_core` 报 Kotlin Gradle Plugin（KGP）
  未来兼容警告；当前不影响构建，后续插件升级时需要处理。
- Flutter 3.50.0 的 `gen-l10n` 仍生成旧 `flutter_localizations` delegates
  （上游 issue #196475）。应用运行路径使用 `material_ui` 新 delegates，
  生成头只对上游模板产生的 `deprecated_member_use` 做窄范围豁免。
- Flutter 3.50.0 会把 app 的 `profile.applicationIdSuffix` 复制给插件库并导致
  Android 配置失败（上游 issue #196412）。当前通过 Variant API 设置 profile
  包名，保留独立安装能力；上游修复后应移除该兼容逻辑。
- Windows 构建出现 `flutter_inappwebview_windows` 的 CMake `CMP0175` 开发警告；
  当前不影响构建与启动，继续跟随插件升级观察。
- Windows OverlayPortal/UIA 上游间歇风险继续观察，不误判为业务回归。
- 日志清理已增加 Windows 临时目录有界重试，分享密码恢复测试已改用 5 秒截止
  时间轮询；当前全量与连续复跑均通过，后续继续观察较慢 CI 环境。
- 开发环境 Flutter `3.50.0`，`pubspec.lock` 已记录 Dart `3.14.0` 与相同
  Flutter SDK 注记。

## 维护约定

- 让全量用例数、分析结果或主要规模发生变化时，更新本文件。
- 只记录当前有效基线；逐次迁移细节追加到 `BASELINE_HISTORY.md`。
- 数字必须标明全量 / 增量口径，两者不可混写。
