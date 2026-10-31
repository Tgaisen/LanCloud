# AppController 退役接力 Prompt

将下面整段复制到新对话，作为继续任务的首条消息。

---

继续 `C:\Users\Potato\Desktop\LanCloud` 的 AppController 渐进退役。

开始前必须完整阅读：

- `AGENTS.md`
- `docs/ARCHITECTURE.md`
- `docs/RIVERPOD_MIGRATION_ASSESSMENT.md`
- `docs/BASELINE.md`
- 本文件

先运行：

```powershell
git status --short --branch
git log -8 --oneline
```

不要 reset、checkout 或覆盖当前未提交改动。Flutter/Dart 只能通过
`tools\agent.cmd`，禁止直接调用 `flutter` / `dart`。日常验证只运行无参命令：

```powershell
tools\agent.cmd analyze
tools\agent.cmd test
```

## 当前基线

- 分支：`riverpod_test`
- 最近一次全量验证：`analyze` 0 issue；`test` 716 个全部通过，约 106 s。
- Provider 依赖、注册和 UI 消费面已全部移除，阶段 6 已完成。
- UI 不再读取 `AppController`。
- `BackupService` 已通过 `BackupDependencies` /
  `BackupStoreDependencies` 解耦。
- `TransferManager` 由 Riverpod 管理；所有 `TransferManager(app)` 和
  `TransferDependenciesProvider` 已删除。
- 下载目标、SAF 中转、唯一路径和目录设置由
  `DefaultTransferDownloadPort` / `DownloadDirectorySettingsState` 负责。
- 导航、目录、运行时、更新、通知、各设置子组、动态取色默认探测均已迁到
  独立 Riverpod 状态对象。
- `AppCompositionRoot` 负责组装备份、传输依赖和 Riverpod 容器，不触发启动
  副作用。

## 当前耦合概况

- `AppController` 约 223 行。
- 生产代码只有 `lib/main.dart` 和 `lib/core/app_composition_root.dart`
  直接引用 `AppController`。
- 测试仍有约 57 个文件、180 处 `AppController` 引用。
- 测试中仍有约 29 处、13 个文件的 `app.accounts` / `app.settings` 引用：
  - `test/accessibility_test.dart`
  - `test/drive_multi_select_test.dart`
  - `test/drive_paging_test.dart`
  - `test/file_icons_test.dart`
  - `test/permissions_settings_test.dart`
  - `test/property_sheet_quick_actions_test.dart`
  - `test/settings_search_test.dart`
  - `test/shell_inset_test.dart`
  - `test/show_cookie_settings_tile_test.dart`
  - `test/transfer_retry_test.dart`
  - `test/update_page_test.dart`
  - `test/update_prompt_test.dart`
  - `test/update_test_scope_test.dart`

控制器剩余职责：

- 构造应用级状态对象并挂监听：`UpdateSettingsState`、
  `NavigationAppearanceSettingsState`、`ThemeSettingsState`、
  `TransferConnectionSettingsState`、`ListHomeSettingsState`、
  `LanguageClipboardSettingsState`、`CachePageSettingsState`、
  `DownloadDirectorySettingsState`。
- 创建 `AccountLogin`、`AccountSession`、`LanzouClientRegistry`。
- `accounts/settings` 存储 getter。
- `init()`：安全存储升级检查、账号/设置加载、运行时设置同步、目录缓存绑定、
  ready、账号资料刷新、动态取色默认探测。
- `reloadFromStorage()`：备份恢复后重载账号/设置、刷新主题/语言、清理客户端
  缓存、重绑目录缓存。
- 生命周期监听和 `dispose()`。

## 后续建议顺序

1. 继续分批迁移测试中的 `app.accounts/settings`：
   - 第一批候选：`accessibility_test`、`permissions_settings_test`、
     `settings_search_test`、`update_prompt_test`。
   - 后续处理网盘、传输、更新页测试。
   - 每批最多 4 个测试文件，另加基线文档。
2. 将控制器内部对 `accounts/settings` 的使用改为
   `accountState.store` / `settingsState.store`，确认测试清零后删除 getter。
3. 把状态对象组装从 `AppController` 移到组合根或独立应用环境对象；必须保持
   所有 store/provider 仍指向同一实例。
4. 抽独立启动初始化流程，保持 `main()` 中
   `AppController().init()` 到 `runApp()` 的先后顺序。保留：
   - 安全存储升级检查先于账号首次读取
   - 账号/设置加载后才同步 `LanzouClient` 静态配置
   - ready 与目录缓存绑定顺序
   - 账号资料后台刷新和动态取色探测不阻塞
5. 分批迁移剩余测试夹具，最后删除 `AppController` 和其他仅兼容注释。
6. 每片更新 `docs/BASELINE.md`；用例数变化时更新总数和口径。

## 红线

- 一次只改一个模块；预计超过 5 个文件先拆分。
- 跨 `core × ui` 的改动先给计划并等待用户确认。
- 不改变启动、登录、传输恢复、备份恢复和返回手势行为。
- 不增删升降第三方依赖。
- 应用级状态不使用 `autoDispose`。
- 禁止 `ignore:`、`dynamic` 或放宽 strict 检查来消除分析错误。
- 不修改 `refs/`、`outputs/`、`build/`、`ohos/`、生成 l10n 文件。
- Windows OverlayPortal/UIA 上游间歇风险继续观察，不误判为本次回归。
- 未获得用户明确“提交”指令时不要 commit。

## 汇报格式

1. 改了哪些文件
2. 为什么
3. 执行了哪些 `tools\agent.cmd` 命令及结果
4. 当前未提交/已提交状态
5. 遗留风险与下一步
