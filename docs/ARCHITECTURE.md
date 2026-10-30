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
10. `runApp(UncontrolledProviderScope(...))` — Riverpod 作用域包裹旧
    `ChangeNotifierProvider<AppController>`；启动前主动读取
    `transferManagerProvider` 保持任务恢复顺序，旧 Provider 不再注册传输管理器

## 状态层

旧 Provider 栈只剩应用级 `AppController`，仍在 `main.dart` 注入；
`TransferManager` 已只由 Riverpod 容器提供。`core/update/` 的 `UpdateService`
是阶段 1 Riverpod 试点：

| 对象 | 文件 | 说明 |
| --- | --- | --- |
| `AppController` | `core/app_controller.dart`（637 行） | 账号、网盘、设置等大部分状态。职责偏宽，是已知问题 |
| `TransferManager` | `core/transfer/transfer_manager.dart` | 上传/下载任务队列 |
| `TransferStore` | `core/transfer/transfer_store.dart` | 传输记录恢复/保存/删除与下载标记端口；`AppDbTransferStore` 适配既有数据库 |
| `TransferAccountPort` | `core/transfer/transfer_account_port.dart` | 当前 UID、账号存在性、账号客户端与公开客户端端口；包装账号存储和客户端注册表 |
| `TransferDownloadPort` | `core/transfer/transfer_download_port.dart` | 下载目标模式、SAF URI、中转路径与唯一保存路径端口 |
| `TransferSettingsPort` | `core/transfer/transfer_settings_port.dart` | 并发数、进度/完成通知和传输设置读取端口 |
| `TransferDependencies` | `core/transfer/transfer_dependencies.dart` | 四个传输端口组成的显式应用级依赖集合 |
| `transferManagerProvider` | `core/transfer/transfer_manager_provider.dart` | 应用级、非 autoDispose 的 `TransferManager` 唯一实例；容器负责释放 |
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
| `AccountLogin` | `core/account_login.dart` | Cookie 登录验证、账号落盘、客户端缓存和网盘缓存切换；通过 `accountStateProvider` 通知账号变化 |
| `SettingsState` | `core/settings_state.dart` | 阶段 3：唯一持有 `SettingsStore`；`settingsStoreProvider` 与旧 `AppController.settings` 均从它派生 |
| `UpdateSettingsState` | `core/update/update_settings_state.dart` | 阶段 3 设置子组：收窄更新通道与自动检查开关的读写边界，持久化仍由 `SettingsStore` 独占 |
| `NotificationSettingsState` | `core/notification_settings_state.dart` | 阶段 3 设置子组：进度通知与完成通知开关的明确读写入口 |
| `NavigationAppearanceSettingsState` | `core/navigation_appearance_settings_state.dart` | 阶段 3 设置子组：侧滑、顶/底栏隐藏、悬浮导航、转场与导航项显示开关 |
| `ThemeSettingsState` | `core/theme_settings_state.dart` | 阶段 3 设置子组：主题模式/种子、OLED、动态取色与全局动画开关 |
| `TransferConnectionSettingsState` | `core/transfer_connection_settings_state.dart` | 阶段 3 设置子组：请求间隔、并发数、API 域名、UA 与上传路径 |
| `ListHomeSettingsState` | `core/list_home_settings_state.dart` | 阶段 3 设置子组：列表排序、首页折叠、最近使用上限与文件夹打开模式 |
| `LanguageClipboardSettingsState` | `core/language_clipboard_settings_state.dart` | 阶段 3 设置子组：界面语言与复制分享链接提示 |
| `CachePageSettingsState` | `core/cache_page_settings_state.dart` | 阶段 3 设置子组：网格视图、启动页、目录缓存和自动加载全部页面 |
| `DownloadDirectorySettingsState` | `core/download_directory_settings_state.dart` | 阶段 3 设置子组：普通下载目录、SAF URI/标签、互斥写入和旧授权释放入口 |

消费现状：`context.read<…>` 约 119 处、`context.watch<…>` 0 处、
`context.select<…>` 11 处。生产代码中的整体 `watch` 已清零；传输页已从
Riverpod 读取应用级 `TransferManager`，并通过 `ListenableBuilder` 保留既有
`notifyListeners()` 刷新语义。`RootShell` 也已从 Riverpod 取得同一管理器，
并用局部计数桥只在运行中 / 排队任务数变化时重建外壳；管理器的进度通知不会
直接放大成整壳重建。“已下载”标记也从 Riverpod 读取管理器，继续只监听低频
`marksRevision`；已下载任务的二级菜单和分享文件属性弹窗也已从 Riverpod 读取。
`DrivePage` 已改用 `ConsumerStatefulWidget`，生命周期监听、上传、批量下载、
自有文件下载、属性卡状态和已下载菜单全部从 Riverpod 取得管理器。对应的四个
直接测试宿主不再注册旧 `ChangeNotifierProvider<TransferManager>`。
分享文件夹页的条目菜单也已从 Riverpod 读取已下载状态。
共享的单文件与批量分享下载入口均已改为从 Riverpod 读取管理器。
拖放上传入口也已迁入 Riverpod。生产代码已无旧 Provider 的
`TransferManager` 读取 / 整体订阅；`RootShell` 与首页共用
`TransferRunningCount`，只在运行中 / 排队任务数变化时重建。
启动装配和测试宿主也已移除 `ChangeNotifierProvider<TransferManager>`。
阶段 6 准备已获授权：后续按页面迁移剩余 `AppController` Provider 消费端，
但暂时保留 `provider` 依赖、根控制器注入和现有状态所有权，不执行最终移除。
`UpdateContent` 已不再读取 `AppController`，更新状态与更新设置均从 Riverpod
读取；设置 store 的变更通过局部 revision 触发。其余新增 UI 仍应优先用
`select` 或 `ValueListenableBuilder` 收窄订阅范围，不要继续放大。
设置页的“复制分享链接后提示”行也已迁为独立 Riverpod Widget。进度通知和完成
通知开关迁入 `NotificationSettingsTile`，权限申请通过可注入回调处理；“目录缓存”
和“自动加载全部页面”迁入 `CachePageSettingsTile`，由
`CachePageSettingsState.revision` 局部刷新。关闭目录缓存时清空 `DriveCache`
的逻辑已收拢到该状态，旧 `AppController` 只转发同一实例。“悬浮导航”“滑动切页”
和“转场动画”迁入 `NavigationAppearanceSettingsTile`；其 revision 由旧
`AppController` 监听转发，迁移期仍能触发外壳刷新。“主题模式”和“纯黑深色”
迁入 `ThemeSettingsTile`，“主题色”迁入 `ThemeColorSettingsTile`；主题色弹窗
通过 `showThemeColorPicker` 返回类型化选择。`ThemeSettingsState.revision`
同样由旧控制器转发，因此根主题在应用外壳迁移前仍会立即更新。设置页主体不再
监听 `AppController`，仅用 `context.read` 读取搜索元数据和事件依赖；
“显示 Cookie”行用 `context.select` 只订阅当前 UID。“语言”已迁入
`LanguageSettingsTile`，弹窗返回语言值后通过
`LanguageClipboardSettingsState` 写入；其 revision 由旧控制器转发，根
`MaterialApp.locale` 仍会立即切换。“默认启动页”和“首页目录打开方式”已迁入
`page_behavior_settings_tile.dart`，分别通过 `CachePageSettingsState` 与
`ListHomeSettingsState` 局部刷新。“全局动画”迁入 `MotionSettingsTile`，
`ThemeSettingsState.setMotionMode` 同时更新 `SystemMotion.motionMode`，旧控制器
只保留兼容转发。“底栏显示项”迁入 `NavBarItemsSettingsTile`，多选弹窗返回
类型化草稿，确认后通过 `NavigationAppearanceSettingsState.setNavItems`
一次写入并只递增一次 revision。设置滑杆已抽成公共
`SettingsSliderTile`；“上传并发数”和“下载并发数”迁入
`TransferConcurrencySettingsTile`，通过 `TransferConnectionSettingsState.revision`
局部刷新，传输调度仍实时读取设置值。“最近使用条数”迁入
`RecentLimitSettingsTile`；`ListHomeSettingsState.setRecentLimit` 统一执行
落盘、当前账号 `AppDb.trimRecents` 和 revision 通知。“网络请求间隔”迁入
`RequestIntervalSettingsTile`；`TransferConnectionSettingsState.setRequestInterval`
同时持久化并同步 `LanzouClient.requestInterval`。接口域名、上传路径和自定义
User-Agent 也迁入 `AdvancedConnectionSettingsTile`；对应 setter 统一同步
`LanzouClient.apiBase`、`uploadPath` 和 `userAgent`。
“隐藏顶/底栏”也已迁入 `NavigationAppearanceSettingsTile`；关闭时的栏位展开动画
由 `NavigationAppearanceSettingsState` 调用注入的 `NavigationState` 执行，并沿用
旧控制器的少动效判断。“下载目录”迁入 `DownloadDirectorySettingsTile`；默认路径
解析、目录分类和系统选择器保留在 UI，普通路径与 SAF 字段的互斥写入、旧授权释放
由 `DownloadDirectorySettingsState` 独占。“我的”页主体已改用 `context.read`，
仅对 `hideTopBar` 做窄 `context.select`；账号卡片单独订阅登录态、昵称和会员等级，
不再因任意 `AppController` 通知重建整页。`RootShell` 使用外壳配置快照和
一个外壳配置快照 `context.select` 读取，运行中任务数则从 Riverpod 管理器做
过滤计数，不再因任意账户、传输进度或通知列表变化重建整棵页面分页器。应用根
`LanCloudApp` 也已改为
`ConsumerStatefulWidget`，直接监听 `ThemeSettingsState.revision` 和
`LanguageClipboardSettingsState.revision`；备份恢复后的设置重载通过显式
`refresh()` 通知根主题与语言更新。共享顶栏组件只订阅 `hideTopBar`，
`BatchActionBar` 只订阅 `floatingNavBar`，正文、浮层和滚动进度仍由各自
`ValueNotifier` 驱动。拖拽悬停提示只订阅网盘/收藏可见性快照；当前目录仍从
`DriveLocation` 实时读取。恢复页也只订阅 `hideTopBar`，备份恢复状态机继续使用
页面本地状态。首页不再整体监听 `AppController` / `TransferManager`，只订阅
`hideTopBar` 和运行中任务数；快速访问、最近使用和折叠状态继续由页面本地状态及
`AppDb.revision` 驱动。网盘页只订阅网格、浮动导航和顶/底栏隐藏的配置快照；
目录、`DriveLocation`、多选和批量操作保持原有状态机。

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

- 有平台目录：`android/`、`ios/`、`windows/`。当前产品范围只验收 Android 与
  Windows；`ios/` 目录继续保留，但暂无适配或验收计划，不作为 Riverpod
  迁移门禁。
- **没有** `web/`、`macos/`、`linux/`，不要创建，也不要写只在 web 生效的分支
- OHOS 适配见 `docs/OHOS_ADAPTATION.md`；仓库当前未跟踪 `ohos/` 目录，相关改动先问

## 不变量（改动前确认，别顺手破掉）

1. 版本号只能由 `tool/bump_version.dart` 同时改 `pubspec.yaml` 与 `lib/core/app_info.dart`（有测试校验）
2. `material_ui` / `m3e_core` / `cupertino_ui` 三件套必须同步升级；`material_ui` 不得 ≥ 1.8.0
3. 文案模板是 `app_zh.arb`，中英两份必须同时改，改完跑 `gen-l10n`
4. `android/gradle.properties` 的 `force-version-code-ignoring-abi` 是 versionCode 位段方案的一部分，不要动
5. `lib/core/third_party_licenses.dart` 的登记结构涉及许可证合规，新增素材要按同格式追加
