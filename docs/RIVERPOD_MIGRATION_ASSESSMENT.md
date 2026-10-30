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

生产代码中的消费点统计：

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

### 阶段 6：移除旧 Provider

只有在以下条件全部满足后才执行：

- 生产代码没有 `package:provider/provider.dart`。
- 测试包装只保留 `ProviderScope`。
- 不再依赖 Riverpod 的 `ChangeNotifierProvider` 兼容层，或已明确决定长期保留的少数
  对象。
- Android、iOS、Windows 的启动、返回手势、后台传输和备份恢复均完成人工验收。

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
