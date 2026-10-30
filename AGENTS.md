# AGENTS.md — LanCloud（蓝云）

蓝奏云第三方 Flutter 客户端。个人维护的**生产项目**：`lib` 约 4.7 万行 / 95 个文件，
`test` 121 个文件 / 616 个测试。改动的默认要求是「不破坏现有行为」，不是「尽量多写」。

## 动手前先读

| 文档 | 什么时候读 |
| --- | --- |
| `docs/ARCHITECTURE.md` | **每次任务开始**。先查「需求 → 先读哪些文件」表，别整仓乱翻 |
| `docs/BASELINE.md` | 需要判断某个红灯是不是你造成的 |
| `docs/VERSIONING.md` | 任何涉及版本号的改动 |
| `docs/PROTOCOL.md` | 改 `core/api/` 的网络与协议逻辑 |
| `docs/RIVERPOD_MIGRATION_ASSESSMENT.md` | 任何触及状态管理（Provider / Riverpod / ChangeNotifier）的改动 |

## 工具链：唯一入口是 `tools\agent.cmd`

`tools\agent.cmd` 是唯一入口。它内部调用 `tools\flutter.cmd`，后者钉住了
`JAVA_HOME=C:\dev\java17`、`ANDROID_HOME`、`PUB_HOSTED_URL`。
**不要直接调用 `flutter` / `dart`，也不要绕过 agent.cmd 去调 flutter.cmd 跑日常任务**
——会用到另一套环境（`flutter doctor` 报的是 Android Studio 自带的 JDK 25），出问题极难排查。

```powershell
C:\Users\Potato\Desktop\LanCloud\tools\agent.cmd analyze   # 有未提交改动→只分析它们；否则全量
C:\Users\Potato\Desktop\LanCloud\tools\agent.cmd test      # 自动推断受影响的测试；推断不出→全量
C:\Users\Potato\Desktop\LanCloud\tools\agent.cmd gen       # 改完 arb 之后
C:\Users\Potato\Desktop\LanCloud\tools\agent.cmd help      # 全部动词
```

其他动词：`pubget`、`build-apk`、`install`、`logcat`、`devices`，
其余名字（`run`、`doctor`、`emulators`…）透传给 flutter。

- **原样执行，不要追加 `| Select-Object`、`2>&1`、`;` 等修饰，也不要带参数。**
  免批准规则对「整条 PowerShell 脚本」做整串相等匹配（Codex 不拆分 `pwsh -Command`
  里的脚本），所以 `agent.cmd analyze lib\ui\x.dart` 这种带参数的写法同样不匹配，
  会弹一次批准。日常请用无参形式——动作由脚本自己判断（看 git 改动 / 推断测试）。
  需要更少/更多输出时改脚本，不要在命令行上过滤，否则规则文件会重新膨胀。
- 规则文件：`~/.codex/rules/default.rules`。里面每条规则都带 `match`/`not_match`
  内联测试，**写错会在加载时直接报错**。改完用
  `codex execpolicy check --rules <该文件> -- <pwsh 路径> -Command "<命令>"`
  自检，并重启 Codex 生效。新增 `agent.cmd` 动词时必须同步加一条规则。
- 一律 `--no-pub`（脚本已内置）：隐式 `pub get` 又慢又需要联网，沙箱里会直接失败。
  确实需要装依赖时用 `agent.cmd pubget`。
- 全量分析/测试留给人工兜底；你改完只需跑这两个无参命令（已是增量的）。
- 改版本只能 `dart run tool/bump_version.dart`（同时改 `pubspec.yaml` 与
  `lib/core/app_info.dart`，有测试校验）。禁止手改这两个文件的版本行，
  禁止用 `--build-number` 顶 versionCode。
- `tool/` 放 Dart 脚本，`tools/` 放 PowerShell 脚本。不要另建第三种位置。
  新增 `tools\agent.cmd` 动词时，必须同时在 `~/.codex/rules/default.rules` 加一条规则。

## 结构

```
lib/main.dart          启动装配（Provider、日志、通知、自动备份/更新）
lib/app.dart           主题构建 + MaterialApp + RootShell（NavigationBar + PageView）
lib/core/              逻辑与平台能力（32 个平铺文件）
lib/core/api/          lanzou_client / models / acw_sc_v2
lib/core/data/         app_db(sqflite) / settings_store / account_store / secure_storage
lib/core/transfer/     transfer_manager
lib/core/backup/       backup_service / backup_crypto / webdav_client / webdav_store
lib/core/update/       update_service / release_info / changelog
lib/ui/                页面与组件（40 个平铺文件）
lib/l10n/              arb + 生成文件
```

## 依赖锁定（不得擅自增删升降）

- `material_ui >=1.6.0 <1.8.0`、`m3e_core ^1.1.4`、`cupertino_ui ^1.1.4` 三件套必须同步。
  **不要升到 `material_ui` 1.8**：它的 `RoundedPolygon` 与 `m3e_core` 1.1.4 同名类型冲突。
- Flutter 3.47 起 Material 已从框架拆出：用 `package:material_ui/material_ui.dart`，
  不存在 `package:flutter/material.dart` 这个导入。MD3E 控件从 `ui/m3e.dart` 取。
- 新增第三方依赖：**先问人**，不要直接 `pub add`。

## 代码约定（从现有代码归纳，不是理想规范）

- **语言**：注释、提交信息、UI 文案用中文；标识符用英文。
- **状态**：应用级只有 `AppController` 与 `TransferManager` 两个 `ChangeNotifier`。
  新增 UI 需要订阅状态时优先 `context.select(...)` 或 `ValueListenableBuilder`：
  全仓 `context.select` 目前为 0、`read` 约 150、`watch` 约 17，重建面已经偏大，别再放大。
- **弹层**：必须写成 `Future<结果类型?> showXxx(BuildContext context)`，返回带类型的结果；
  参考 `showAppSheet`、`showM3eMenu`、`showLoginSheet`、`showBackupUnlockDialog`。
  **禁止**在 widget 里内联 `showDialog(...)` 临时拼装。
- **导航**：没有路由库，不要引入 `go_router` / `auto_route`。跨页面用 `Navigator.push`。
- **平台分支**：只走 `core/platform_support.dart`，不要在 UI 里裸写 `Platform.isAndroid`。
- **文案**：一律 `AppLocalizations.of(context)!.xxx`，禁止硬编码用户可见字符串。
- **不要让静态分析变红，也不要「压」掉它**：`analysis_options.yaml` 已开启
  `strict-casts` / `strict-inference` / `strict-raw-types`，全仓当前 0 issue，这个基线要保持。
  **禁止**为过检查而加 `// ignore:`、改成 `dynamic`、或把类型断言换成 `as dynamic`。
  确需豁免时，`ignore` 注释必须写明具体理由，并在汇报里单独说明。
- **JSON 解码边界**：`core/api/` 里对 payload 的显式 `as Map` / `as List` 是开发者主动断言，
  不要为了"消除告警"去全量改成 `is` 判断——`strict-casts` 只管 `dynamic` 的隐式下转型，
  显式 `as` 本来就不报。若要做运行时加固，只在解码入口加结构校验，不要散落到调用点。

## 不要碰

- `refs/`（第三方参照源码）、`outputs/`、`build/`、`ohos/`、`.vscode/`
- `lib/l10n/app_localizations*.dart`（生成文件）
- `pubspec.yaml` 与 `lib/core/app_info.dart` 的版本行
- `android/gradle.properties` 里的 `force-version-code-ignoring-abi`
- `lib/core/third_party_licenses.dart` 的登记结构（许可证合规）
- `analysis_options.yaml` 的 `exclude` 列表

## 完成定义（DoD）

1. 跑过 `tools\agent.cmd analyze`（有未提交改动时即增量），无新增 issue
2. 跑过 `tools\agent.cmd test` 并通过；它推断不出受影响文件时会跑全量，属正常
3. 触及 `core/api/`、`core/data/`、`core/transfer/`、`core/backup/`、`core/update/`
   的改动**必须**带测试（新增或更新）
4. 若用例总数发生变化，同步 `docs/BASELINE.md` 里的用例数与耗时（标明全量/增量口径）
5. 汇报格式：**改了哪些文件 → 为什么 → 用哪条命令验证、结果如何 → 遗留风险**

没做到 1–3 就别说「完成」。

## 纪律

- 一次只改一个模块。跨 `core` × `ui` 的改动，**先给计划等人确认**再动手。
- 单个任务预计改动超过 5 个文件，停下来先说明拆分方案。
- 第一次进入某个子系统时，先读相关文件再提方案；不要凭印象改。
- 报错先读完整堆栈，禁止「猜一个改一个」。
- 不确定就问；不要默默扩大改动范围。
- 提交信息格式 `type(scope): 中文描述`（如 `fix(transfers): 修复批量删除后的动画重播`）。
  不要直接推 `main`，走分支 + PR。
- 不要自行 `git commit`，除非明确要求。

## Riverpod 试点（已授权，但范围严格受限）

方案细节见 `docs/RIVERPOD_MIGRATION_ASSESSMENT.md`。

**只批准了阶段 0 + 阶段 1**，即 `core/update/` 的 `UpdateService` 试点。
阶段 2 及以后（叶子依赖、状态拆分、UI 消费端、`TransferManager`、移除 Provider）
**必须逐阶段取得人工批准**，不得自行推进。

### 阶段 0：边界
1. 保留 `main()` 里 `AppController().init()` → `runApp()` 的现有结构，**不改造启动流程**。
2. 双栈共存：Riverpod 只服务试点，其余页面继续用 Provider。
3. 为同时需要两者的 Widget / 测试提供统一包装 helper；
   **不要批量改 39 个 Provider 测试文件**，随功能迁移逐个改。
4. 依赖升级、状态重构、UI 迁移**分成独立提交**，不要混在一起；分支要能整体回退。
5. 不改变用户行为。

### 阶段 1：UpdateService
- 先把更新状态整理成明确的数据模型，再决定用 `Notifier` 还是 `AsyncNotifier`。
- 必须保留的既有语义：更新通道、缓存有效期、12 小时自动检查、
  **每个版本只提醒一次**。
- 不新增会阻塞启动的 provider；应用级状态**不用 `autoDispose`**。
- 本阶段不碰登录、传输、数据库、主题状态。

### 全局红线
- **单一状态所有者**：同一字段不允许在 Provider 与 Riverpod 两侧同时可写，
  另一侧只能转发或读取。
- 高频状态（滚动/动画/下载进度）继续用 `ValueNotifier` + `ValueListenableBuilder`，
  不要为了「统一技术栈」机械替换。
- 不引入 `riverpod_generator` / `riverpod_lint` / `build_runner`：codegen 延后，
  不与首次迁移同时引入。
- 选型以实际安装的 `flutter_riverpod` 版本为准（评估时为 3.4.3）。
  **不要套用 2.x 时代的写法**（`StateNotifier` 那一套）；不确定就查官方文档或来问，不要猜。
- 每个提交都要保持 `analyze` 0 issue + `agent.cmd test` 通过。

### 停下来重新决策的条件
试点做完后，如果收益主要是「换了 API 名字」而不是状态代码更小/更清晰，
或者测试并没有更容易注入假数据 —— **停止后续迁移**，保留 Riverpod 作为新功能备选方案，
改为优化现有 Provider 结构（`context.select` 收窄重建）。这个判断必须写进汇报。

## 进行中的决策（不要擅自执行）

- **OHOS 适配**：见 `docs/OHOS_ADAPTATION.md`，仓库当前未跟踪 `ohos/` 目录。

## 术语

| 词 | 含义 |
| --- | --- |
| 蓝奏云 | 网盘服务，本项目的对接对象 |
| 分享链接 / 提取码 | 蓝奏云的公开分享形式，需解析出真实下载地址 |
| `folsha2` / `folsha3` | 蓝奏云文件夹相关哈希参数 |
| WebDAV | 备份目标，见 `core/backup/webdav_*` |
| MD3E | Material 3 Expressive，通过 `m3e_core` 提供，入口 `ui/m3e.dart` |
| ACW_SC_V2 | 反爬 cookie 挑战，见 `core/api/acw_sc_v2.dart` |
| RootShell | 主外壳（NavigationBar + PageView），在 `app.dart` |
| 传输中心 | 上传/下载任务页 `ui/transfers_page.dart` + `TransferManager` |
