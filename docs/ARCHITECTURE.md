# 架构地图

> 目的：让人和 AI 代理用最少的读取量定位到该改的文件。
> 「需求 → 先读哪些文件」一节是本文件最有价值的部分，改需求前先查表。

## 一句话

蓝奏云第三方 Flutter 客户端。单进程、无后端；网络协议在 `lib/core/api/`，
状态在 2 个应用级 `ChangeNotifier`，页面在 `lib/ui/`（平铺）。

## 启动顺序（`lib/main.dart`，按实际代码）

1. `registerThirdPartyLicenses()` — 先登记素材许可证，开源许可页要用
2. `SystemChrome.setEnabledSystemUIMode(edgeToEdge)`（仅移动端）
3. `PlatformSupport.loadAndroidSdkInt()` — 预热，影响 WebView 合成方式
4. `AppLog.instance.init()` — 接管 `FlutterError.onError` / `PlatformDispatcher.onError` / `debugPrint`
5. `FlutterForegroundTask.init()`（仅移动端）— 传输期间后台保活
6. `AppController().init()` — 状态初始化入口
7. `SystemMotion.init()`、`NotificationService.init()`、`SharedInbox`、`IncomingLinks`
8. `BackupService.maybeAutoBackup()`（不阻塞）
9. 创建更新试点 `ProviderContainer`，恢复更新缓存后非阻塞执行
   `UpdateService.maybeAutoCheck()`
10. `runApp(UncontrolledProviderScope(...))` — Riverpod 更新作用域包裹
    `MultiProvider`，继续注入 `AppController` + `TransferManager`

## 状态层

旧 Provider 栈只有两个应用级 `ChangeNotifier`，都在 `main.dart` 注入；
`core/update/` 的 `UpdateService` 是阶段 1 Riverpod 试点：

| 对象 | 文件 | 说明 |
| --- | --- | --- |
| `AppController` | `core/app_controller.dart`（637 行） | 账号、网盘、设置等大部分状态。职责偏宽，是已知问题 |
| `TransferManager` | `core/transfer/transfer_manager.dart` | 上传/下载任务队列 |
| `UpdateService` | `core/update/update_service.dart` | `Notifier<UpdateState>`；更新检查、缓存、失败冷却和一次性提醒的唯一所有者 |
| `AppDb` | `core/data/app_db_provider.dart` | 阶段 2 首个叶子依赖；普通 `Provider` 暴露既有单例，不监听、不自动销毁 |
| `LanzouClientRegistry` | `core/api/lanzou_client_registry.dart` | 按 uid 缓存账号客户端并保留独立公开客户端；Provider 与 `AppController` 共用同一注册表 |
| `AppLog` | `core/app_log_provider.dart` | 启动时先初始化，再通过普通 `Provider` 暴露同一实例；更新服务已从容器读取 |
| `NotificationService` | `core/notifications_provider.dart` | 初始化后通过普通 `Provider` 暴露同一单例；`TransferManager` 的进度与完成通知使用构造注入实例 |
| `SharedDownloadsGateway` | `core/shared_downloads_gateway.dart` | 公共 Downloads 能力接口；生产实现委托原 MethodChannel，目录解析与传输保存改用注入实例 |
| `SettingsStore` / `AccountStore` | `core/data/*_store_provider.dart` | 普通 `Provider` 暴露已加载的可写存储，不当作监听状态；更新服务已统一读取 `settingsStoreProvider` |
| `DownloadPathService` | `core/download_path_service.dart` | 无状态默认下载目录解析；依赖 `SharedDownloadsGateway`，`AppController` 原方法签名保持不变 |
| `NavigationState` | `core/navigation_state.dart` | 阶段 3：多选、返回处理器、`driveCanHandleBack`、当前 Tab 和顶/底栏高频进度的唯一所有者；旧 `AppController` 仅转发 |
| `DriveState` | `core/drive_state.dart` | 阶段 3：目录缓存、目录请求、当前位置和可见性探针的唯一所有者；`DriveLocation` 继续由旧控制器导出 |
| `AccountState` | `core/account_state.dart` | 阶段 3：唯一持有 `AccountStore`；`accountStoreProvider` 与旧 `AppController.accounts` 均从它派生 |
| `SettingsState` | `core/settings_state.dart` | 阶段 3：唯一持有 `SettingsStore`；`settingsStoreProvider` 与旧 `AppController.settings` 均从它派生 |
| `UpdateSettingsState` | `core/update/update_settings_state.dart` | 阶段 3 设置子组：收窄更新通道与自动检查开关的读写边界，持久化仍由 `SettingsStore` 独占 |
| `NotificationSettingsState` | `core/notification_settings_state.dart` | 阶段 3 设置子组：进度通知与完成通知开关的明确读写入口 |

消费现状：`context.read<…>` 约 150 处、`context.watch<…>` 约 17 处。
UpdateService 试点前 `context.select<…>` 为 0；更新页现在用两处 `select`
只订阅更新通道与自动检查开关。其余新增 UI 仍应优先用 `select` 或
`ValueListenableBuilder` 收窄订阅范围，不要继续放大。

## 导航与弹层

- 根：`app.dart` 的 `LanCloudApp`（含 `MaterialApp`、主题、`locale`）
  → `AgreementGate`（首启条款门）→ `UpdatePromptHost` → `RootShell`
- `RootShell`：`NavigationBar` + `PageView` 的外壳。主 tab 页为
  `ui/home_page.dart`、`ui/drive_page.dart`、`ui/transfers_page.dart`、`ui/profile_page.dart`
  （以 `app.dart` 里 `RootShell` 的实际实现为准）
- **没有路由库**（无 `go_router` / `auto_route`），不要引入。跨页面用 `Navigator.push`，
  页面内切换用外壳状态。
- 弹层约定：一律写成 `Future<结果类型?> showXxx(BuildContext context)`，
  把「弹什么、返回什么」收敛到一个具名函数。现有例子：
  `showAppSheet`、`showM3eMenu`、`showLoginSheet`、`showBackupUnlockDialog`。
  **禁止在 widget 里内联 `showDialog(...)` 现场拼装。**

## 子系统地图

| 目录／文件 | 职责 |
| --- | --- |
| `core/api/lanzou_client.dart` | 蓝奏云 HTTP 客户端（`dio`），协议细节见 `docs/PROTOCOL.md` |
| `core/api/models.dart` | 接口模型 |
| `core/api/acw_sc_v2.dart` | 反爬 cookie 挑战（ACW_SC_V2）求解 |
| `core/data/app_db.dart` | `sqflite` 本地库；桌面端通过 `sqflite_common_ffi` 走 FFI |
| `core/data/settings_store.dart` | 设置项，`shared_preferences` |
| `core/data/account_store.dart`、`core/data/secure_storage.dart` | 账号与凭据，`flutter_secure_storage` |
| `core/data/account_data.dart` | 账号模型 |
| `core/transfer/transfer_manager.dart` | 任务队列、进度、重试 |
| `core/backup/` | 本地备份与恢复：`backup_service`（编排）、`backup_crypto`（加解密）、`backup_sections`、`webdav_client` / `webdav_store` |
| `core/update/` | 更新检查：`update_service`、`release_info`、`changelog` |
| `core/platform_support.dart` | 平台判定与 Android SDK 级别，所有平台分支的唯一入口 |
| `core/cookie_auth.dart` | 登录态与 cookie |
| `core/lanzou_link.dart` | 分享链接解析 |
| `ui/m3e.dart` | MD3E 组件统一出口（`export` + 薄封装），页面只从这里取 MD3E 控件 |
| `ui/common.dart` | 跨页面共用的小组件与常量 |
| `app.dart` | 主题构建（`buildTheme` / `buildLanCloudTheme`）、`MaterialApp`、`RootShell` |

## 需求 → 先读哪些文件

| 需求 | 先读 |
| --- | --- |
| 下载 / 传输队列 | `core/transfer/transfer_manager.dart`、`core/download_target.dart`、`core/download_dir.dart`、`core/saved_file.dart`、`ui/transfers_page.dart`、`ui/download_mark.dart` |
| 上传 / 文件选择 / 保存 | `core/file_picker_channel.dart`、`core/system_file_saver.dart`、`core/shared_downloads_storage.dart`、`ui/drop_actions.dart` |
| 登录 / 鉴权 / 反爬 | `core/cookie_auth.dart`、`core/api/acw_sc_v2.dart`、`ui/login_page.dart`、`ui/web_login_page.dart`、`ui/cookie_sheet.dart` |
| 分享链接 / 提取码 | `core/lanzou_link.dart`、`ui/share_page.dart`、`ui/share_file_sheet.dart`、`ui/share_folder_page.dart`、`ui/share_password_dialog.dart` |
| 备份 / 恢复 / WebDAV | `core/backup/*`、`ui/backup_page.dart`、`ui/backup_options_page.dart`、`ui/restore_page.dart`、`ui/restore_dialogs.dart` |
| 自动更新 / APK 安装 | `core/update/*`、`core/apk_installer.dart`、`ui/update_page.dart`、`ui/update_prompt.dart` |
| 本地数据 / 设置项 | `core/data/*`（先看 `app_db.dart` 表结构，再看 `settings_store.dart`） |
| 平台差异（Android / Windows） | `core/platform_support.dart`、`core/saf_storage.dart`、`core/system_open.dart`、`core/system_share.dart`、`core/window_frame.dart`、`core/drag_drop.dart` |
| 主题 / 动效 / 无障碍 | `app.dart`（主题）、`ui/m3e.dart`、`core/dynamic_color_support.dart`、`core/system_motion.dart`、`ui/reduce_motion.dart` |
| 日志 / 崩溃 / 诊断 | `core/app_log.dart`、`core/webview_diagnostics.dart` |
| 文案 / 国际化 | `lib/l10n/app_zh.arb`（模板）、`app_en.arb`、`l10n.yaml` |
| 版本号 | `docs/VERSIONING.md`、`tool/bump_version.dart`、`lib/core/app_info.dart` |

## 平台

- 有平台目录：`android/`、`ios/`、`windows/`
- **没有** `web/`、`macos/`、`linux/`，不要创建，也不要写只在 web 生效的分支
- OHOS 适配见 `docs/OHOS_ADAPTATION.md`；仓库当前未跟踪 `ohos/` 目录，相关改动先问

## 不变量（改动前确认，别顺手破掉）

1. 版本号只能由 `tool/bump_version.dart` 同时改 `pubspec.yaml` 与 `lib/core/app_info.dart`（有测试校验）
2. `material_ui` / `m3e_core` / `cupertino_ui` 三件套必须同步升级；`material_ui` 不得 ≥ 1.8.0
3. 文案模板是 `app_zh.arb`，中英两份必须同时改，改完跑 `gen-l10n`
4. `android/gradle.properties` 的 `force-version-code-ignoring-abi` 是 versionCode 位段方案的一部分，不要动
5. `lib/core/third_party_licenses.dart` 的登记结构涉及许可证合规，新增素材要按同格式追加
