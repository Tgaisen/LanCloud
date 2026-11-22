# 回归基线

> 当前快照日期：2026-11-22。
>
> 本文件只记录当前仓库状态；逐次迁移和增量测试历史见
> [BASELINE_HISTORY.md](BASELINE_HISTORY.md)。

## 当前自动化基线

| 命令 | 口径 | 结果 | 耗时 |
| --- | --- | --- | --- |
| `tools\agent.cmd analyze` | 全量 | No issues found | 约 15–22 s |
| `tools\agent.cmd analyze` | 增量（系统动作 adapter，2 个 Dart 文件） | No issues found | 约 1 s |
| `tools\agent.cmd test` | 全量（Windows，含 Golden） | **1068 tests, all passed** | 约 2 min 27 s |
| `tools\agent.cmd test` | 增量（Golden，2 个测试文件） | **4 tests, all passed** | 约 13 s |
| `tools\agent.cmd test` | 增量（测试基座与拆分文件，41 个测试文件） | **339 tests, all passed** | 约 1 min 8 s |
| `tools\agent.cmd coverage` | 全量 | **1068 tests, all passed**；生产代码行覆盖 79.7% | 约 4 min 11 s |
| `tools\agent.cmd integration-test` | Windows RootShell / 首次启动 / 备份 round-trip | **3 tests, all passed** | 约 1 min 15 s |
| `tools\agent.cmd integration-test emulator-5554` | Android 17 / API 37，逐文件验证 | `app_smoke` 2/2、备份 round-trip 1/1 通过 | 构建约 2–4 min |
| `tools\agent.cmd format` | 覆盖率入口与备份 integration 加入后 | 404 files，0 changed | 约 3 s |
| `tools\agent.cmd build-android` | debug，拆分 ABI | `app-<abi>-debug.apk` | 首次构建约 5 min 46 s |
| `tools\agent.cmd build-android --release --universal` | release，含插件注册兼容步骤 | `app-release.apk`（74.8 MB） | 约 4 min 17 s |

当前分析结果为 0 issue 是硬基线。出现红灯时，先判断是否为本次改动引入；
不要把增量结果当成全量结论。Flutter 3.50.0 下全量分析已重跑并通过。

普通测试用例总数为 1068，包含 4 项 Windows golden 测试；最近一次 Windows
全量为 1068 项全部通过。另有 3 项 Windows integration smoke，独立通过且
不计入 1068。此前相比 `ff3ea87` 的 1061 项增加了目录与拖拽、Golden、
首次启动 integration 等覆盖；
组件测试；Batch 8B–10 均通过各自受影响测试。
平台能力矩阵覆盖
Android、Windows、iOS、macOS、Linux 与未知 TargetPlatform 的 fail-closed
行为，以及动态色来源、更新产物、只读 const 能力和 Riverpod 测试覆盖。设置页、
网盘添加菜单、普通文件选择、系统另存为、二维码来源与分享收件箱已改为按具体
能力执行，默认下载目录、传输 SAF 路由、启动系统栏与前台任务也按能力矩阵选择，
系统分享已收敛为 Android 原生、桌面降级与 unsupported gateway，权限与系统设置
通道已收敛为可注入 transport 并按能力 fail closed，更新检查与下载产物已由
`UpdateArtifact` 和 adapter 统一解析，本地通知初始化与权限入口由
`supportsLocalNotifications` 门控，常驻进度通知另由
`supportsPersistentProgressNotifications` 控制，Windows 进度设置和上报均隐藏；
应用缓存清理由私有临时目录与 SAF 能力选择，设备信息分支统一走
`PlatformSupport`。
WebView 登录 UA 由 `usesMobileWebUserAgent` 决定，动态色插件探测由
`DynamicColorSource` 选择；全局滚动条和自适应菜单改由运行时鼠标信号控制。
收藏与传输分栏标题改由实际宽度决定，文件分享入口按原生分享、桌面定位和
unsupported 三态显示；外部网页与文件打开动作已收敛到可注入 gateway/adapter。
全量覆盖
收藏分栏高度稳定、批量消除更新标志、分享目录分页取消后保留当前页面与已加载
内容，同时保留 WebDAV 自动备份互斥和补检覆盖。
测试入口在受影响文件超过 60 个时自动回退全量，避免 Windows 命令行长度上限导致
测试尚未启动就报错。

## 规模

| 指标 | 当前值 |
| --- | ---: |
| `lib` Dart 文件 | 168 |
| `lib` 总行数 | 65,563 |
| `test` 测试文件 | 224 个 `*_test.dart` + 7 个 `test/support/*.dart` |
| `test` 总行数 | 41,087（测试 39,438 + 辅助 1,649） |
| `test` 用例数 | 1068 |
| `integration_test` 文件 / 用例 | 2 / 3（RootShell、首次启动、备份 round-trip） |
| `lib/ui` 平铺文件 | 62 |
| `lib/core` | 61 个平铺文件 + 6 个子系统目录 |
| 文案（`app_zh.arb`） | 1,812 行 |

## 工具链与依赖

- Flutter `3.50.0` stable / Dart `3.14.0` / DevTools `2.61.0`。
- `flutter_riverpod: ^3.5.0`。
- `integration_test` 作为 Flutter SDK 开发依赖接入；未引入第三方测试框架。
- `provider` 依赖和 `ChangeNotifierProvider` 已移除。
- `AppController` 已删除；应用级对象由 `AppEnvironment` 组装，
  `AppStartup` 编排启动与备份恢复后的状态同步。
- 应用级 provider 不使用 `autoDispose`；高频滚动、动画和传输进度继续使用
  `ValueNotifier` / `ValueListenableBuilder`。

## 测试安全网

- 当前用例总数为 1068；最近一次 Windows 全量 1068 项通过；
  平台能力矩阵与 UI、
  扫码、分享、文件、下载、启动、系统分享、系统设置、更新交付、本地通知门控
  通知设置可见性、缓存清理、设备信息分支、WebView 登录 UA、动态色来源路由
  鼠标滚动条、自适应菜单、分栏宽度及文件分享入口语义已由全量测试覆盖；
  项目已有 4 个 Windows golden test 和 3 个 Windows integration smoke。
- Golden 覆盖 `SectionHeader` 与 `EmptyHint` 的明暗主题，固定 DPR 1 和中文
  locale；当前基准图在 Windows 生成，其他平台跳过，避免字体与光栅差异造成
  跨平台误报。
- 更新 golden 基准图使用 `tools\agent.cmd golden-update`；普通
  `tools\agent.cmd test` 仍负责校验 golden。
- `tools\agent.cmd integration-test` 无参数时在 `windows` 设备运行
  `integration_test`；其他平台或 Android 设备可在命令后显式指定设备 ID。
- `tools\agent.cmd coverage` 默认跑全量并写入 `coverage/lcov.info`；该目录
  已被 `.gitignore` 排除，不会进入提交。
- Integration smoke 使用 `AppEnvironment` 和现有测试宿主，不运行生产
  `main()`；数据库目录强制指向用例创建的临时目录并在结束时清理。
- 最近一次覆盖率审计排除生成的 `app_localizations*.dart` 后，生产代码行覆盖
  为 79.7%（`core` 79.8%、`ui` 80.8%）。该结果只作诊断，不作为硬门禁。
- Android 17 / API 37 模拟器上，`app_smoke_test.dart` 2 项和
  `backup_roundtrip_test.dart` 1 项分别通过；目录级一次运行曾因模拟器掉线
  和 Gradle daemon 退出未完成，不视为应用断言失败。
- CI 的 Windows 测试任务在 PR 和 `main` push 中同时校验 golden 并运行
  integration smoke；Ubuntu 单元测试任务不执行 Windows golden 像素比较。
- `tools\agent.cmd analyze|test` 默认走增量；全量结果必须按上表单独记录。
- 增量推断出超过 60 个测试文件时，`agent.cmd test` 自动回退全量。
- 共享测试基座位于 `test/support/`；修改其中的 helper 时，选择器会带上
  所有导入该 helper 的测试文件，避免只运行非测试 helper 本身。
- `transfers_selection_test.dart` 与 `property_sheet_quick_actions_test.dart`
  已按功能拆分；用例总数不变，但单文件范围更大程度地对齐页面行为。
- `tools\agent.cmd` 已内置 `--no-pub`；需要安装依赖时使用 `agent.cmd pub-get`。
  Android release 的唯一例外是构建前执行
  `flutter build apk --config-only --release`，用于刷新 dev dependency 的 release
  插件注册；实际 APK 构建仍使用 `--no-pub`。

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

- 首个 golden 使用 Flutter 测试默认 Ahem 字体，图中的文字会显示为方块；
  当前覆盖布局、尺寸、间距与颜色，不覆盖真实字形。若后续需要文字级视觉回归，
  应单独评估统一测试字体及其许可证。
- Integration smoke 当前覆盖 `RootShell` 主标签切换、首次启动条款门到
  RootShell / 登录页，以及收藏夹的本地备份导出与恢复 round-trip；尚未覆盖
  生产 `main()` 启动、真实账号网络请求、通知、前台服务、WebDAV 或文件选择
  等原生链路。
- 覆盖率低值主要集中在 `web_page` / `web_login_page`、`main`、
  `device_info` 和通知等 WebView / 原生通道适配层；这些路径仍依赖设备级
  Android 测试或人工验收，不能只看行覆盖数字判断风险。
- Android 构建仍对 `desktop_drop`、`m3e_core` 报 Kotlin Gradle Plugin（KGP）
  未来兼容警告；当前不影响构建，后续插件升级时需要处理。
- Flutter 3.50.0 的 `gen-l10n` 仍生成旧 `flutter_localizations` delegates
  （上游 issue #196475）。应用运行路径使用 `material_ui` 新 delegates，
  生成头只对上游模板产生的 `deprecated_member_use` 做窄范围豁免。
- Flutter 3.50.0 会把 app 的 `profile.applicationIdSuffix` 复制给插件库并导致
  Android 配置失败（上游 issue #196412）。当前通过 Variant API 设置 profile
  包名，保留独立安装能力；上游修复后应移除该兼容逻辑。
- Flutter 3.50.0 的 `--no-pub` release 构建会排除 `integration_test` 原生模块，
  却保留开发态插件注册（上游 issue #169336 / #163774）。当前在 CI、Agent 和发布
  脚本中先执行不带 `--no-pub` 的 `build apk --config-only --release`，再执行
  `--no-pub` 实际构建；升级 Flutter 后应验证并移除该兼容步骤。
- Windows 构建出现 `flutter_inappwebview_windows` 的 CMake `CMP0175` 开发警告；
  当前不影响构建与启动，继续跟随插件升级观察。
- Windows OverlayPortal/UIA 上游间歇风险继续观察，不误判为业务回归。
- 日志清理已增加 Windows 临时目录有界重试，清理用例也会等待目录可见性与
  新文件重建；分享密码恢复测试的真实 sqlite 等待上限已从 5 秒调整为 30 秒。
  当前全量通过，后续继续观察较慢 CI 环境。
- 收藏文件夹自动检测只在应用启动或回到前台且到期时执行；应用进程被系统
  结束后不会定时唤醒，Windows 关闭窗口后同样停止。检测期间的进度通知与
  前台服务只用于本轮临时后台保活。
- 2026-11-21 自适应菜单批次的全量测试耗时 4 min 42 s、对应增量耗时
  2 min 29 s，明显高于相邻批次且无测试失败；后续继续观察是否为临时系统负载
  或测试并行度变化。
- WebDAV 自动备份同样只在应用启动或回到前台且到期时补做；应用被系统结束
  后不会定时唤醒。自动与手动备份共用 single-flight，失败后冷却一小时再补试。
- 开发环境 Flutter `3.50.0`，`pubspec.lock` 已记录 Dart `3.14.0` 与相同
  Flutter SDK 注记。

## 维护约定

- 让全量用例数、分析结果或主要规模发生变化时，更新本文件。
- 只记录当前有效基线；逐次迁移细节追加到 `BASELINE_HISTORY.md`。
- 数字必须标明全量 / 增量口径，两者不可混写。
