# AppController 退役接力 Prompt

将下面整段复制到新对话，作为继续任务的首条消息。

---

继续 `C:\Users\Potato\Desktop\LanCloud` 的 AppController 渐进退役。

开始前必须完整阅读：

- `AGENTS.md`
- `docs/ARCHITECTURE.md`
- `docs/RIVERPOD_MIGRATION_ASSESSMENT.md`
- `docs/BASELINE.md`

先运行 `git status --short --branch` 和 `git log -8 --oneline`。不要 reset、
checkout 或覆盖当前未提交改动。Flutter/Dart 只能通过 `tools\agent.cmd`，
禁止直接调用 `flutter` / `dart`；日常验证只运行无参：

```powershell
tools\agent.cmd analyze
tools\agent.cmd test
```

## 已完成的迁移

- Provider → Riverpod 阶段 6 已完成，`provider` 依赖已移除。
- UI 不再读取 `AppController`。
- `BackupService` 已通过 `BackupDependencies` /
  `BackupStoreDependencies` 解耦，`AppController` 不再实现备份接口。
- `TransferManager` 已由 Riverpod 管理。
- 最近一次已提交状态的全量验证：analyze 0 issue，727 tests 全部通过。

## 当前未提交切片

当前工作区可能包含一个尚未提交的下载端口切片：

- `DefaultTransferDownloadPort` 已加入
  `lib/core/transfer/transfer_download_port.dart`。
- 下载目标模式、固定目录、SAF 中转、临时文件清理和唯一保存路径已从
  `AppController` 移入该端口；控制器暂时保留同名兼容转发。
- `test/transfer_dependencies_test.dart` 已改为断言生产端口类型，并新增
  唯一保存路径冲突测试。
- 文档 `ARCHITECTURE.md`、`RIVERPOD_MIGRATION_ASSESSMENT.md`、
  `BASELINE.md` 已记录该切片。
- 该切片增量验证：64 个测试文件 / 365 tests 通过；新增 1 条测试后当前总数为
  728，但 728 用例全量测试尚未在该未提交状态上运行。

第一步先审阅 `git diff`，在当前工作树上运行无参 analyze/test。通过后建议拆成：

1. 代码+测试：`refactor(transfer): 抽出默认下载端口`
2. 文档：`docs(transfer): 记录默认下载端口迁移`

未获得用户明确“提交”指令时不要 commit。

## 当前耦合概况

- `AppController` 约 690 行。
- 生产代码只有 `lib/main.dart` 直接引用 `AppController`，其余出现是文档注释。
- 测试仍有约 72 个文件、225 处 `AppController` 引用。
- 剩余生产职责主要是启动初始化、状态对象组装和
  `TransferDependencies` 兼容装配。

## 后续建议顺序

1. 在 `main.dart` 直接组装 `TransferDependencies`：
   - `AppDbTransferStore`
   - `AppTransferAccountPort`
   - `DefaultTransferDownloadPort`
   - `StoreTransferSettingsPort`
   保留启动顺序和同一实例；之后从 `AppController` 删除
   `TransferDependenciesProvider` 兼容实现。
2. 抽独立启动 composition root，保持 `main()` 中
   `AppController().init()` → `runApp()` 的现有先后顺序不变。
3. 分批迁移约 72 个测试夹具，避免一次全改。
4. 删除 `AppController` 兼容 getter/setter、旧测试与控制器本体。
5. 每片更新基线；用例数变化时同步 `docs/BASELINE.md`。

## 红线

- 一次只改一个模块；预计超过 5 个文件先拆分。
- 跨 `core × ui` 的改动先给计划并等待用户确认。
- 不改变启动、登录、传输恢复、备份恢复和返回手势行为。
- 不增删升降第三方依赖。
- 不使用 `autoDispose` 管理应用级状态。
- 禁止 `ignore:`、`dynamic` 或放宽 strict 检查来消除分析错误。
- 不修改 `refs/`、`outputs/`、`build/`、`ohos/`、生成 l10n 文件。
- Windows OverlayPortal/UIA 上游间歇风险继续观察，不误判为本次回归。

## 汇报格式

汇报必须是：

1. 改了哪些文件
2. 为什么
3. 执行了哪些 `tools\agent.cmd` 命令及结果
4. 当前未提交/已提交状态
5. 遗留风险与下一步
