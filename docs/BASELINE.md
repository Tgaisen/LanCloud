# 回归基线

> 记录日期：2026-10-30。用途：给人和 AI 代理一个「改之前长什么样」的锚点。
> 出现红灯时的第一步，是判断「本次改坏」还是「本来就红」。
>
> **维护约定**：谁让全量用例数或分析基线发生变化，谁负责同步本文件；
> 数字必须标明口径（全量 / 增量），两者不可混写。

## 实测结果

| 命令 | 口径 | 结果 | 耗时 |
| --- | --- | --- | --- |
| `tools\agent.cmd analyze`（无改动→全量） | 全量 | No issues found | 冷缓存约 58 s / 热缓存约 16 s |
| `tools\agent.cmd analyze`（1–2 个文件） | 增量 | No issues found | **0.2–1.7 s**（进程启动约 7 s） |
| `tools\agent.cmd test`（strict 清理前） | 全量 | 616 tests, all passed | 约 92 s |
| `tools\agent.cmd test`（strict 清理后） | 全量 | **626 tests, all passed** | 约 96 s |
| `tools\agent.cmd test`（改过 35 个文件时） | 增量 | 236 tests, all passed | 数十秒 |
| `tools\agent.cmd test`（单文件） | 增量 | passed | 数秒 |
| `tools\agent.cmd analyze`（UpdateService 阶段 1） | 增量 | No issues found | 约 21 s |
| `tools\agent.cmd test`（UpdateService 阶段 1） | 增量 | **334 tests, all passed** | 约 68 s |
| `tools\agent.cmd test`（AppDb provider） | 增量 | **1 test, all passed** | 约 12 s |
| `tools\agent.cmd test`（LanzouClient 注册表） | 增量 | **311 tests, all passed** | 约 61 s |
| `tools\agent.cmd test`（AppLog provider） | 增量 | **339 tests, all passed** | 约 59 s |
| `tools\agent.cmd test`（NotificationService provider） | 增量 | **115 tests, all passed** | 约 25 s |
| `tools\agent.cmd test`（SharedDownloadsGateway） | 增量 | **311 tests, all passed** | 约 57 s |
| `tools\agent.cmd test`（Settings/Account store providers） | 增量 | **72 tests, all passed** | 约 12 s |
| `tools\agent.cmd test`（DownloadPathService） | 增量 | **312 tests, all passed** | 约 59 s |
| `tools\agent.cmd test`（NavigationState 阶段 3） | 增量 | **315 tests, all passed** | 约 61 s |
| `tools\agent.cmd test`（DriveState 阶段 3） | 增量 | **318 tests, all passed** | 约 61 s |
| `tools\agent.cmd test`（AccountState 阶段 3） | 增量 | **321 tests, all passed** | 约 63 s |
| `tools\agent.cmd test`（SettingsState 所有权） | 增量 | **322 tests, all passed** | 约 60 s |
| `tools\agent.cmd test`（UpdateSettingsState 子组） | 增量 | **325 tests, all passed** | 约 59 s |
| `tools\agent.cmd test`（NotificationSettingsState 子组） | 增量 | **328 tests, all passed** | 约 60 s |
| `tools\agent.cmd test`（NavigationAppearanceSettingsState） | 增量 | **331 tests, all passed** | 约 59 s |
| `tools\agent.cmd test`（ThemeSettingsState 子组） | 增量 | **334 tests, all passed** | 约 60 s |
| `tools\agent.cmd test`（TransferConnectionSettingsState） | 增量 | **337 tests, all passed** | 约 61 s |
| `tools\agent.cmd test`（ListHomeSettingsState） | 增量 | **340 tests, all passed** | 约 60 s |
| `tools\agent.cmd test`（LanguageClipboardSettingsState） | 增量 | **343 tests, all passed** | 约 63 s |
| `tools\agent.cmd test`（CachePageSettingsState） | 增量 | **346 tests, all passed** | 约 68 s |
| `tools\agent.cmd test`（DownloadDirectorySettingsState） | 增量 | **349 tests, all passed** | 约 62 s |
| `tools\agent.cmd analyze`（阶段 3 设置拆分后） | 全量 | No issues found | 约 19 s |
| `tools\agent.cmd test`（阶段 3 设置拆分后） | 全量 | **679 tests, all passed** | 约 95 s |
| `tools\agent.cmd test`（UpdateContent Riverpod 消费） | 增量 | **15 tests, all passed** | 约 16 s |
| `tools\agent.cmd test`（ClipboardLinkPromptTile） | 增量 | **49 tests, all passed** | 约 14 s |
| `tools\agent.cmd test`（NotificationSettingsTile + 文案） | 增量 | **308 tests, all passed** | 约 67 s |
| `tools\agent.cmd test`（CachePageSettingsTile） | 增量 | **351 tests, all passed** | 约 61 s |
| `tools\agent.cmd test`（NavigationAppearanceSettingsTile） | 增量 | **352 tests, all passed** | 约 65 s |
| `tools\agent.cmd test`（ThemeSettingsTile） | 增量 | **354 tests, all passed** | 约 72 s |

工具链：Flutter 3.47.7（stable）/ Dart 3.13.5 / DevTools 2.60.0。
静态检查：`analysis_options.yaml` 已开启 `strict-casts` / `strict-inference` / `strict-raw-types`。

## 规模

| 指标 | 数量 |
| --- | ---: |
| `lib` Dart 文件 | 95 |
| `lib` 总行数 | 约 4.7 万 |
| `test` 测试文件 | 123（平铺，`<主题>_test.dart`） |
| `test` 总行数 | 约 2 万 |
| `test` 用例数 | 688（当前总数；本次只验证了受影响增量） |
| `lib/ui` 页面与组件 | 40 个平铺文件 |
| `lib/core` | 32 个平铺文件 + 5 个子系统目录 |
| 文案（`app_zh.arb`） | 1357 行 |

## 这个基线意味着什么

- 626 个测试是**唯一的自动化安全网**：没有 `integration_test`，没有 golden test。
  所以「跑测试」不是形式，是唯一能自动发现回归的手段。
- 全量 analyze 冷缓存约 58 s、热缓存约 16 s；全量 test 约 96 s；增量 analyze 只要 1–2 s。
  `tools\agent.cmd analyze|test` 会自动走增量：改完就跑这两个无参命令，全量由人兜底
  （见 `AGENTS.md`）。注意增量跑的是**受影响的子集**，不能拿它推断全量是否通过。
- `flutter analyze` / `flutter test` 默认会隐式执行 `pub get`；沙箱内联网被拦时会直接失败。
  `tools\agent.cmd` 已内置 `--no-pub`；需要装依赖时用 `agent.cmd pubget`。
- 插件在 Stop 时会自动跑 `dart format` + `dart analyze`，其超时（90 s）与全量 analyze
  冷缓存耗时（58 s）贴得比较近：机器忙的时候可能超时，属已知情况，不算改动失败。
- 当前分析结果为 0 issue 是**硬基线**，不是「再看看」。新增告警要按类型修好，
  不许用 `// ignore:` / `dynamic` 消掉（见 `AGENTS.md` 代码约定）。

## 已知偏差

- 本基线对应版本 `26.1.0-pre.19` 之后的工作区（strict 清理完成时）。
- `pubspec.lock` 里的 SDK 注记已是 `flutter: "3.47.7"` 并已入库，不再每次 `pub get` 产生 diff。
- 2026-10-30 修整了 strict 类型检查暴露的 20 条既有 issue（1 error + 19 warnings），
  并在 `analysis_options.yaml` 正式启用三项 strict 开关；清理后全量 0 issue。
- 2026-10-30 的 UpdateService 阶段 1 试点新增 4 个测试（2 个状态模型、1 个
  并发状态合并、1 个 provider override）；增量 48 个文件 / 334 个测试通过，
  当前总数由 626 增至 630，
  尚未用本轮改动执行全量测试。
- 2026-10-30 的 AppDb provider 阶段 2 叶子新增 1 个测试，当前总数由 630 增至
  631；本次只运行了该 provider 的增量测试。
- 2026-10-30 的 LanzouClient 注册表切片新增 4 个测试，并覆盖备份恢复时保留
  公开客户端；增量 48 个文件 / 311 个测试通过，当前总数由 631 增至 635。
- 2026-10-30 的 AppLog provider 叶子新增 1 个测试，并将 UpdateService 的失败
  日志改为 provider 读取；增量 50 个文件 / 339 个测试通过，当前总数由 635 增至
  636。
- 2026-10-30 的 NotificationService provider 新增 1 个测试，并把
  `TransferManager` 的通知调用改为构造注入；增量 16 个文件 / 115 个测试通过，
  当前总数由 636 增至 637。
- 2026-10-30 的 SharedDownloadsGateway 新增 3 个测试，覆盖注入路径解析、模式
  查询和 provider override；增量 49 个文件 / 311 个测试通过，当前总数由 637
  增至 640。
- 2026-10-30 的 Settings/Account store provider 新增 2 个测试，并把更新服务
  统一到 `settingsStoreProvider`；增量 8 个文件 / 72 个测试通过，当前总数由
  640 增至 642。
- 2026-10-30 的 DownloadPathService 新增 2 个测试，覆盖注入目录解析和 provider
  override；增量 49 个文件 / 312 个测试通过，当前总数由 642 增至 644。
- 2026-10-30 的 NavigationState 阶段 3 首片新增 3 个测试，覆盖状态本身、
  `AppController` 转发和 provider override；增量 50 个文件 / 315 个测试通过，
  当前总数由 644 增至 647。
- 2026-10-30 的 DriveState 首片新增 3 个测试，覆盖目录状态、可见性探针、旧 API
  转发和 provider override；增量 51 个文件 / 318 个测试通过，当前总数由 647
  增至 650。
- 2026-10-30 的 AccountState 首片新增 1 个测试，覆盖旧 API 与 store 同一性；
  增量 52 个文件 / 321 个测试通过，当前总数由 650 增至 651。
- 2026-10-30 的 SettingsState 所有权首片新增 1 个测试，覆盖旧 API 与 store
  同一性；增量 52 个文件 / 322 个测试通过，当前总数由 651 增至 652。
- 2026-10-30 的 UpdateSettingsState 子组新增 3 个测试，覆盖 store 读写、旧 API
  通知语义和 provider override；增量 53 个文件 / 325 个测试通过，当前总数由
  652 增至 655。
- 2026-10-30 的 NotificationSettingsState 子组新增 3 个测试，覆盖 store 读写、
  旧 API 通知语义和 provider override；增量 54 个文件 / 328 个测试通过，当前
  总数由 655 增至 658。
- 2026-10-30 的 NavigationAppearanceSettingsState 新增 3 个测试，覆盖全部字段、
  隐藏栏立即展开副作用和 provider override；增量 55 个文件 / 331 个测试通过，
  当前总数由 658 增至 661。
- 2026-10-30 的 ThemeSettingsState 新增 3 个测试，覆盖全部主题字段、SystemMotion
  同步和 provider override；增量 56 个文件 / 334 个测试通过，当前总数由 661
  增至 664。
- 2026-10-30 的 TransferConnectionSettingsState 新增 3 个测试，覆盖全部连接字段、
  LanzouClient 静态同步和 provider override；增量 57 个文件 / 337 个测试通过，
  当前总数由 664 增至 667。
- 2026-10-30 的 ListHomeSettingsState 新增 3 个测试，覆盖全部列表/首页字段、
  旧 API 通知和 provider override；增量 58 个文件 / 340 个测试通过，当前总数由
  667 增至 670。
- 2026-10-30 的 LanguageClipboardSettingsState 新增 3 个测试，覆盖语言/剪贴板
  字段、旧 API 通知和 provider override；增量 59 个文件 / 343 个测试通过，当前
  总数由 670 增至 673。
- 2026-10-30 的 CachePageSettingsState 新增 3 个测试，覆盖页面/缓存字段、
  DriveCache 清理副作用和 provider override；增量 60 个文件 / 346 个测试通过，
  当前总数由 673 增至 676。
- 2026-10-30 的 DownloadDirectorySettingsState 新增 3 个测试，覆盖普通/SAF
  目录字段、旧 API 互斥写入和 provider override；增量 61 个文件 / 349 个测试
  通过，当前总数由 676 增至 679。
- 2026-10-30 的阶段 4 首片将 `UpdateContent` 改为纯 Riverpod 消费，并新增 1 个
  不使用 `AppController` 的作用域测试；增量 2 个文件 / 15 个测试通过，当前总数
  由 679 增至 680。
- 2026-10-30 的阶段 4 设置页首个叶子新增 `ClipboardLinkPromptTile` 和 1 个独立
  Widget 测试；增量 9 个文件 / 49 个测试通过，当前总数由 680 增至 681。
- 2026-10-30 的 NotificationSettingsTile 新增 1 个独立 Widget 测试，并把完成
  通知文案改为“传输完成通知 / 下载或上传完成、失败时通知”；增量 52 个文件 /
  308 个测试通过，当前总数由 681 增至 682。
- 2026-10-30 的 CachePageSettingsTile 新增 1 个独立 Widget 测试，并把关闭目录
  缓存时清空 `DriveCache` 的副作用收拢到 `CachePageSettingsState`；增量 62 个
  文件 / 351 个测试通过，当前总数由 682 增至 683。
- 2026-10-30 的 NavigationAppearanceSettingsTile 新增 1 个独立 Widget 测试和
  1 个控制器通知转发测试，覆盖悬浮导航、滑动切页、转场动画；增量 62 个文件 /
  352 个测试通过，当前总数由 683 增至 685。
- 2026-10-30 的 ThemeSettingsTile 新增 2 个独立 Widget 测试和 1 个控制器通知
  转发测试，覆盖主题模式与纯黑深色；增量 62 个文件 / 354 个测试通过，当前总数
  由 685 增至 688。
- 若临时再改 `analysis_options.yaml` 加规则，issue 数会变；先把预期数量记在这里再跑，
  避免和「本次改坏」混淆。
