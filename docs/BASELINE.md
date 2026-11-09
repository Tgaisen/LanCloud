# 回归基线

> 当前快照日期：2026-11-09。
>
> 本文件只记录当前仓库状态；逐次迁移和增量测试历史见
> [BASELINE_HISTORY.md](BASELINE_HISTORY.md)。

## 当前自动化基线

| 命令 | 口径 | 结果 | 耗时 |
| --- | --- | --- | --- |
| `tools\agent.cmd analyze` | 全量 | No issues found | 约 41 s |
| `tools\agent.cmd analyze` | 增量（本次改动，2 项） | No issues found | 约 10 s |
| `tools\agent.cmd test` | 全量（当前） | **871 tests, all passed** | 约 189 s |
| `tools\agent.cmd test` | 增量（本次改动，68 个测试文件） | **427 tests, all passed** | 约 85 s |

当前分析结果为 0 issue 是硬基线。出现红灯时，先判断是否为本次改动引入；
不要把增量结果当成全量结论。

当前全量用例总数为 871（本轮新增 6 个）。全量 871 个用例已在并发场景下全部
通过；`app_log_test.dart` 与 `share_password_recovery_test.dart` 连续 3 轮
针对性复跑也全部通过。

## 规模

| 指标 | 当前值 |
| --- | ---: |
| `lib` Dart 文件 | 156 |
| `lib` 总行数 | 57,920 |
| `test` 测试文件 | 175（全部为 `*_test.dart`，平铺） |
| `test` 总行数 | 32,105 |
| `test` 用例数 | 871 |
| `lib/ui` 平铺文件 | 60 |
| `lib/core` | 55 个平铺文件 + 5 个子系统目录 |
| 文案（`app_zh.arb`） | 1,622 行 |

## 工具链与依赖

- Flutter `3.47.9` stable / Dart `3.13.7` / DevTools `2.60.0`。
- `flutter_riverpod: ^3.4.3`。
- `provider` 依赖和 `ChangeNotifierProvider` 已移除。
- `AppController` 已删除；应用级对象由 `AppEnvironment` 组装，
  `AppStartup` 编排启动与备份恢复后的状态同步。
- 应用级 provider 不使用 `autoDispose`；高频滚动、动画和传输进度继续使用
  `ValueNotifier` / `ValueListenableBuilder`。

## 测试安全网

- 当前全量总数为 871 个测试；项目仍没有
  `integration_test` 和 golden test。
- `tools\agent.cmd analyze|test` 默认走增量；全量结果必须按上表单独记录。
- `tools\agent.cmd` 已内置 `--no-pub`；需要安装依赖时使用 `agent.cmd pubget`。

## 构建与安装快照

- Android：debug APK 构建成功，并在 `NOH AN00`（Android 12 / API 31 /
  arm64）覆盖安装成功，保留应用数据。
- Android arm64 release / profile / debug 三档均构建成功；包名和本地化标签
  已通过 APK 产物核对。
- Windows：x64 Release 构建成功，已启动 `lancloud.exe` 验证进程可正常运行。
- Windows x64 release / profile / debug 三档均构建成功；文件描述、产品名与
  构建类型图标已通过 EXE 产物核对。
- 以上只证明构建与安装链路正常；登录、分享解析、后台传输、备份恢复、返回手势、
  Windows 拖放等人工功能验收仍需单独记录。

## 已知偏差与风险

- Android 构建出现 Kotlin Gradle Plugin（KGP）未来兼容警告；当前不影响构建，
  后续升级 Flutter / 插件时需要处理。
- Windows 构建出现 `flutter_inappwebview_windows` 的 CMake `CMP0175` 开发警告；
  当前不影响构建与启动，继续跟随插件升级观察。
- Windows OverlayPortal/UIA 上游间歇风险继续观察，不误判为业务回归。
- 日志清理已增加 Windows 临时目录有界重试，分享密码恢复测试已改用 5 秒截止
  时间轮询；当前全量与连续复跑均通过，后续继续观察较慢 CI 环境。
- 开发环境 Flutter `3.47.9`，`pubspec.lock` 已记录相同 SDK 注记。

## 维护约定

- 让全量用例数、分析结果或主要规模发生变化时，更新本文件。
- 只记录当前有效基线；逐次迁移细节追加到 `BASELINE_HISTORY.md`。
- 数字必须标明全量 / 增量口径，两者不可混写。
