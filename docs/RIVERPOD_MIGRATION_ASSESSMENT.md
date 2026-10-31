# Provider → Riverpod 迁移评估报告

> 评估日期：2026-10-30  
> 对应版本：`26.1.0-pre.18+260100218`  
> 评估范围：LanCloud 当前生产代码、测试与 Flutter 工具链  
> 文档性质：迁移可行性评估与实施指南。
> **2026-10-30 起阶段 0 与阶段 1 已批准执行**（范围与红线见 `AGENTS.md`），
> 阶段 2 及以后仍需逐阶段批准。

## 1. 结论摘要

迁移技术上可行，当前风险可控；但不建议为了“Provider 的未来”立即做一次性全量重写。

当前项目虽然以小型应用起步，但维护规模已经不算小：生产代码约 3.8 万行，测试约
2.1 万行。Provider 的使用方式又比较简单，只有两个应用级 `ChangeNotifier`。真正
限制维护性和重建范围的，是 `AppController` 持有过多职责且缺少细粒度订阅，不是
Provider 包本身。

推荐策略：

1. 保留 Provider 和现有 `ValueNotifier`，继续交付当前功能。
2. 以 `UpdateService` 为隔离试点，引入 Riverpod。
3. 试点通过后，再按“叶子依赖 → 派生状态 → 业务状态 → UI 消费端 → 清理 Provider”
   的顺序迁移。
4. 如果主要目标是减少不必要的重建，先用 `context.select` 和状态拆分也能获得大部分
   收益，成本明显低于全量迁移。

| 项目 | 评估 |
| --- | --- |
| 技术可行性 | 高 |
| 一次性全量迁移风险 | 中高 |
| 机械替换的即时收益 | 低 |
| 借迁移重构状态边界的长期收益 | 中高 |
| 当前第一优先级 | 做一个小范围 Riverpod 试点，同时拆分宽泛通知 |

## 2. 评估基线

评估时执行了静态分析和完整测试：

```powershell
flutter analyze --no-pub
flutter test --no-pub --reporter compact
```

结果：

- `flutter analyze`：无问题。
- `flutter test`：616 个测试全部通过。
- Flutter：`3.47.7`，Dart：`3.13.5`。
- 当前 Provider 依赖：`provider ^6.1.5+1`。
- 评估时 pub.dev 最新 `flutter_riverpod`：`3.4.3`，要求 Dart `^3.12.0`，与当前
  工具链兼容。

这些结果说明迁移有可靠的回归基线，也说明迁移后需要维护的测试和跨平台行为并不少。

### 2.1 关键代码量

| 指标 | 数量 |
| --- | ---: |
| `lib` Dart 文件 | 95 |
| `lib` Dart 总行数 | 47,208 |
| 非生成 Dart 文件 | 92 |
| 非生成 Dart 代码行数 | 37,863 |
| 测试文件 | 121 |
| 测试代码行数 | 21,025 |
| 直接导入 Provider 的生产文件 | 21 |
| 直接导入 Provider 的测试文件 | 39 |

### 2.2 Provider 使用方式

当前只在 [main.dart](../lib/main.dart) 根部注册了两个对象：

```text
AppController
TransferManager
```

没有 `ProxyProvider`、复杂 Scope 或同一类型多实例。这使 Riverpod 官方提供的渐进式
迁移方式可以直接使用，但也意味着 Provider 目前主要承担依赖注入，而不是复杂的
响应式依赖图。

迁移评估时的生产代码消费点统计：

| 指标 | 数量 |
| --- | ---: |
| `context.read` | 150 |
| `context.watch` | 17 |
| `context.select` | 0 |
| 获取 `AppController` 的局部变量 | 96 |

读取点很多，但绝大多数是事件回调里的 `read`。这类代码迁移时主要是语法替换，不会
自动获得 Riverpod 的竞争优势。

## 3. 当前状态问题

### 3.1 `AppController` 职责过宽

[app_controller.dart](../lib/core/app_controller.dart) 同时管理：

- 账户与登录态
- 设置
- API 客户端及其缓存
- 数据库与网盘缓存入口
- 导航与多选状态
- 顶栏、底栏动画进度
- 更新服务和下载路径工具

`AppController` 中约有 35 个设置 setter、42 处 `notifyListeners()`。设置页修改任一
选项时，所有监听整个控制器的 Widget 都可能重建。

### 3.2 通知范围过宽

应用根部的 [app.dart](../lib/app.dart) 直接监听整个 `AppController`。此外多个页面
也直接 `context.watch<AppController>()`，但没有使用 `context.select`。

因此当前最明显的问题不是“Provider 重建失效”，而是：

- 状态粒度太粗。
- 任意状态变化都通知所有监听者。
- 消费者没有声明自己真正依赖的字段。

直接把同样结构搬到 Riverpod，写成宽泛的 `ref.watch(appProvider)`，不会改善这一点。

### 3.3 已有适合保留的高频状态

以下状态已经使用 `ValueNotifier` 和 `ValueListenableBuilder`：

- 顶栏、底栏收起进度
- 当前 Tab
- 网盘目录请求
- 传输任务状态和进度
- 下载标记版本

Riverpod 并不保证在高频进度更新和动画场景下比 `ValueNotifier` 更高效。迁移时不应
为了统一技术栈而机械替换这些实现。

### 3.4 初始化与生命周期具有应用级语义

应用在 `runApp` 前完成 `AppController.init()`，账户、设置、数据库、后台传输和平台
服务都有应用级生命周期。Riverpod 的默认异步 provider 如果需要懒加载，通常会引入
`AsyncValue` 启动门；而 `autoDispose` 还可能错误销毁应用级状态。

因此第一阶段应保留当前“先在 `main` 初始化，再注入”的方式，不要同时改变启动流程。

## 4. 如何理解“Riverpod 是 Provider 的未来”

Riverpod 与 Provider 由同一作者维护。Riverpod 官方把它描述为更现代、推荐的方案，
并明确建议新项目优先考虑 Riverpod。这些说法是合理的架构方向，但不等于 Provider
已经不可用，也不存在本项目必须立即迁移的截止日期。

需要区分以下概念：

- Riverpod 不是 Provider 的“小版本升级”，不能只改 import。
- Riverpod 不是 Provider 的无条件替代品；收益取决于状态建模方式。
- Riverpod 的 `ChangeNotifierProvider` 是兼容迁移工具，不是最终形态。
- Riverpod 代码生成是推荐方向，但不是迁移前置条件。
- Provider 仍然稳定可用；立即迁移的理由应是具体问题，而不是流行趋势。

## 5. 收益与成本

| 能力 | 当前 Provider 状态 | Riverpod 潜在收益 | 本项目实际优先级 |
| --- | --- | --- | --- |
| 依赖注入 | 已满足 | 类型安全、脱离 `BuildContext` | 低 |
| 细粒度重建 | Provider 支持 `select`，当前未使用 | `select`、派生 provider 更自然 | 高 |
| 异步状态 | 手写 checking/loading/error 字段 | `AsyncValue`、自动重试与取消能力 | 中高 |
| 依赖组合 | 当前几乎不需要 | `ref.watch` 组合依赖更简洁 | 中 |
| 页面级缓存销毁 | 主要靠页面生命周期 | `autoDispose`、`family` | 中 |
| 测试覆盖 | 已有 Provider 包装和注入 | `ProviderContainer` 便于纯逻辑测试 | 中 |
| 高频动画/进度 | `ValueNotifier` 已合适 | 无明显优势 | 低 |

### 5.1 粗略工作量

以下是熟悉本项目和 Riverpod 的一名维护者的粗略估计，不包含后续跨平台人工验收：

| 方案 | 粗略工作量 | 主要结果 |
| --- | ---: | --- |
| 根节点兼容 Provider 并替换调用语法 | 2–4 人日 | 生态切换，收益有限 |
| 单个功能试点，例如更新服务 | 1–2 人日 | 验证 Riverpod 是否真正简化代码 |
| 完整状态拆分与 Riverpod 化 | 1–3 周 | 依赖关系和重建边界明显改善 |
| 仅为减少重建而优化现有 Provider | 1–3 人日 | 当前投入产出比最高 |

实际时间会受 Riverpod 熟悉程度、设备测试能力和迁移期间功能并行开发影响。

## 6. 推荐迁移顺序

### 阶段 0：建立基线与迁移边界

目标：确保任何阶段都可以停止或回退。

工作内容：

- 记录 `flutter analyze`、完整测试和 Android/Windows 启动基线。
- 保留当前 `main()` 初始化和 `runApp()` 结构。
- 确定 Riverpod 只用于新试点功能，Provider 继续服务其余页面。
- 为测试增加统一的 Riverpod/Provider 包装辅助函数，先在试点测试中使用。
- 建立任务分支和可回退提交，不把依赖升级、状态重构和 UI 迁移混在同一提交。

完成标准：

- 不改变用户行为。
- 两个状态库可以在同一 Widget 树中共存。
- 试点功能可以随时撤回，不影响现有 Provider 页面。

### 阶段 1：迁移 `UpdateService` 试点

目标：用一个边界清楚、异步特征明显的功能验证 Riverpod。

选择 [update_service.dart](../lib/core/update/update_service.dart) 的原因：

- 当前独立继承 `ChangeNotifier`。
- 有 checking、success、failure、缓存有效期和一次性提示等状态。
- [update_page.dart](../lib/ui/update_page.dart) 已经使用独立监听，影响面可控。
- 适合验证 `AsyncValue`、`ref.listen`、测试覆盖和自动更新之间是否真正简化代码。

迁移要求：

- 先把更新状态整理为明确的数据模型，再选择 `Notifier` 或 `AsyncNotifier`。
- 保留对更新通道、缓存有效期、自动检查和“每个版本只提醒一次”的既有语义。
- 启动时仍按现有方式初始化，不新增阻塞启动的 provider。
- 不在本阶段改动登录、传输、数据库或主题状态。

完成标准：

- 更新页、自动提醒和测试行为保持不变。
- 状态代码比 `ChangeNotifier + 手写布尔字段` 更小或更清晰。
- 测试可以通过 provider override 注入假数据，不需要真实网络。
- 如果收益主要只是语法变化，则停止后续全量迁移。

> **实施进度（2026-10-30）**：阶段 1 代码试点已落地。`UpdateService` 现在是
> `Notifier<UpdateState>`，更新状态、失效判断和一次性提醒均已收拢到不可变
> 状态模型；更新页、全局提醒和「我的」副标题已改为消费 Riverpod。网络与时钟
> 通过 provider override 注入，测试不再使用静态调试字段。当前仍只完成增量
> 自动化验证，阶段 2 及全量迁移尚未启动。
>
> **人工验收（2026-10-30）**：
>
> - Android：`NOH AN00` / Android 12 / arm64，debug 包。更新页、手动检测、
>   测试版与正式版切换、关闭自动检查后不自动重检、进程重启后的缓存与设置恢复
>   均正常。
> - Windows：Windows 10 Enterprise x64，本轮 Release 构建。更新页、手动检测、
>   通道切换、自动检查开关、关闭重开后的状态恢复均正常。
> - 两端应用日志均无本次更新流程新增异常。当前已是最新版本，无法在线上自然触发
>   “发现新版本”全局提醒；该路径由 Widget 测试覆盖。
>
> **阶段 3 设备复验（2026-10-30）**：
>
> - Android debug 覆盖安装保留数据；首页/网盘/我的切换、长按多选、返回退出
>   多选、更新页与自动检查开关均正常。
> - Windows Release 重新构建运行；侧栏切换与转场、更新页和自动检查开关均正常。
> - 两端测试后均恢复为测试版通道、自动检查开启；日志未发现本次导航/设置拆分
>   相关异常。
>
> **阶段 3 设置拆分后全量复验（2026-10-30）**：
>
> - `agent.cmd analyze` 全量无问题；`agent.cmd test` 全量 679 个测试通过。
> - Android debug 覆盖安装保留数据；启动、导航、更新开关、传输与并发设置、
>   下载目录页面均正常。
> - Windows Release 重新构建运行；导航、传输与连接设置、下载目录入口和更新
>   开关均正常。
> - 两端本轮运行日志未出现导航或设置所有权拆分相关异常。

### 阶段 2：迁移叶子依赖和无状态服务

目标：先建立 provider 图的最底层。

建议顺序：

1. `AppDb`
2. `LanzouClient` 的创建入口和客户端注册表
3. 路径、日志、通知等无状态或应用级服务
4. `SettingsStore`、`AccountStore` 背后的持久化接口

这一阶段的重点是明确依赖，不追求一次性消除 `AppController`。数据库和平台服务应以
普通 `Provider` 暴露，避免把可变 store 本身误当成可监听状态。

完成标准：

- 每个底层依赖只有一个 provider 定义。
- 测试只覆盖必要的接口或实现，不依赖真实数据库和平台插件。
- provider 之间没有循环依赖。

> **实施进度（2026-10-30）**：已建立 `appDbProvider`，返回既有
> `AppDb.instance`；应用入口用 `AppController.db` 覆盖同一实例，确保双栈期间
> 仍只有一份数据库连接。客户端缓存也已收拢到 `LanzouClientRegistry` 并通过
> `lanzouClientRegistryProvider` 暴露；`AppController` 保留原公开方法，内部
> 改为使用同一注册表。运行日志已通过 `appLogProvider` 暴露，更新服务的失败
> 记录改从 provider 读取；初始化仍保持在容器创建前。通知服务已通过
> `notificationServiceProvider` 注入 `TransferManager`，进度与完成提醒不再直接
> 读取单例。Android 公共 Downloads 能力已抽成 `SharedDownloadsGateway`，并由
> `AppController` 与 `TransferManager` 构造注入；其余桌面目录和持久化接口尚未
> 迁移。`SettingsStore` 与 `AccountStore` 已通过普通 Provider 暴露入口，
> `UpdateService` 的专用设置 provider 已移除并统一读取 `settingsStoreProvider`。
> 默认下载目录的平台分支也已收拢到 `DownloadPathService` 并通过构造注入接入
> `AppController`；SAF 中转与目录设置状态仍留在现有控制器。

### 阶段 3：拆分可监听状态

目标：把 `AppController` 的全量通知拆成有明确所有者的状态。

建议拆成：

- `SettingsState`：主题、语言、导航显示、传输并发等设置。
- `AccountState`：账户列表、当前 UID、登录态变更。
- `NavigationState`：当前 Tab、多选、返回请求等。
- `DriveState`：目录位置、缓存和请求状态。
- `TransferState`：任务集合、筛选、选择和批量操作。

迁移建议：

- 优先使用不可变状态或小而稳定的状态对象。
- 从 `ChangeNotifierProvider` 的兼容迁移开始也可以，但必须标记为过渡形态。
- 对派生值使用 provider，而不是在 UI 中反复计算，例如：
  `activeUid → activeAccount → activeClient → accountDriveCache`。
- 不在新 provider 和旧 `AppController` 中同时维护同一字段。迁移期间必须只有一个
  状态所有者，另一侧只允许转发或读取。

完成标准：

- 设置修改不会触发账户、导航或传输监听者重建。
- 切换账号只会刷新账户相关依赖。
- `AppController.notifyListeners()` 数量显著下降。
- 所有写操作都有单一入口。

> **实施进度（2026-10-30）**：阶段 3 已从 `NavigationState` 的安全子集开始。
> 多选、网盘/「我的」返回处理器和 `driveCanHandleBack` 已移到独立状态对象，
> 并通过 `navigationStateProvider` 暴露同一实例。`AppController` 仅保留兼容
> getter/setter 与通知转发。当前 Tab、顶/底栏进度和 Ticker 动画也已移入该状态，
> 仍使用 `ValueNotifier`，没有把高频帧更新改成不可变大对象。设置和账户状态尚未
> 迁移。
>
> `DriveState` 首片也已落地：目录请求、当前位置、网盘/收藏可见性探针迁入独立
> 状态对象，并通过 `driveStateProvider` 暴露；`DriveLocation` 保持旧导入兼容。
> `DriveCache` 随后也移入 `DriveState`，由 `driveCacheProvider` 派生暴露；旧
> `AppController.driveCache` 只转发同一实例。账号切换、恢复和清理顺序未改变。
>
> `AccountState` 首片已落地：唯一持有现有 `AccountStore`，`accountStoreProvider`
> 从该状态派生，`AppController.accounts` 只转发同一 store。账号持久化格式、
> 当前 UID 与登录信息字段仍由 `AccountStore` 负责，没有复制状态。
>
> `SettingsState` 所有权首片已落地：唯一持有现有 `SettingsStore`，
> `settingsStoreProvider` 从该状态派生，旧 `AppController.settings` 只转发。
> 35 个设置 setter、默认值和持久化键尚未拆分，后续按设置组逐步迁移。
>
> 第一个设置子组 `UpdateSettingsState` 已拆分：更新通道与自动检查开关通过
> 独立 provider 读写同一个 `SettingsStore`。旧 `AppController` setter 保持原通知
> 语义（通道同值不通知），没有复制持久化字段。
>
> `NotificationSettingsState` 随后拆分：进度通知与完成通知开关通过独立 provider
> 读写同一 store。旧 `AppController` 两个 setter 保持原通知行为，UI 尚未迁移。
>
> `NavigationAppearanceSettingsState` 也已拆分：侧滑切换、顶/底栏隐藏、悬浮导航、
> 转场和导航项显示开关收窄为独立边界。关闭隐藏顶/底栏时立即展开的副作用已在
> 阶段 4 迁入该状态，RootShell UI 本身尚未迁移。
>
> `ThemeSettingsState` 随后拆分：主题模式/种子、OLED、动态取色和全局动画通过
> 独立 provider 读写同一 store。`setMotionMode` 的 `SystemMotion` 同步已在阶段 4
> 迁入该状态，应用根主题和 UI 消费端尚未迁移。
>
> `TransferConnectionSettingsState` 随后拆分：请求间隔、并发数、API 域名、UA 和
> 上传路径收窄为独立入口。阶段 4 已把设置到 `LanzouClient` 的静态运行时同步
> 迁入该状态，旧控制器仅保留兼容通知。
>
> `ListHomeSettingsState` 也已拆分：列表排序、首页折叠、最近使用上限和文件夹
> 打开模式使用独立 provider。最近使用上限写入后的按账号数据库裁剪已在阶段 4
> 迁入该状态。
>
> `LanguageClipboardSettingsState` 已拆分：界面语言与复制分享链接提示收窄为独立
> 入口。应用根 Locale 读取仍在旧外壳，但阶段 4 已通过 revision 转发保证即时
> 刷新。
>
> `CachePageSettingsState` 也已拆分：网格视图、启动页、目录缓存和自动加载开关
> 使用独立 provider。关闭目录缓存时清空 `DriveCache` 的副作用已收拢到该状态，
> 旧控制器只转发同一实例，不再重复清缓存。
>
> `DownloadDirectorySettingsState` 最后拆分：普通下载目录与 SAF URI/标签通过
> 独立入口读写。阶段 4 已把旧 SAF 授权释放和互斥写入顺序迁入该状态，平台目录
> 选择保留在设置叶子。

### 阶段 4：迁移 UI 消费端

目标：按页面逐个迁移，而不是全局查找替换。

推荐顺序：

1. 更新页和更新提醒
2. 设置页中边界清楚的叶子控件
3. 首页和“我的”页
4. 收藏页、分享页
5. 网盘页
6. 传输页和应用外壳

每次迁移一个页面时：

- 将页面改为 `ConsumerWidget` 或 `ConsumerStatefulWidget`。
- build 中使用 `ref.watch`，事件回调和 `initState` 后使用 `ref.read`。
- 用 `select` 或派生 provider 限制重建范围。
- 保留现有动画、返回手势、`KeepAlive` 和响应式布局行为。
- 同步修改该页面的测试包装，不批量修改全部测试。

完成标准：

- 页面不再依赖整个 `AppController`。
- provider 依赖关系可以从页面代码直接读出。
- Provider 和 Riverpod 暂时共存时，两边都能获得同一份权威状态。

> **实施进度（2026-10-30）**：阶段 4 从更新页开始。`UpdateContent` 已完全改为
> Riverpod 消费：更新状态、通道和自动检查均来自 provider，设置写入通过
> `UpdateSettingsState.revision` 局部刷新，不再读取 `AppController`。共享
> `TopBarOverlayScaffold` 仍依赖旧 Provider，留到应用外壳迁移阶段处理。
>
> 设置页的第一个叶子控件“复制分享链接后提示”已抽成
> `ClipboardLinkPromptTile`，使用 `LanguageClipboardSettingsState.revision`
> 局部刷新并有独立 Widget 测试。设置页外层仍整体监听 `AppController`，后续按
> 设置组逐个移除外层依赖。
>
> 进度通知和完成通知两个开关随后迁入 `NotificationSettingsTile`。开关状态由
> `NotificationSettingsState.revision` 局部刷新，系统通知权限申请可注入，结果
> 同步回“管理权限”入口。设置页外层依赖仍未移除。
>
> “目录缓存”和“自动加载全部页面”两行也已迁入 `CachePageSettingsTile`，通过
> `CachePageSettingsState.revision` 局部刷新。设置页现有 Riverpod 叶子共用阶段 0
> 的 `appTestTree` 测试包装器；只更新涉及本页的测试，没有批量迁移其它 Provider
> 测试。设置页外层依赖仍未移除。
>
> “悬浮导航”“滑动切页”“转场动画”随后迁入
> `NavigationAppearanceSettingsTile`。`NavigationAppearanceSettingsState.revision`
> 由旧 `AppController` 监听并转发，因此直属 Riverpod 写入仍会刷新尚未迁移的外壳；
> 控制器不复制字段或写入状态。设置页外层依赖仍未移除。
>
> “主题模式”和“纯黑深色”随后迁入 `ThemeSettingsTile`，通过
> `ThemeSettingsState.revision` 局部刷新。旧控制器监听该 revision 并转发通知，
> 使根 `MaterialApp` 在应用外壳尚未迁移时继续即时响应主题变化。
>
> “主题色”随后迁入 `ThemeColorSettingsTile`。原内联弹窗整理为
> `showThemeColorPicker`，返回类型化的动态取色或 seed 选择；动态取色支持探测仍由
> 设置页负责，写入统一经过 `ThemeSettingsState`。
>
> “语言”随后迁入 `LanguageSettingsTile`。`showLanguagePicker` 返回
> `String?`，写入统一经过 `LanguageClipboardSettingsState`；旧控制器监听该状态
> revision 并转发通知，使根 `MaterialApp.locale` 在应用外壳迁移前仍会立即更新。
>
> “默认启动页”和“首页目录打开方式”随后迁入
> `page_behavior_settings_tile.dart`。两个弹窗均返回 `String?`，设置分别写入
> `CachePageSettingsState` 与 `ListHomeSettingsState`；这两项只影响后续导航行为，
> 本轮不需要新增旧控制器通知桥。
>
> “全局动画”随后迁入 `MotionSettingsTile`。`showMotionModePicker` 返回
> `String?`；`ThemeSettingsState.setMotionMode` 统一负责持久化和
> `SystemMotion.motionMode` 同步，旧控制器不再保留第二份副作用。
>
> “底栏显示项”随后迁入 `NavBarItemsSettingsTile`。
> `showNavBarItemsPicker` 返回类型化的传输/收藏草稿；取消不写入，确认后通过
> `NavigationAppearanceSettingsState.setNavItems` 一次提交并只递增一次 revision。
>
> 设置页滑杆随后抽成公共 `SettingsSliderTile`，保留拖动中只更新本地、松手才
> 落盘与现有无障碍语义。“上传并发数”和“下载并发数”迁入
> `TransferConcurrencySettingsTile`；传输调度继续实时读取同一个 `SettingsStore`，
> 高级连接参数仍由旧控制器同步 `LanzouClient`。
>
> “最近使用条数”随后迁入 `RecentLimitSettingsTile`。
> `ListHomeSettingsState.setRecentLimit` 通过注入的当前账号与
> `AppDb.trimRecents` 统一执行落盘、数据库裁剪和 revision 通知；旧控制器只监听
> 转发，不再重复裁剪。
>
> “网络请求间隔”随后迁入 `RequestIntervalSettingsTile`。
> `TransferConnectionSettingsState.setRequestInterval` 统一持久化并同步
> `LanzouClient.requestInterval`；旧控制器只保留兼容通知。
>
> API 域名、上传路径和自定义 User-Agent 随后迁入
> `AdvancedConnectionSettingsTile`。选择/文本弹窗返回类型化结果，对应 setter
> 统一同步 `LanzouClient.apiBase`、`uploadPath` 和 `userAgent`；旧控制器仅保留
> 兼容通知。
>
> “隐藏顶栏”和“隐藏底栏”随后复用 `NavigationAppearanceSettingsTile`。
> `NavigationAppearanceSettingsState` 注入 `NavigationState` 和少动效判断，关闭
> 隐藏时会先执行原有栏位展开动画，再通过 revision 通知旧控制器。
>
> “下载目录”随后迁入 `DownloadDirectorySettingsTile`。该组件通过
> `DownloadPathService` 解析默认路径，并负责平台目录选择；普通路径与 SAF 字段的
> 互斥写入、旧授权释放统一由 `DownloadDirectorySettingsState` 完成。选择器支持
> 测试注入，旧控制器仅监听 revision 转发通知。
>
> 设置页外层 `context.watch<AppController>()` 随后移除。页面主体改用
> `context.read` 生成搜索元数据并处理事件，迁移后的设置行各自订阅局部状态；
> “显示 Cookie”行使用 `context.select`，只在当前 UID 变化时重建。
>
> `ProfilePage` 主体随后也移除 `context.watch<AppController>()`，仅用
> `context.select` 订阅 `hideTopBar`。账号卡片拆成局部
> `ProfileAccountTile`，只订阅登录态、UID、昵称和会员等级；其他账号操作仍通过
> `context.read` 在事件回调中执行。
>
> `RootShell` 随后移除对 `AppController` 和 `TransferManager` 的整体 `watch`。
> 外壳改为订阅只含 ready、UID、导航项、滑动、浮动和隐藏栏的配置快照；
> `TransferManager` 只订阅运行中任务数，避免普通通知或传输历史变化重建整个
> PageView。
>
> 应用根 `LanCloudApp` 随后改为 `ConsumerStatefulWidget`，直接订阅
> `ThemeSettingsState` 和 `LanguageClipboardSettingsState` 的 revision。
> `AppController.reloadFromStorage()` 在备份恢复后显式调用两个状态的 `refresh()`，
> 保持主题与语言恢复行为。
>
> `common.dart` 的共享顶栏与多选操作栏随后改为局部订阅：
> `TopBarOverlay` / `TopBarOverlayScaffold` 只订阅 `hideTopBar`，
> `BatchActionBar` 只订阅 `floatingNavBar`；滚动进度继续使用
> `ValueListenable`，不再因其他 `AppController` 通知重建。
>
> `DropHoverBanner` 随后把 `driveVisible` / `favoritesVisible` 收窄为双布尔
> `context.select`；拖拽通道和当前目录仍分别由 ValueNotifier 实时驱动。
>
> 恢复页随后把整体 `AppController` 订阅收窄为 `hideTopBar` 单个布尔；
> `BackupService` 仍在初始化时通过 `context.read` 注入，恢复向导状态保持页面本地。
>
> 首页随后移除 `AppController` / `TransferManager` 整体 `watch`，只订阅
> `hideTopBar` 和运行中任务数。快速访问、最近使用、删除动画和折叠状态继续由
> 页面本地状态及 `AppDb.revision` 驱动。
>
> 网盘页最后移除整体 `AppController` 订阅，只订阅网格视图、浮动导航与顶/底栏
> 隐藏配置。目录加载、`DriveLocation`、多选、批量下载/删除和缓存状态保持原有
> 状态机。至此生产代码中的 `context.watch<AppController>()` 已清零；剩余
> `TransferManager` 整体订阅留到阶段 5。
>
> **阶段 4 全量与人工复验（2026-10-30）**：
>
> - `agent.cmd analyze` 全量 0 issue；`agent.cmd test` 全量 707 个测试通过。
> - Android：`NOH AN00` / Android 12 / arm64，debug 覆盖安装保留数据；首页、
>   「我的」、设置页、缓存/自动加载开关、深浅主题、并发/请求间隔和 Android
>   下载目录提示正常；进程日志无本轮相关异常。
> - Windows：Windows 10 x64 Release 重新构建运行；导航、设置页、启动页弹窗、
>   主题切换、传输并发和下载目录弹窗正常；运行日志无本轮相关异常。

### 阶段 5：处理 `TransferManager`

目标：在账户、设置和客户端 provider 稳定后，再迁移最复杂的后台状态。

[transfer_manager.dart](../lib/core/transfer/transfer_manager.dart) 包含：

- 持久化任务恢复
- 上传和下载队列
- 进度通知
- Android/iOS 前台服务
- 任务取消、重试和完成回调
- 与账户、下载目录、数据库和 API 客户端的多项依赖

迁移建议：

- 最后迁移业务状态，不要在第一阶段直接改它。
- 保持传输 manager 为应用级、非 `autoDispose` 的单例生命周期。
- 高频进度继续使用 `ValueNotifier`、节流或独立进度通道，不必把每次进度变化都变成
  大型状态对象复制。
- 先消除 `TransferManager` 对完整 `AppController` 的依赖，改为依赖账户、客户端和
  下载路径能力接口，避免 provider 循环。

完成标准：

- 应用启动后任务恢复顺序不变。
- 前后台切换、取消、重试、批量删除和通知栏进度行为不变。
- 传输状态不会因页面销毁或 `autoDispose` 丢失。

> **实施进度（2026-10-30）**：阶段 5 首个依赖边界切片已落地。
> `TransferManager` 不再导入或持有完整 `AppController`，改为依赖
> `TransferAppAdapter`；该接口只暴露数据库、当前账号、账号存储、设置、客户端
> 与下载路径能力。迁移期由 `AppController` 直接实现，因此现有构造调用与运行行为
> 不变，后续可逐项替换为独立 provider。
>
> 随后继续拆出 `TransferStore` 持久化端口，封装任务恢复、保存、删除和下载标记；
> `AppDbTransferStore` 适配既有 `AppDb`。`TransferManager` 已不再直接持有
> `AppDb`，并新增使用假存储端口恢复任务的测试。
>
> 账号与客户端能力随后拆为 `TransferAccountPort`：当前 UID、账号存在性、
> 按 UID 创建客户端和公开客户端统一由 `AppTransferAccountPort` 包装既有
> `AccountStore + LanzouClientRegistry`。`TransferManager` 不再直接接触账号存储。
>
> 下载目标与路径能力随后拆为 `TransferDownloadPort`，封装目标模式、SAF URI、
> SAF 中转路径和唯一保存路径。迁移期用 `CallbackTransferDownloadPort` 委托既有
> `AppController` 方法，实际下载与平台写入逻辑未改。
>
> 最后拆出 `TransferSettingsPort`，并通过 `TransferDependencies` 组合存储、账号、
> 下载和设置四个端口。`TransferAppAdapter` 已删除；`AppController` 只实现
> `TransferDependenciesProvider` 提供依赖集合，现有 `TransferManager(app)` 构造
> 调用仍保持兼容。
>
> 应用入口随后通过 `transferDependenciesProvider` 注入同一依赖集合，并由
> `transferManagerProvider` 创建应用级 `TransferManager`。Provider 不使用
> `autoDispose`，容器负责释放；旧页面在迁移期仍通过 Provider 获得同一实例。
>
> 传输页随后迁为 `ConsumerStatefulWidget`：事件回调通过
> `ref.read(transferManagerProvider)` 取得管理器，构建时通过
> `ref.watch(transferManagerProvider)` 取得同一实例，再用
> `ListenableBuilder` 订阅 `ChangeNotifier`。这样没有把普通 `Provider` 误当成
> 会响应 `notifyListeners()` 的响应式状态，也保留了任务进度与状态变化的既有
> 刷新路径。列表与条目改为显式接收管理器，不再各自从旧 Provider 读取。
> 四个直接挂载传输页的测试文件已改用 `ProviderScope` 覆盖同一管理器实例，
> 不再依赖 `ChangeNotifierProvider<TransferManager>`。
>
> `RootShell` 随后迁为 `ConsumerStatefulWidget`，上传入口、返回退出确认和
> 运行中任务检查均改从 `transferManagerProvider` 读取。普通 Riverpod
> `Provider` 不会转发 `ChangeNotifier` 的通知，因此运行中任务角标使用一个
> 局部计数桥监听管理器，仅当运行中 / 排队任务数变化时才重建外壳（与迁移前
> `select` 的重建范围一致）；进度通知仍被过滤。新增测试验证任务取消后角标自动
> 消失。由于子页面尚未迁移完成，测试同时保留旧 Provider，确保迁移期两边仍指向
> 同一管理器实例。
>
> “已下载”标记随后迁为从 `ProviderScope` 读取 `transferManagerProvider`。
> 组件仍只监听低频 `marksRevision`，不会因下载进度变化重建设长列表；没有
> `ProviderScope` 的独立预览 / 组件测试继续静默不显示。网盘、收藏与分享列表
> 的三个直接验证测试已通过 Riverpod override 注入同一管理器。
>
> 已下载任务的二级菜单随后改为从当前 `ProviderScope` 读取管理器，菜单关闭条件
> 与任务操作保持不变。分享文件属性弹窗同时迁为 `ConsumerStatefulWidget`，
> 下载状态、进度环和菜单入口均使用 Riverpod 中的同一管理器实例。
>
> `DrivePage` 随后迁为 `ConsumerStatefulWidget`，页面在 `initState` 中通过
> `ref.read(transferManagerProvider)` 获取管理器并注册 / 注销任务监听。该切片
> 只迁移生命周期所有权；上传、批量下载、属性卡和已下载菜单回调仍在后续切片。
>
> 随后清理了 `DrivePage` 内剩余的管理器读取：普通上传、文档提供器上传、批量
> 下载、自有文件下载统一复用生命周期中保存的同一管理器；文件属性卡迁为
> `ConsumerStatefulWidget`，下载标记和进度环从 provider 读取。四个直接测试宿主
> 已移除旧 `ChangeNotifierProvider<TransferManager>`，只保留 `ProviderScope`
> override，防止迁移遗漏被双栈测试掩盖。
>
> 分享文件夹页的条目菜单随后改为通过当前 `ProviderScope` 读取下载标记，
> “已加入下载”时仍会禁用菜单下载项。分页和顶栏测试宿主已改用 Riverpod
> override，现有菜单与失效文件用例继续覆盖实际路径。
>
> 共享的 `downloadShareFile` 单文件下载入口随后迁入 Riverpod，首页、分享文件
> 属性弹窗和分享文件夹菜单继续共用同一套解析、补密码与入队逻辑。批量分享下载
> 尚未迁移；密码恢复测试的宿主已切换为 Riverpod override。
>
> 随后 `downloadShareFiles` 批量分享下载入口也迁入 Riverpod，进度弹窗、逐项
> 失败计数和最终提示保持不变。至此 `common.dart` 不再直接读取旧
> `TransferManager`。
>
> 拖放上传入口随后迁入 Riverpod；未登录跳过、链接导入和混合内容处理顺序保持
> 不变。此时生产代码只剩首页运行中任务数的旧 `context.select`。
>
> 最后把 `RootShell` 内的运行中任务计数过滤桥抽成共享
> `TransferRunningCount`，首页也改用该组件。相同任务数下的进度/
> `notifyListeners()` 更新会被过滤，只有运行中 / 排队任务数变化才重建。
> 新增测试同时验证数量变化会重建、重复通知但数量不变不会重建。至此生产代码
> 已无旧 Provider 的 `TransferManager` 读取或整体订阅。
>
> **阶段 5 全量自动化复验（2026-10-30）**：`agent.cmd analyze` 全量 0 issue；
> `agent.cmd test` 全量 715 个测试全部通过。Android/Windows 的后台传输、
> 取消、重试、批量删除和通知栏进度仍需在移除旧 Provider 前人工复验。
>
> 随后从 `main.dart` 移除了旧 `ChangeNotifierProvider<TransferManager>`；
> 启动时仍主动读取一次 `transferManagerProvider`，保持任务恢复和后台服务启动
> 顺序不变。生产代码和启动装配都只从 Riverpod 获取传输管理器。
>
> **Windows 间歇风险（2026-10-30）**：传输页滚动与文件拖放释放曾在 Windows
> 触发 Flutter 原生语义树崩溃，调用栈分别落在
> `AXNodeData::GetStringAttribute` 和 `FlutterPlatformNodeDelegate::ChildAtIndex`。
> 根因与 [flutter#190357](https://github.com/flutter/flutter/issues/190357) 的
> OverlayPortal 孤儿语义节点问题一致；修复 PR #193372 尚未进入当前稳定的
> Flutter 3.47.9。重新构建的便携包以及 GitHub Release 的
> `26.1.0-pre.19` 均未能再次复现拖放崩溃，因此该项降级为上游间歇风险并继续
> 回归观察，不再作为阶段 6 的硬阻塞。
>
> 最后两个仍注册旧传输 Provider 的测试宿主（分享文件属性弹窗、应用外壳）也已
> 切换为 `ProviderScope` override。至此生产代码、启动装配和测试宿主都不再注册
> `ChangeNotifierProvider<TransferManager>`。
>
> **阶段 6 准入审计（2026-10-30）**：
>
> - 已完成：传输管理器只由 Riverpod 创建和读取；`ProviderScope` 非
>   `autoDispose`，启动时主动预热；高频进度继续使用现有通知通道。
> - 未满足：生产代码仍有 19 个文件导入 `provider`，含 119 处
>   `context.read<AppController>` 和 11 处 `context.select<AppController>`；
>   `main.dart` 仍注册 `ChangeNotifierProvider<AppController>`。
> - 未满足：测试仍有 32 个文件、55 处 AppController Provider 注册。
> - 观察项：Windows 传输页滚动和拖放曾触发 Flutter 上游 UIA 语义树崩溃；
>   最新便携包与 `26.1.0-pre.19` 正式 Release 均未复现，但稳定版 3.47.9
>   仍不包含修复 PR #193372，继续保留回归观察。
> - 自动化盲区：项目仍无 `integration_test` 和 golden test；715 个测试主要覆盖
>   Dart/Widget 层，无法发现上述 Windows 原生 UIA 崩溃。
>
> 结论：阶段 5 已完成；阶段 6 不直接进入。先按模块拆分迁移
> `AppController` 的 Provider 消费面，并等待包含 #193372 的 Flutter 版本完成
> Windows 回归观察。iOS 明确不在当前产品适配与验收范围内，不作为迁移门禁。
>
> **阶段 6 准备授权（2026-10-30）**：允许建立并执行 `AppController` 消费端的
> 逐页迁移计划，从登录、协议、关于页等叶子页面开始。准备阶段仍保留 `provider`
> 依赖、`main.dart` 的 AppController 注入和现有状态所有权；不删除依赖，不把
> 阶段 6 标记为完成。每个切片必须独立保持 `analyze` 0 issue、`agent.cmd test`
> 通过。Windows 上游 UIA 问题继续回归观察；iOS 不纳入当前迁移门禁。
>
> **阶段 6 准备进度（2026-10-30）**：首个切片建立 `AccountLogin`，统一 Cookie
> 格式校验、远端验证、账号资料落盘、客户端缓存和网盘缓存切换。`AccountState`
> 增加账号变化通知，`AppController` 仅转发该通知；旧
> `addAccountFromCookie` 方法保留兼容签名并委托同一服务。登录页 UI 尚未切换，
> 当前只完成可注入业务边界与两条服务测试。
>
> 登录页随后完成消费端切换：Cookie 登录弹窗通过 `accountLoginProvider` 提交，
> 恢复流程通过 `accountStateProvider` 读取当前账号。`LoginPage` 本身已不再
> 导入或读取 `AppController`。由于恢复流程仍会进入尚未迁移的 `RestorePage`，
> 登录页测试宿主在 `ProviderScope` 外暂时保留 AppController Provider。
>
> 共享顶栏随后迁移：`TopBarOverlayScaffold` 从
> `navigationAppearanceSettingsStateProvider` 读取 `hideTopBar`，并通过
> revision 局部刷新；`TopBarOverlay` 在页面未传进度时从
> `navigationStateProvider` 读取外壳顶栏进度。两者在没有应用级 Riverpod
> 覆盖的旧测试宿主中才回退 AppController，并新增一条无 AppController Provider
> 的 Riverpod-only 回归测试。
>
> 随后清理首批叶子页测试：关于页测试只注入
> `navigationAppearanceSettingsStateProvider` 和 `navigationStateProvider`；
> 协议、首启条款和 `AgreementGate` 测试使用空 `ProviderScope`，不再构造
> AppController。
>
> 共享顶栏相关测试随后完成 Riverpod 宿主编排：顶栏点按回顶、安全区布局和
> 顶栏显隐测试均显式覆盖导航外观与导航状态，不再注册
> `ChangeNotifierProvider<AppController>`；测试探针也直接读写
> `NavigationState`。生产组件对尚未迁移页面的 AppController 回退仍保留，
> 待这些页面完成消费端迁移后再删除。
>
> “备份选项”页与解锁弹窗的测试随后也改为直接构造
> `SettingsStore + NavigationState + NavigationAppearanceSettingsState`，
> 不再通过 AppController 提供顶栏依赖。
>
> 分享文件夹页随后迁入 Riverpod 消费端：公开客户端改从
> `lanzouClientRegistryProvider` 读取，收藏写入改从 `appDbProvider` 读取，
> “自动加载全部页面”改从 `cachePageSettingsStateProvider` 读取；文件和文件夹
> 提取码弹窗也使用同一客户端注册表。共享 `BatchActionBar` 改为优先订阅
> `NavigationAppearanceSettingsState.revision`，仅对尚未迁移的旧测试宿主保留
> AppController 回退。分页、密码恢复、空状态与多选条相关增量 53 个测试文件 /
> 299 个测试通过，并新增 1 条 Riverpod 外观 revision 回归测试。
>
> “显示 Cookie”设置行随后改为直接监听 `AccountState`，只随当前账号变化
> 局部刷新；其他 `AppController` 通知不会再触发该行重建。
>
> 分享文件属性弹窗自己的直链解析随后迁入
> `lanzouClientRegistryProvider`；收藏查询和共享下载入口仍在旧控制器上，
> 留到下一片统一迁移。
>
> WebView 登录页随后也改为通过 `accountLoginProvider` 保存捕获到的 Cookie；
> 页面不再读取 `AppController`。该页缺少可直接自动化的 WebView Widget 测试，
> 因此本轮改跑完整测试套件，719 个测试全部通过。
>
> `common.dart` 的共享收藏与分享下载入口随后统一迁入 Riverpod：
> `isFavoritedByRef` / `toggleFavoriteByRef` 读取 `appDbProvider`，
> `downloadShareFile` / `downloadShareFiles` 读取
> `lanzouClientRegistryProvider` 与 `transferManagerProvider`。分享文件属性
> 弹窗及单文件下载测试宿主已可在不注册 `ChangeNotifierProvider<AppController>`
> 的情况下运行。相关增量 52 个测试文件 / 302 个测试通过。
>
> “打开分享链接”弹窗随后迁入 Riverpod：公开分享客户端来自
> `lanzouClientRegistryProvider`，最近使用与收藏写入来自 `appDbProvider`，
> 当前 UID 来自 `AccountState.store`。弹窗本身的解析、补密码、最近记录、
> 收藏模式和成功后的导航顺序保持不变；相关增量 2 个测试文件 / 20 个测试通过。
>
> 备份恢复消费端开始迁移前，先建立应用级 `backupServiceProvider`。应用入口
> 仍通过 `BackupService.of(app)` 取得既有单例并同时用于启动自动备份和容器
> 覆盖，不改变服务内部依赖与生命周期。新增 1 个 provider 覆盖 / 同一性测试，
> 当前测试总数为 720。
>
> 随后 `BackupContent` 与 `RestorePage` 完成消费端迁移：两者从
> `backupServiceProvider` 获取同一服务实例，恢复页的 `hideTopBar` 也改为
> `NavigationAppearanceSettingsState.revision` 局部刷新。备份页、恢复页和
> “我的”大屏备份窗格测试均通过 provider override 注入假服务；相关增量
> 5 + 2 个测试文件、54 + 13 个测试通过。`BackupService` 内部仍暂时持有
> `AppController`，留到后续生命周期拆分时处理。
>
> 传输页随后完成消费端迁移：多选退出回调与选择模式来自
> `navigationStateProvider`，顶栏收起开关来自
> `NavigationAppearanceSettingsState.revision`，滚动进度使用同一
> `NavigationState.topBarHide`。四个直接测试宿主已移除旧
> `ChangeNotifierProvider<AppController>`，增量 4 个测试文件 / 23 个测试通过。
>
> 设置页随后完成生产消费端迁移：搜索元数据来自 `settingsStoreProvider`，
> 清缓存使用 `driveCacheProvider`，清数据使用 `accountStateProvider` 与
> `appDbProvider`；`_Entry` 的构建回调同时去掉未使用的 AppController 参数。
> 相关增量 8 个测试文件 / 46 个测试通过。
>
> ProfilePage 随后完成账号会话迁移：新增应用级 `AccountSession`，统一账号
> 切换、移除、使用数据清理、客户端移除和网盘缓存重绑；AppController 原公开
> 方法只委托同一实例。页面上的切换 / 移除 / 账号卡片分别改用
> `accountSessionProvider` 与 `AccountState`，ProfilePage 不再读取
> AppController，`settings_search_test` 也移除了最后一个旧 Provider 宿主。
> 账号摘要后台刷新改为通知 `AccountState`，避免只刷新旧 Provider 消费者。
> 相关增量 63 个测试文件 / 359 个测试通过；当前测试总数为 722。
>
> 拖放动作随后完成迁移：`DropHoverBanner` 从 `DriveState` 读取可见性与当前
> 目录，文件上传从 `AccountState + LanzouClientRegistry + DriveState` 组合
> 客户端，批量收藏从客户端注册表和 `appDbProvider` 获取依赖。拖放测试不再
> 注册旧 `AppController` Provider；增量 1 个测试文件 / 12 个测试通过。
>
> “显示 Cookie”设置行随后移除旧 Provider 回退，成为纯
> `ConsumerWidget + AccountState` 组件；相应测试不再依赖 AppController。
>
> 共享 `TopBarOverlay` / `TopBarOverlayScaffold` / `BatchActionBar` 随后删除
> AppController 回退分支，只接受应用级
> `navigationAppearanceSettingsStateProvider` 与 `navigationStateProvider`。
> 对应测试宿主随组件迁移补齐 override，不再依赖双栈兼容路径；相关增量
> 54 个测试文件 / 302 个测试通过。
>
> 收藏页随后完成消费端迁移：数据库、导航与多选、收藏探针、公开客户端和当前
> UID 分别来自 `appDbProvider`、`navigationStateProvider`、
> `driveStateProvider`、`lanzouClientRegistryProvider` 与
> `accountStateProvider`。页面不再读取 AppController；收藏、空状态和密码恢复
> 测试移除旧宿主，相关增量 3 个测试文件 / 11 个测试通过。
>
> 首页随后完成迁移：`NavigationState` 接管现有切页回调（AppController 保留
> 兼容转发），HomePage 的数据库、当前目录、客户端、首页展开设置、顶栏和
> 传输运行数分别来自既有 provider。首页不再读取 AppController；相关增量
> 65 个测试文件 / 366 个测试通过。
>
> DrivePage 开始按功能切片迁移。首个切片处理目录加载、缓存、导航、返回能力、
> 动画开关、排序切换和首页目录请求，依赖来自账号、数据库、客户端、目录、
> 页面设置与导航 provider；文件操作、上传下载和属性菜单仍暂用旧控制器。
> 相关增量 5 个测试文件 / 45 个测试通过。
>
> DrivePage 单条目菜单切片随后完成：复制链接、二维码、修改信息、访问密码、
> 移动、收藏和单条删除统一复用已有的 `AccountState`、`appDbProvider`、
> `DriveState` 与客户端注册表，不再读取旧 `AppController`；属性卡入口和元数据
> 刷新同步迁移，属性卡内部加载、批量操作、下载直链和页面外壳留到后续切片。
> 页面内旧 `AppController.read` 由 41 处降至 20 处。新增一条
> “旧控制器客户端为空时，Riverpod 客户端仍可完成复制、修改和删除”的回归测试；
> 相关增量 5 个测试文件 / 46 个测试通过，当前总数为 723。
>
> DrivePage 属性卡与直链切片随后完成：文件 / 文件夹属性卡内部加载、
> 收藏态与快速访问查询、自有文件下载、公开直链解析和直链复制统一从
> `AccountState`、`appDbProvider`、`lanzouClientRegistryProvider` 与
> `transferManagerProvider` 读取。`_FolderInfoSheet` 改为
> `ConsumerStatefulWidget`；测试在旧 `AppController.client` 为空的条件下覆盖
> 文件属性、文件夹属性、下载解析和直链复制。页面内旧 `AppController.read`
> 由 20 处降至 11 处。相关增量 5 个测试文件 / 46 个测试通过，当前总数保持 723。
>
> DrivePage 批量操作切片随后完成：批量删除、下载、复制链接、收藏、移动、
> 修改简介和访问密码统一从 `_activeClient()`、`AccountState`、
> `appDbProvider`、客户端注册表及传输管理器读取。新增“旧控制器客户端为空时
> 批量复制和删除仍可用”的回归测试；页面内旧 `AppController.read` 由 11 处降至
> 4 处。相关增量 5 个测试文件 / 47 个测试通过，当前总数为 724。剩余旧读取仅为
> 初始化兼容、新建目录和页面外壳，另有一个设置快照 select。
>
> DrivePage 页面外壳切片随后完成：设置快照改由 `CachePageSettingsState` 与
> `NavigationAppearanceSettingsState` 的 revision 驱动，目录位置、栏位滚动、
> 多选退出回调和下载键分别来自 `DriveState`、`NavigationState` 与
> `AccountState`；新建目录也改走 `_activeClient()`。`_app` 字段及其兼容读取
> 全部删除，DrivePage 不再导入 `AppController` 或 `provider`。四个本页测试
> 宿主移除旧 `ChangeNotifierProvider<AppController>`。页面内旧读取与 select
> 均清零；全仓 `AppController.read` 降至 11 处、select 降至 1 处，生产
> `provider` 导入只剩 `app.dart` 与 `main.dart`。相关增量 5 个测试文件 /
> 47 个测试通过，当前总数保持 724。
>
> 阶段 6 收尾随后完成。`AppRuntimeState` 接管应用 ready、凭据重认证提示和系统
> 少动效信号，`AppController` 只转发同一实例并通过 provider 覆盖暴露。
> `RootShell` 改用 `AppRuntimeState`、`AccountState`、`NavigationState`、导航
> 外观/缓存/剪贴板设置与客户端注册表；本地快照桥仅在外壳相关字段变化时重建。
> `app.dart`、`main.dart` 和最后 3 个测试包装移除旧 AppController Provider。
> 随后确认 `lib` 与 `test` 无 `package:provider/provider.dart` 导入，并删除
> `pubspec.yaml` / `pubspec.lock` 中的 `provider` 依赖。
>
> 自动化验证结果：`AppRuntimeState` 切片 64 个测试文件 / 363 个测试通过；
> 外壳与依赖移除后 70 个测试文件 / 382 个测试通过。新增 2 条运行时状态测试，
> 当前总数为 726。阶段 6 的代码与依赖迁移已完成，但 Android / Windows 的启动、
> 返回手势、后台传输和备份恢复人工验收尚未执行，因此仍不宣告阶段 6 最终完成。
>
> **阶段 6 完成（2026-10-31）**：全量 `analyze` 为 0 issue，全量测试
> 726 个全部通过。Android debug 包已在 `NOH AN00`（Android 12 / arm64）
> 和 x86_64 Android 17 模拟器安装；Windows Release 构建成功。用户完成人工
> 测试后确认未发现问题。至此 `provider` 依赖、旧 Provider 注册和
> `AppController` Provider 消费面全部移除，阶段 6 完成。
>
> **AppController 退役进度**：首个切片已移除 `BackupService` 对
> `AppController` 的直接依赖。新增 `BackupDependencies` 窄接口，统一暴露账号、
> 设置、数据库与恢复后重载；`AppController` 在迁移期实现该接口，现有调用方
> 和启动顺序不变。新增 1 条接口兼容测试，增量 66 个测试文件 / 373 个测试通过，
> 当前总数为 727。下一步是把 `main.dart` 与测试改为直接构造 `BackupDependencies`
> 实现，再从 `AppController` 移除该兼容实现。
>
> 随后新增 `BackupStoreDependencies`，生产入口直接用账号、设置、数据库和
> `reloadFromStorage` 回调组装备份依赖；备份服务和启动自动备份均不再走
> `AppController` 的接口实现。新增 1 条适配器转发测试，增量 1 个测试文件 /
> 3 个测试通过，当前总数为 728。剩余工作是把测试夹具改为同一适配器，再从
> `AppController` 删除 `BackupDependencies` 接口与 `@override` 兼容成员。
>
> 备份测试夹具已分两批迁移完成：备份脚本/分项/provider/登录页，以及备份页/
> “我的”/恢复进度测试都改用 `BackupStoreDependencies` 构造服务。全仓已无
> `BackupService(AppController)` 或 `super.app` 用法，仅保留一条
> “AppController 满足 BackupDependencies”的临时兼容断言，供最终删除接口时移除。
>
> AppController 的备份兼容实现已删除：`AppController` 不再实现
> `BackupDependencies`，`BackupService` 的构造参数与内部字段统一命名为
> `dependencies`，恢复弹窗也读取该窄依赖。临时兼容断言同步删除。增量
> 66 个测试文件 / 373 个测试通过，用例总数由 728 调整为 727（删除的是兼容断言）。
> 至此备份链路不再依赖完整 `AppController`。
>
> AppController 退役继续推进到下载边界：新增 `DefaultTransferDownloadPort`，
> 把目标模式、固定目录、SAF 中转、过期临时文件清理和唯一保存路径从控制器移入
> 生产端口。`AppController` 暂时保留同名兼容方法，但内部只转发到该端口。
> 新增 1 条唯一保存路径冲突测试，增量 64 个测试文件 / 365 个测试通过，
> 当前总数为 728。下一步应直接在入口组装 `TransferDependencies`，再删除
> `TransferDependenciesProvider` 兼容实现。
>
> 随后生产入口改为直接组装 `TransferDependencies`：传输存储、账号/客户端、
> 下载端口和设置端口分别由已初始化的数据库、账号、设置及平台能力构造，
> `transferManagerProvider` 不再读取 `AppController.transferDependencies`。
> 存储、账号、设置和平台服务均沿用启动时的同一对象，任务恢复顺序不变。
> `AppController` 的兼容 getter 暂时保留，因为现有传输测试仍通过
> `TransferManager(app)` 使用该适配面；需先分批迁移测试夹具，再删除完整
> 控制器依赖。增量分析 1 个文件无问题，目标测试文件 7 个测试通过，用例总数
> 保持 728。

### 阶段 6：移除旧 Provider

只有在以下条件全部满足后才执行：

- 生产代码没有 `package:provider/provider.dart`。
- 测试包装只保留 `ProviderScope`。
- 不再依赖 Riverpod 的 `ChangeNotifierProvider` 兼容层，或已明确决定长期保留的少数
  对象。
- Android、Windows 的启动、返回手势、后台传输和备份恢复均完成人工验收。
  iOS 当前无适配计划，不纳入迁移门禁。

完成后删除 `provider` 依赖和兼容测试辅助函数，避免长期双栈。

## 7. 目标 provider 结构建议

下面是目标方向，不是要求一次性按此顺序实现：

```text
appEnvironmentProvider
├── appDbProvider
├── settingsRepositoryProvider
├── accountRepositoryProvider
├── clientRegistryProvider
└── pathServiceProvider

settingsStateProvider
accountStateProvider
navigationStateProvider
driveStateProvider
transferStateProvider
updateStateProvider

activeUidProvider        = accountStateProvider.select(...)
activeAccountProvider    = accountStateProvider.select(...)
activeClientProvider     = Provider(ref.watch(clientRegistryProvider) ...)
accountDriveCacheProvider = Provider(ref.watch(activeUidProvider) ...)
```

约束：

- UI 不直接把数据库、网络客户端或平台插件当成自身状态。
- 应用级状态不使用 `autoDispose`。
- 页面局部的搜索、筛选和分页可以优先采用 `autoDispose`/`family`。
- “派生状态”不保存第二份可写数据。
- 不创建覆盖整个应用的万能 `ref` 或长期桥接层来假装迁移完成。

## 8. 实施提示

### 8.1 允许双栈，但限制双栈范围

Riverpod 与 Provider 可以同时工作。双栈期应使用 import alias 减少 API 混淆，并为
需要同时使用两者的 Widget 和测试提供统一包装。

双栈只是过渡状态，必须为每个阶段设置退出条件，避免永久维护两套状态系统。

### 8.2 先处理状态所有权，再处理库

每次迁移前先回答：

- 谁拥有这个状态？
- 谁可以修改它？
- 哪些消费者真正依赖它？
- 状态何时创建和销毁？
- 是否需要在应用重启后恢复？

如果这些问题没有答案，即使换成 Riverpod，也只会得到另一种形式的全局可变状态。

### 8.3 先迁移叶子

先迁移不依赖其他可变状态的服务，再迁移派生值，最后迁移 UI。不要从最大的
`AppController` 开始，也不要在迁移初期同时改造初始化、导航和后台任务。

### 8.4 保留高频 ValueNotifier

滚动进度、动画进度、下载百分比等高频状态继续使用当前机制，直到性能测试证明
Riverpod 更合适。Riverpod 的优势是依赖组合与状态生命周期，不是让每个高频帧都生成
新的不可变大对象。

### 8.5 测试改造应跟随功能迁移

不要先批量重写 39 个 Provider 测试文件。每迁移一个页面或状态，再更新对应测试，并把
重复包装抽成共享 helper。

建议同时保留：

- 纯逻辑的 `ProviderContainer` 测试。
- Widget 的 `ProviderScope` 测试。
- 现有完整回归测试。

### 8.6 代码生成可以延后

`riverpod_generator` 和 `riverpod_lint` 能改善新 provider 的一致性，但不应与首次
迁移同时引入。先确认状态 API 和迁移方式，再决定是否加入 codegen 和 `build_runner`。

## 9. 风险清单

| 风险 | 影响 | 缓解方式 |
| --- | --- | --- |
| 只机械替换语法 | 付出成本但无法减少重建或复杂度 | 试点必须同时改善状态建模 |
| Provider/Riverpod 双写同一状态 | 数据漂移、顺序错误 | 明确单一状态所有者 |
| `autoDispose` 误用于应用状态 | 后台任务、登录态或缓存丢失 | 应用级 provider 默认保持存活 |
| 高频进度进入大对象状态 | 额外复制和重建 | 保留 `ValueNotifier` 或拆分进度 provider |
| 初始化流程同时改造 | 启动竞态、登录页和恢复流程回归 | 第一阶段保留 `init()` 流程 |
| provider 循环依赖 | 状态创建顺序不稳定 | 先拆接口和叶子依赖 |
| 测试包装迁移过快 | 大量无关测试同时失败 | 随功能逐步迁移并抽 helper |
| 兼容层长期不退出 | 两套心智模型并存 | 每阶段定义退出条件 |
| 只验证 Widget 测试 | Android/Windows 生命周期问题遗漏 | 增加真机、桌面和后台传输验收 |

## 10. 验收与决策门槛

### 试点结束后继续迁移的条件

- 更新状态代码明显更简洁，而不只是换了 API 名字。
- 自动更新、错误提示、缓存和一次性提醒行为不变。
- 测试更容易注入或断言，至少不增加明显复杂度。
- 没有新增启动竞态或平台生命周期问题。
- 团队可以清楚解释 provider 的依赖和销毁规则。

如果以上条件不能同时成立，建议停止全量迁移，保留 Riverpod 作为新功能备选方案，并
优先优化现有 Provider 状态结构。

### 最终迁移验收项

- `flutter analyze` 无问题。
- 完整 `flutter test` 通过。
- Android 冷启动、登录、分享链接解析和返回手势正常。
- Windows 启动、拖放、下载目录和窗口布局正常。
- Android/iOS 后台上传下载、通知栏进度和任务恢复正常。
- 设置修改不会重建无关页面。
- 账号切换只刷新相关账户、客户端和缓存依赖。
- 所有 app 生命周期 manager 只有一个实例。
- 不再存在 Provider/Riverpod 双写。

## 11. 参考资料

评估时参考了以下官方资料：

- [Riverpod for Provider Users: Quickstart](https://riverpod.dev/docs/from_provider/quickstart)
- [Provider vs Riverpod](https://riverpod.dev/docs/from_provider/provider_vs_riverpod)
- [Migration from ChangeNotifier](https://riverpod.dev/docs/migration/from_change_notifier)
- [Riverpod testing](https://riverpod.dev/docs/how_to/testing)

版本信息具有时效性。正式执行迁移时，应重新确认 `flutter_riverpod` 与 Flutter/Dart
约束，并重新执行本报告的基线命令。
