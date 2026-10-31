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
| `tools\agent.cmd test`（ThemeColorSettingsTile） | 增量 | **48 tests, all passed** | 约 16 s |
| `tools\agent.cmd test`（LanguageSettingsTile） | 增量 | **356 tests, all passed** | 约 69 s |
| `tools\agent.cmd test`（页面行为设置叶子） | 增量 | **51 tests, all passed** | 约 14 s |
| `tools\agent.cmd test`（MotionSettingsTile） | 增量 | **364 tests, all passed** | 约 66 s |
| `tools\agent.cmd test`（NavBarItemsSettingsTile） | 增量 | **53 tests, all passed** | 约 15 s |
| `tools\agent.cmd test`（传输并发滑杆） | 增量 | **51 tests, all passed** | 约 14 s |
| `tools\agent.cmd test`（RecentLimitSettingsTile） | 增量 | **357 tests, all passed** | 约 65 s |
| `tools\agent.cmd test`（RequestIntervalSettingsTile） | 增量 | **357 tests, all passed** | 约 65 s |
| `tools\agent.cmd test`（高级连接覆盖项） | 增量 | **360 tests, all passed** | 约 66 s |
| `tools\agent.cmd test`（隐藏顶/底栏） | 增量 | **357 tests, all passed** | 约 60 s |
| `tools\agent.cmd test`（DownloadDirectorySettingsTile） | 增量 | **357 tests, all passed** | 约 68 s |
| `tools\agent.cmd test`（设置页外层监听） | 增量 | **46 tests, all passed** | 约 13 s |
| `tools\agent.cmd test`（ProfilePage 消费端） | 增量 | **29 tests, all passed** | 约 11 s |
| `tools\agent.cmd test`（RootShell 消费端） | 增量 | **32 tests, all passed** | 约 12 s |
| `tools\agent.cmd test`（LanCloudApp 根主题/语言） | 增量 | **377 tests, all passed** | 约 68 s |
| `tools\agent.cmd test`（common 共享顶栏/操作栏） | 增量 | **291 tests, all passed** | 约 61 s |
| `tools\agent.cmd test`（DropHoverBanner） | 增量 | **12 tests, all passed** | 约 5 s |
| `tools\agent.cmd test`（RestorePage 顶栏订阅） | 增量 | **1 test, all passed** | 约 4 s |
| `tools\agent.cmd test`（HomePage 消费端） | 增量 | **6 tests, all passed** | 约 4 s |
| `tools\agent.cmd test`（DrivePage 消费端） | 增量 | **45 tests, all passed** | 约 19 s |
| `tools\agent.cmd test`（TransferAppAdapter） | 增量 | **357 tests, all passed** | 约 64 s |
| `tools\agent.cmd test`（TransferStore） | 增量 | **358 tests, all passed** | 约 65 s |
| `tools\agent.cmd test`（TransferAccountPort） | 增量 | **359 tests, all passed** | 约 62 s |
| `tools\agent.cmd test`（TransferDownloadPort） | 增量 | **360 tests, all passed** | 约 62 s |
| `tools\agent.cmd test`（TransferDependencies） | 增量 | **361 tests, all passed** | 约 64 s |
| `tools\agent.cmd test`（transferManagerProvider） | 增量 | **120 tests, all passed** | 约 26 s |
| `tools\agent.cmd test`（传输页消费端） | 增量 | **23 tests, all passed** | 约 26 s |
| `tools\agent.cmd test`（RootShell 传输订阅） | 增量 | **33 tests, all passed** | 约 21 s |
| `tools\agent.cmd test`（已下载标记消费端） | 增量 | **37 tests, all passed** | 约 26 s |
| `tools\agent.cmd test`（已下载菜单与分享属性弹窗） | 增量 | **13 tests, all passed** | 约 15 s |
| `tools\agent.cmd test`（DrivePage 生命周期监听） | 增量 | **45 tests, all passed** | 约 27 s |
| `tools\agent.cmd test`（DrivePage 传输交互与属性卡） | 增量 | **45 tests, all passed** | 约 27 s |
| `tools\agent.cmd test`（分享文件夹菜单） | 增量 | **19 tests, all passed** | 约 18 s |
| `tools\agent.cmd test`（共享单文件下载入口） | 增量 | **292 tests, all passed** | 约 61 s |
| `tools\agent.cmd test`（共享批量下载入口） | 增量 | **292 tests, all passed** | 约 55 s |
| `tools\agent.cmd test`（拖放上传入口） | 增量 | **12 tests, all passed** | 约 15 s |
| `tools\agent.cmd test`（首页运行任务计数） | 增量 | **40 tests, all passed** | 约 25 s |
| `tools\agent.cmd test`（移除传输旧 Provider 注册） | 全量 | **715 tests, all passed** | 约 108 s |
| `tools\agent.cmd test`（清理最后测试宿主） | 增量 | **17 tests, all passed** | 约 17 s |
| `tools\agent.cmd test`（阶段 5 最终收尾 HEAD） | 全量 | **715 tests, all passed** | 约 111 s |
| `tools\agent.cmd test`（阶段 6 准备首个切片） | 增量 | **366 tests, all passed** | 约 66 s |
| `tools\agent.cmd test`（登录页消费端） | 增量 | **16 tests, all passed** | 约 17 s |
| `tools\agent.cmd test`（共享顶栏消费端） | 增量 | **293 tests, all passed** | 约 75 s |
| `tools\agent.cmd test`（关于 / 协议叶子页测试） | 增量 | **7 tests, all passed** | 约 19 s |
| `tools\agent.cmd analyze`（阶段 4 消费端完成后） | 全量 | No issues found | 约 27 s |
| `tools\agent.cmd test`（阶段 4 消费端完成后） | 全量 | **707 tests, all passed** | 约 113 s |
| `tools\agent.cmd analyze`（阶段 5 消费端完成后） | 全量 | No issues found | 约 31 s |
| `tools\agent.cmd test`（阶段 5 消费端完成后） | 全量 | **715 tests, all passed** | 约 106 s |
| `tools\agent.cmd analyze`（分享文件夹页消费端） | 增量 | No issues found | 约 17 s |
| `tools\agent.cmd test`（分享文件夹页消费端） | 增量 | **299 tests, all passed** | 约 58 s |
| `tools\agent.cmd test`（显示 Cookie 设置行） | 增量 | **1 test, all passed** | 约 15 s |
| `tools\agent.cmd test`（分享文件属性弹窗） | 增量 | **8 tests, all passed** | 约 14 s |
| `tools\agent.cmd test`（WebView 登录消费端） | 全量 | **719 tests, all passed** | 约 110 s |
| `tools\agent.cmd analyze`（阶段 6 准备后续切片） | 全量 | No issues found | 约 18 s |
| `tools\agent.cmd test`（共享收藏 / 分享下载 helper） | 增量 | **302 tests, all passed** | 约 57 s |
| `tools\agent.cmd test`（打开分享链接弹窗） | 增量 | **20 tests, all passed** | 约 17 s |
| `tools\agent.cmd test`（backupServiceProvider） | 增量 | **1 test, all passed** | 约 13 s |
| `tools\agent.cmd test`（备份内容 provider 注入） | 增量 | **54 tests, all passed** | 约 27 s |
| `tools\agent.cmd test`（恢复页 provider 注入） | 增量 | **13 tests, all passed** | 约 18 s |
| `tools\agent.cmd analyze`（备份恢复消费端完成后） | 全量 | No issues found | 约 25 s |
| `tools\agent.cmd test`（备份恢复消费端完成后） | 全量 | **720 tests, all passed** | 约 113 s |
| `tools\agent.cmd test`（传输页导航依赖） | 增量 | **23 tests, all passed** | 约 12 s |
| `tools\agent.cmd test`（设置页搜索与事件依赖） | 增量 | **46 tests, all passed** | 约 25 s |
| `tools\agent.cmd test`（AccountSession 服务） | 增量 | **361 tests, all passed** | 约 53 s |
| `tools\agent.cmd test`（ProfilePage 账号会话消费端） | 增量 | **359 tests, all passed** | 约 52 s |
| `tools\agent.cmd test`（拖放动作依赖） | 增量 | **12 tests, all passed** | 约 15 s |
| `tools\agent.cmd test`（显示 Cookie 纯 Riverpod） | 增量 | **1 test, all passed** | 约 13 s |
| `tools\agent.cmd test`（共享顶栏 / 多选条回退移除） | 增量 | **302 tests, all passed** | 约 49 s |
| `tools\agent.cmd test`（收藏页消费端） | 增量 | **11 tests, all passed** | 约 18 s |
| `tools\agent.cmd test`（首页消费端与切页回调） | 增量 | **366 tests, all passed** | 约 52 s |
| `tools\agent.cmd test`（网盘目录加载与导航切片） | 增量 | **45 tests, all passed** | 约 25 s |
| `tools\agent.cmd analyze`（网盘单条目菜单切片） | 增量 | No issues found | 约 29 s |
| `tools\agent.cmd test`（网盘单条目菜单切片） | 增量 | **46 tests, all passed** | 约 36 s |
| `tools\agent.cmd analyze`（网盘属性卡与直链切片） | 增量 | No issues found | 约 22 s |
| `tools\agent.cmd test`（网盘属性卡与直链切片） | 增量 | **46 tests, all passed** | 约 28 s |
| `tools\agent.cmd analyze`（网盘批量操作切片） | 增量 | No issues found | 约 18 s |
| `tools\agent.cmd test`（网盘批量操作切片） | 增量 | **47 tests, all passed** | 约 27 s |
| `tools\agent.cmd analyze`（网盘页面外壳切片） | 增量 | No issues found | 约 17 s |
| `tools\agent.cmd test`（网盘页面外壳切片） | 增量 | **47 tests, all passed** | 约 27 s |
| `tools\agent.cmd analyze`（AppRuntimeState） | 增量 | No issues found | 约 15 s |
| `tools\agent.cmd test`（AppRuntimeState） | 增量 | **363 tests, all passed** | 约 66 s |
| `tools\agent.cmd analyze`（RootShell 与移除 Provider） | 增量 | No issues found | 约 30 s |
| `tools\agent.cmd test`（RootShell 与移除 Provider） | 增量 | **382 tests, all passed** | 约 74 s |
| `tools\agent.cmd analyze`（BackupDependencies） | 增量 | No issues found | 约 19 s |
| `tools\agent.cmd test`（BackupDependencies） | 增量 | **373 tests, all passed** | 约 72 s |
| `tools\agent.cmd analyze`（BackupStoreDependencies） | 增量 | No issues found | 约 20 s |
| `tools\agent.cmd test`（BackupStoreDependencies） | 增量 | **3 tests, all passed** | 约 14 s |
| `tools\agent.cmd analyze`（备份测试夹具批次 1） | 全量 | No issues found | 约 29 s |
| `tools\agent.cmd test`（备份测试夹具批次 1） | 增量 | **31 tests, all passed** | 约 24 s |
| `tools\agent.cmd analyze`（备份测试夹具批次 2） | 全量 | No issues found | 约 19 s |
| `tools\agent.cmd test`（备份测试夹具批次 2） | 增量 | **72 tests, all passed** | 约 29 s |
| `tools\agent.cmd analyze`（移除 AppController 备份接口） | 增量 | No issues found | 约 19 s |
| `tools\agent.cmd test`（移除 AppController 备份接口） | 增量 | **373 tests, all passed** | 约 68 s |
| `tools\agent.cmd analyze`（DefaultTransferDownloadPort） | 增量 | No issues found | 约 15 s |
| `tools\agent.cmd test`（DefaultTransferDownloadPort） | 增量 | **365 tests, all passed** | 约 59 s |
| `tools\agent.cmd analyze`（入口直接组装传输依赖） | 增量 | No issues found | 约 17 s |
| `tools\agent.cmd test`（入口直接组装传输依赖） | 增量 | **7 tests, all passed** | 约 14 s |
| `tools\agent.cmd analyze`（AppCompositionRoot） | 增量 | No issues found | 约 12 s |
| `tools\agent.cmd test`（AppCompositionRoot） | 增量 | **8 tests, all passed** | 约 13 s |
| `tools\agent.cmd analyze`（传输测试夹具批次 1） | 全量 | No issues found | 约 17 s |
| `tools\agent.cmd test`（传输测试夹具批次 1） | 增量 | **23 tests, all passed** | 约 14 s |
| `tools\agent.cmd analyze`（传输测试夹具批次 2） | 全量 | No issues found | 约 17 s |
| `tools\agent.cmd test`（传输测试夹具批次 2） | 增量 | **2 tests, all passed** | 约 15 s |
| `tools\agent.cmd analyze`（传输测试夹具批次 3） | 全量 | No issues found | 约 17 s |
| `tools\agent.cmd test`（传输测试夹具批次 3） | 增量 | **11 tests, all passed** | 约 16 s |
| `tools\agent.cmd analyze`（网盘测试夹具批次 4） | 全量 | No issues found | 约 17 s |
| `tools\agent.cmd test`（网盘测试夹具批次 4） | 增量 | **10 tests, all passed** | 约 17 s |
| `tools\agent.cmd analyze`（分享文件夹夹具批次 5） | 全量 | No issues found | 约 19 s |
| `tools\agent.cmd test`（分享文件夹夹具批次 5） | 增量 | **16 tests, all passed** | 约 24 s |
| `tools\agent.cmd analyze`（分享密码恢复夹具批次 6） | 全量 | No issues found | 约 20 s |
| `tools\agent.cmd test`（分享密码恢复夹具批次 6） | 增量 | **5 tests, all passed** | 约 20 s |
| `tools\agent.cmd analyze`（外壳夹具批次 7） | 全量 | No issues found | 约 17 s |
| `tools\agent.cmd test`（外壳夹具批次 7） | 增量 | **9 tests, all passed** | 约 20 s |
| `tools\agent.cmd analyze`（属性弹窗夹具批次 8） | 全量 | No issues found | 约 20 s |
| `tools\agent.cmd test`（属性弹窗夹具批次 8） | 增量 | **26 tests, all passed** | 约 29 s |
| `tools\agent.cmd analyze`（分享文件弹窗夹具批次 9） | 全量 | No issues found | 约 17 s |
| `tools\agent.cmd test`（分享文件弹窗夹具批次 9） | 增量 | **8 tests, all passed** | 约 17 s |
| `tools\agent.cmd analyze`（传输选择夹具批次 10） | 全量 | No issues found | 约 21 s |
| `tools\agent.cmd test`（传输选择夹具批次 10） | 增量 | **18 tests, all passed** | 约 26 s |
| `tools\agent.cmd analyze`（移除传输依赖兼容层） | 增量 | No issues found | 约 9 s |
| `tools\agent.cmd test`（移除传输依赖兼容层） | 增量 | **366 tests, all passed** | 约 68 s |
| `tools\agent.cmd analyze`（下载兼容测试迁移） | 全量 | No issues found | 约 32 s |
| `tools\agent.cmd test`（下载兼容测试迁移） | 增量 | **7 tests, all passed** | 约 15 s |
| `tools\agent.cmd analyze`（移除控制器下载兼容层） | 增量 | No issues found | 约 12 s |
| `tools\agent.cmd test`（移除控制器下载兼容层） | 增量 | **359 tests, all passed** | 约 57 s |
| `tools\agent.cmd analyze`（移除更新设置兼容 API） | 增量 | No issues found | 约 7 s |
| `tools\agent.cmd test`（移除更新设置兼容 API） | 增量 | **358 tests, all passed** | 约 53 s |
| `tools\agent.cmd analyze`（移除通知设置兼容 API） | 增量 | No issues found | 约 7 s |
| `tools\agent.cmd test`（移除通知设置兼容 API） | 增量 | **355 tests, all passed** | 约 52 s |
| `tools\agent.cmd analyze`（移除导航外观兼容 API） | 增量 | No issues found | 约 7 s |
| `tools\agent.cmd test`（移除导航外观兼容 API） | 增量 | **351 tests, all passed** | 约 52 s |
| `tools\agent.cmd analyze`（移除列表/首页兼容 API） | 增量 | No issues found | 约 7 s |
| `tools\agent.cmd test`（移除列表/首页兼容 API） | 增量 | **346 tests, all passed** | 约 51 s |
| `tools\agent.cmd analyze`（移除传输连接兼容 API） | 增量 | No issues found | 约 7 s |
| `tools\agent.cmd test`（移除传输连接兼容 API） | 增量 | **342 tests, all passed** | 约 52 s |
| `tools\agent.cmd analyze`（移除主题设置兼容 API） | 增量 | No issues found | 约 7 s |
| `tools\agent.cmd test`（移除主题设置兼容 API） | 增量 | **338 tests, all passed** | 约 54 s |
| `tools\agent.cmd analyze`（移除语言/剪贴板兼容 API） | 增量 | No issues found | 约 7 s |
| `tools\agent.cmd test`（移除语言/剪贴板兼容 API） | 增量 | **335 tests, all passed** | 约 50 s |
| `tools\agent.cmd analyze`（网盘目录切片完成后） | 全量 | No issues found | 约 21 s |
| `tools\agent.cmd test`（网盘目录切片完成后） | 全量 | **722 tests, all passed** | 约 110 s |
| `tools\agent.cmd analyze`（拖放与 Cookie 行完成后） | 全量 | No issues found | 约 17 s |
| `tools\agent.cmd test`（拖放与 Cookie 行完成后） | 全量 | **722 tests, all passed** | 约 99 s |
| `tools\agent.cmd analyze`（账号会话消费端完成后） | 全量 | No issues found | 约 32 s |
| `tools\agent.cmd test`（账号会话消费端完成后） | 全量 | **722 tests, all passed** | 约 99 s |

工具链：Flutter 3.47.7（stable）/ Dart 3.13.5 / DevTools 2.60.0。
静态检查：`analysis_options.yaml` 已开启 `strict-casts` / `strict-inference` / `strict-raw-types`。

## 规模

| 指标 | 数量 |
| --- | ---: |
| `lib` Dart 文件 | 143 |
| `lib` 总行数 | 约 4.4 万 |
| `test` 测试文件 | 161（平铺，`<主题>_test.dart`） |
| `test` 总行数 | 约 2.1 万 |
| `test` 用例数 | 720（当前总数；累计删除旧设置兼容测试） |
| `lib/ui` 页面与组件 | 54 个平铺文件 |
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
- 2026-10-30 的 ThemeColorSettingsTile 把主题色弹窗整理为
  `showThemeColorPicker` 并新增 1 个独立 Widget 测试，覆盖动态取色与 seed 互斥；
  增量 8 个文件 / 48 个测试通过，当前总数由 688 增至 689。
- 2026-10-30 的 LanguageSettingsTile 把语言弹窗整理为 `showLanguagePicker` 并
  新增 1 个独立 Widget 测试，同时把语言状态 revision 转发到旧控制器；增量 63 个
  文件 / 356 个测试通过，当前总数由 689 增至 690。
- 2026-10-30 的页面行为设置新增 2 个独立 Widget 测试，覆盖默认启动页与首页目录
  打开方式；`ListHomeSettingsState` 增加局部 revision，增量 10 个文件 / 51 个测试
  通过，当前总数由 690 增至 692。
- 2026-10-30 的 MotionSettingsTile 新增 1 个独立 Widget 测试，并把
  `SystemMotion.motionMode` 同步收拢到 `ThemeSettingsState`；增量 64 个文件 /
  364 个测试通过，当前总数由 692 增至 693。
- 2026-10-30 的 NavBarItemsSettingsTile 新增 1 个批量写入测试和 1 个独立 Widget
  测试，覆盖取消不写入、确认后一次提交；增量 10 个文件 / 53 个测试通过，当前
  总数由 693 增至 695。
- 2026-10-30 的上传/下载并发滑杆新增 2 个独立 Widget 测试，并把设置滑杆抽成
  公共 `SettingsSliderTile`；增量 10 个文件 / 51 个测试通过，当前总数由 695
  增至 697。
- 2026-10-30 的 RecentLimitSettingsTile 新增 1 个状态裁剪测试和 1 个独立 Widget
  测试，并把 `AppDb.trimRecents` 调用收拢到 `ListHomeSettingsState`；增量 63 个
  文件 / 357 个测试通过，当前总数由 697 增至 699。
- 2026-10-30 的 RequestIntervalSettingsTile 新增 1 个独立 Widget 测试，并把
  `LanzouClient.requestInterval` 同步收拢到 `TransferConnectionSettingsState`；
  增量 63 个文件 / 357 个测试通过，当前总数由 699 增至 700。
- 2026-10-30 的 AdvancedConnectionSettingsTile 新增 3 个独立 Widget 测试，覆盖
  API 域名、上传路径和 User-Agent 保存/恢复默认；对应 `LanzouClient` 静态配置
  同步已收拢到 `TransferConnectionSettingsState`，增量 64 个文件 / 360 个测试
  通过，当前总数由 700 增至 704。
- 2026-10-30 的隐藏顶/底栏复用 `NavigationAppearanceSettingsTile`，新增 1 个
  Riverpod 直属写入的少动效展开测试；增量 62 个文件 / 357 个测试通过，当前总数
  由 704 增至 705。
- 2026-10-30 的 DownloadDirectorySettingsTile 新增 2 个独立 Widget 测试，覆盖
  普通目录选择与恢复默认时释放旧 SAF 授权；状态层新增 revision 并独占互斥写入，
  增量 62 个文件 / 357 个测试通过，当前总数由 705 增至 707。
- 2026-10-30 的设置页移除外层 `context.watch<AppController>()`，新增 1 个
  “显示 Cookie”局部 UID 订阅测试；增量 8 个文件 / 46 个测试通过，当前总数由
  707 增至 708。
- 2026-10-30 的 ProfilePage 移除外层 `context.watch<AppController>()`，账号卡片
  改为局部账号摘要订阅，顶栏隐藏设置使用窄 `context.select`；增量 3 个文件 /
  29 个测试通过，用例总数保持 708。
- 2026-10-30 的 RootShell 移除 `AppController` / `TransferManager` 整体订阅，
  改为外壳配置快照与运行中任务数两个 `context.select`；增量 9 个文件 / 32 个测试
  通过，用例总数保持 708。
- 2026-10-30 的 LanCloudApp 改为直接订阅主题与语言状态 revision，并新增
  `refresh()` 覆盖备份恢复后的设置重载；增量 70 个文件 / 377 个测试通过，用例
  总数保持 708。
- 2026-10-30 的 common 共享顶栏与多选操作栏移除整体 AppController 订阅，改为
  `hideTopBar` / `floatingNavBar` 两个窄 select；增量 51 个文件 / 291 个测试通过，
  用例总数保持 708。
- 2026-10-30 的 DropHoverBanner 将网盘/收藏可见性收窄为双布尔快照；增量 1 个
  文件 / 12 个测试通过，用例总数保持 708。
- 2026-10-30 的 RestorePage 将整体 AppController 订阅收窄为 `hideTopBar` 布尔；
  增量 1 个文件 / 1 个测试通过，用例总数保持 708。
- 2026-10-30 的 HomePage 将整体 AppController / TransferManager 订阅收窄为
  `hideTopBar` 与运行中任务数；增量 2 个文件 / 6 个测试通过，用例总数保持 708。
- 2026-10-30 的 DrivePage 将整体 AppController 订阅收窄为视图设置快照；增量 5
  个文件 / 45 个测试通过，用例总数保持 708。生产代码中的整体 AppController
  watch 已清零。
- 2026-10-30 阶段 4 消费端迁移完成后的全量验证发现：此前按增量结果累计的用例数
  存在 1 条误差；以全量 **707 tests** 为准，相关历史增量的“当前总数”仅反映当时
  的累计记录口径。
- 2026-10-30 的阶段 5 `TransferAppAdapter` 新增 1 个边界测试，增量 63 个文件 /
  357 个测试通过，当前总数由全量 707 增至 708；`TransferManager` 已不再直接
  导入完整 `AppController`。
- 2026-10-30 的阶段 5 `TransferStore` 新增 1 个假存储恢复任务测试，增量 63 个
  文件 / 358 个测试通过，当前总数由 708 增至 709；`TransferManager` 已不再直接
  持有 `AppDb`。
- 2026-10-30 的阶段 5 `TransferAccountPort` 新增 1 个账号/客户端解析测试，增量
  63 个文件 / 359 个测试通过，当前总数由 709 增至 710；`TransferManager` 已不再
  直接接触账号存储或客户端注册表。
- 2026-10-30 的阶段 5 `TransferDownloadPort` 新增 1 个回调委托测试，增量 63 个
  文件 / 360 个测试通过，当前总数由 710 增至 711；`TransferManager` 的下载目标
  与路径解析已通过端口隔离。
- 2026-10-30 的阶段 5 `TransferDependencies` 新增 1 个设置端口测试，增量 63 个
  文件 / 361 个测试通过，当前总数由 711 增至 712；万能适配器已删除，管理器改为
  四个显式端口的依赖集合。
- 2026-10-30 的阶段 5 `transferManagerProvider` 新增 1 个共享实例测试，增量
  16 个文件 / 120 个测试通过，当前总数由 712 增至 713；管理器已由 Riverpod
  容器创建并负责释放。
- 2026-10-30 的传输页消费端迁移通过 `ProviderScope` 注入管理器；增量 4 个测试
  文件 / 23 个测试通过，用例总数保持 713。
- 2026-10-30 的 `RootShell` 传输订阅迁入 Riverpod，并新增任务角标随运行中任务数
  更新的测试；增量 9 个文件 / 33 个测试通过，当前总数由 713 增至 714。
- 2026-10-30 的“已下载”标记迁入 Riverpod；增量 3 个测试文件 / 37 个测试通过，
  用例总数保持 714。
- 2026-10-30 的已下载任务二级菜单与分享文件属性弹窗迁入 Riverpod；增量 2 个
  测试文件 / 13 个测试通过，用例总数保持 714。
- 2026-10-30 的 `DrivePage` 生命周期任务监听迁入 Riverpod；增量 5 个测试文件 /
  45 个测试通过，用例总数保持 714。
- 2026-10-30 的 `DrivePage` 上传、批量下载、自有文件下载和属性卡迁入 Riverpod；
  增量 5 个测试文件 / 45 个测试通过，用例总数保持 714。四个网盘页测试宿主已
  移除旧传输管理器 Provider，只保留 Riverpod override。
- 2026-10-30 的分享文件夹页条目菜单迁入 Riverpod；增量 4 个测试文件 / 19 个测试
  通过，用例总数保持 714。
- 2026-10-30 的共享 `downloadShareFile` 入口迁入 Riverpod；增量 51 个测试文件 /
  292 个测试通过，用例总数保持 714。
- 2026-10-30 的共享 `downloadShareFiles` 批量入口迁入 Riverpod；增量 51 个测试
  文件 / 292 个测试通过，用例总数保持 714；`common.dart` 已无旧传输管理器读取。
- 2026-10-30 的拖放上传入口迁入 Riverpod；增量 1 个测试文件 / 12 个测试通过，
  用例总数保持 714；生产代码只剩首页运行中任务数的旧 `select`。
- 2026-10-30 的共享 `TransferRunningCount` 接入首页并新增过滤重建测试；增量
  12 个文件 / 40 个测试通过，当前总数由 714 增至 715。生产代码已无旧 Provider
  的 `TransferManager` 读取或整体订阅。
- 2026-10-30 阶段 5 消费端完成后全量复验：`agent.cmd analyze` 0 issue；
  `agent.cmd test` 715 个测试全部通过。阶段 5 后台传输与跨平台行为仍需人工复验。
- 2026-10-30 从 `main.dart` 移除旧 `ChangeNotifierProvider<TransferManager>`；
  保留启动时主动创建 Riverpod 管理器。全量 715 个测试通过，用例总数不变。
- 2026-10-30 清理最后两个测试宿主中的旧传输 Provider；增量 2 个测试文件 /
  17 个测试通过，用例总数保持 715。全仓已无
  `ChangeNotifierProvider<TransferManager>`。
- 2026-10-30 阶段 5 最终 HEAD 全量复验：`agent.cmd test` 715 个测试全部通过。
  阶段 6 准入审计确认 AppController 的 Provider 消费面和集成测试盲区仍是
  主要阻塞项。
- 2026-10-30 Windows 间歇风险：Flutter 3.47.x 的 OverlayPortal 孤儿语义节点
  问题曾在传输页滚动和拖放释放时触发原生崩溃（flutter#190357）。重新构建的
  便携包和 `26.1.0-pre.19` 正式 Release 均未复现；修复 PR #193372 仍未进入
  稳定版 3.47.9，后续继续回归观察。iOS 无适配计划，不纳入迁移验收。
- 2026-10-30 阶段 6 准备首个切片新增 `AccountLogin`，覆盖成功登录以及 Cookie
  格式错误 / 验证失败两条用例；增量 65 个测试文件 / 366 个测试通过，当前总数
  由 715 增至 717。登录页 UI 尚未迁移。
- 2026-10-30 登录页消费端迁入 Riverpod；增量 2 个测试文件 / 16 个测试通过，
  用例总数保持 717。`LoginPage` 已无 AppController 读取；其测试宿主仅为尚未
  迁移的 `RestorePage` 保留旧 Provider。
- 2026-10-30 共享顶栏消费端迁入 Riverpod 并保留旧测试回退；增量 51 个测试文件
  / 293 个测试通过，当前总数由 717 增至 718。
- 2026-10-30 关于页和协议 / 首启页测试清理旧 Provider；增量 2 个测试文件 /
  7 个测试通过，用例总数保持 718。
- 2026-10-31 分享文件夹页、提取码弹窗和 `BatchActionBar` 改为 Riverpod 消费；
  `ShareFolderPage` 的公开客户端、收藏数据库和“自动加载全部页面”设置均从
  provider 读取。新增 1 条 `BatchActionBar` Riverpod 外观 revision 测试；增量
  53 个测试文件 / 299 个测试通过，当前总数由 718 增至 719。
- 2026-10-31 “显示 Cookie”设置行改为直接监听 `AccountState`；修改其他设置
  不会刷新该行，账号通知后才局部更新。增量 1 个测试文件 / 1 个测试通过，
  用例总数保持 719。
- 2026-10-31 分享文件属性弹窗的直链解析改从 `lanzouClientRegistryProvider`
  读取；增量 1 个测试文件 / 8 个测试通过，用例总数保持 719。收藏与下载共用
  入口仍暂时依赖旧控制器。
- 2026-10-31 WebView 登录页保存 Cookie 改走 `accountLoginProvider`；该页无直接
  Widget 测试，因此执行全量验证，719 个测试全部通过，用例总数保持 719。
- 2026-10-31 `common.dart` 的收藏查询、收藏切换、单文件下载和批量下载 helper
  统一改从 `appDbProvider`、`lanzouClientRegistryProvider` 与
  `transferManagerProvider` 读取依赖；分享属性弹窗和单文件下载测试已移除直接
  测试宿主中的 `ChangeNotifierProvider<AppController>`。增量 52 个测试文件 /
  302 个测试通过，用例总数保持 719。
- 2026-10-31 “打开分享链接”弹窗改用客户端注册表、`appDbProvider` 与
  `AccountState.store`；生产文件已无 `AppController` 读取。增量 2 个测试文件 /
  20 个测试通过，用例总数保持 719。
- 2026-10-31 新增应用级 `backupServiceProvider`，由 `main.dart` 用现有
  `BackupService.of(app)` 覆盖，自动备份与页面后续消费共用同一实例；新增
  1 个 provider 覆盖 / 同一性测试，当前总数由 719 增至 720。
- 2026-10-31 `BackupContent` 改从 `backupServiceProvider` 获取服务，备份页与
  “我的”大屏右窗格测试通过 override 注入假服务；增量 5 个测试文件 /
  54 个测试通过，用例总数保持 720。
- 2026-10-31 `RestorePage` 的服务与 `hideTopBar` 订阅均迁入 Riverpod，登录页
  测试不再注册旧 `AppController` Provider；增量 2 个测试文件 / 13 个测试通过，
  用例总数保持 720。
- 2026-10-31 `TransfersPage` 的多选回调、`NavigationState` 和顶栏收起进度改从
  Riverpod 读取；4 个直接测试文件不再注册旧 `AppController` Provider。增量
  4 个测试文件 / 23 个测试通过，用例总数保持 720。
- 2026-10-31 `SettingsCategoryPage` 的搜索元数据、清缓存和清数据依赖改从
  `settingsStoreProvider`、`driveCacheProvider`、`accountStateProvider` 与
  `appDbProvider` 读取；生产文件不再引用 `AppController`。增量 8 个测试文件 /
  46 个测试通过，用例总数保持 720。
- 2026-10-31 新增应用级 `AccountSession`，统一账号切换、移除、使用数据清理、
  客户端移除和网盘缓存重绑；`AppController` 兼容方法委托同一实例。新增
  2 条服务测试，当前总数由 720 增至 722。
- 2026-10-31 `ProfilePage` 的账号切换、移除和账号卡片改走
  `accountSessionProvider` / `AccountState`，页面本身不再读取
  `AppController`；`settings_search_test` 最后一个旧 Provider 宿主已移除。
  增量 63 个测试文件 / 359 个测试通过，用例总数保持 722。
- 2026-10-31 `drop_actions.dart` 的悬停提示、文件上传和批量收藏分别改从
  `driveStateProvider`、`accountStateProvider`、客户端注册表和
  `appDbProvider` 读取；拖放测试移除 5 个旧 `AppController` Provider 注册。
  增量 1 个测试文件 / 12 个测试通过，用例总数保持 722。
- 2026-10-31 `ShowCookieSettingsTile` 删除旧 Provider 回退，改为纯
  `ConsumerWidget + AccountState` 监听；增量 1 个测试文件 / 1 个测试通过，
  用例总数保持 722。
- 2026-10-31 移除 `TopBarOverlay` / `TopBarOverlayScaffold` /
  `BatchActionBar` 的 AppController 回退，共享组件现在只接受应用级 Riverpod
  导航状态。相关测试宿主补齐导航 provider override；增量 54 个测试文件 /
  302 个测试通过，用例总数保持 722。
- 2026-10-31 `FavoritesPage` 改用 `AppDb`、`NavigationState`、`DriveState`、
  客户端注册表和账号状态 provider；页面不再读取 `AppController`。收藏页、
  空状态和密码恢复测试移除对应旧 Provider 宿主；增量 3 个测试文件 /
  11 个测试通过，用例总数保持 722。
- 2026-10-31 `NavigationState` 接管切页回调，AppController 保留兼容转发；
  `HomePage` 改用数据库、导航目录、账号客户端、首页设置和传输计数 provider，
  不再读取 `AppController`。增量 65 个测试文件 / 366 个测试通过，用例总数
  保持 722。
- 2026-10-31 `DrivePage` 首个切片迁移目录加载、缓存、导航、返回能力、排序
  动画和首页目录请求，改用账号、数据库、客户端、目录、页面设置和导航 provider；
  文件操作仍暂用旧控制器。增量 5 个测试文件 / 45 个测试通过，用例总数保持
  722。
- 2026-10-31 `DrivePage` 单条目菜单切片将复制链接、二维码、修改信息、访问
  密码、移动、收藏和单条删除改为读取现有账号、数据库、客户端和目录 provider；
  新增“旧控制器客户端不可用时仍能完成复制、修改和删除”的回归测试。增量
  5 个测试文件 / 46 个测试通过，当前总数由 722 增至 723。
- 2026-10-31 `DrivePage` 属性卡与直链切片将文件 / 文件夹属性卡加载、收藏态、
  快速访问查询、自有文件下载和公开直链解析迁入 Riverpod；测试在旧
  `AppController.client` 为空时继续覆盖属性、下载和直链。页面内旧读取由
  20 处降至 11 处；增量 5 个测试文件 / 46 个测试通过，用例总数保持 723。
- 2026-10-31 `DrivePage` 批量操作切片将批量删除、下载、复制链接、收藏、移动、
  修改简介和访问密码迁入 Riverpod；新增“旧控制器客户端为空时批量复制和删除
  仍可用”的回归测试。页面内旧读取由 11 处降至 4 处；增量 5 个测试文件 /
  47 个测试通过，当前总数由 723 增至 724。
- 2026-10-31 `DrivePage` 页面外壳切片把设置快照改为既有状态 revision 驱动，
  目录位置、栏位滚动、多选兼容、下载键和新建目录均迁入 Riverpod/现有状态对象；
  `_app` 与 `provider` 导入已从页面删除。四个本页测试宿主移除旧
  `ChangeNotifierProvider<AppController>`。增量 5 个测试文件 / 47 个测试通过，
  用例总数保持 724；生产 `provider` 导入剩余 `app.dart` 与 `main.dart`。
- 2026-10-31 新增 `AppRuntimeState`，唯一持有 ready、凭据重认证提示和系统少动效
  信号；`AppController` 仅转发同一实例。新增 2 条状态/ provider 覆盖测试，
  增量 64 个测试文件 / 363 个测试通过，当前总数由 724 增至 726。
- 2026-10-31 `RootShell` 完成最终 Riverpod 消费迁移，使用本地快照桥限制重建；
  `app.dart`、`main.dart` 与最后 3 个测试包装移除旧 AppController Provider。
  随后删除 `provider` 依赖并刷新 lockfile。`lib` / `test` 均无旧 Provider 导入；
  增量 70 个测试文件 / 382 个测试通过，用例总数保持 726。Android / Windows
  人工验收仍未执行，阶段 6 不提前标记为全部完成。
- 2026-10-31 全量 `analyze` 0 issue、726 个测试全部通过；Android debug 在
  `NOH AN00` 与 x86_64 Android 17 模拟器安装，Windows Release 构建成功，
  人工测试未发现问题，阶段 6 完成。
- 2026-10-31 AppController 退役首片新增 `BackupDependencies`，备份服务不再直接
  依赖完整控制器；`AppController` 暂时实现该接口以保持调用兼容。新增 1 条
  接口兼容测试，增量 66 个测试文件 / 373 个测试通过，当前总数由 726 增至 727。
- 2026-10-31 新增 `BackupStoreDependencies`，生产入口直接使用既有存储与显式
  重载回调组装备份服务；新增 1 条适配器转发测试，增量 1 个测试文件 /
  3 个测试通过，当前总数由 727 增至 728。测试夹具与 `AppController` 接口移除
  仍待后续切片。
- 2026-10-31 备份测试夹具分两批迁到 `BackupStoreDependencies`：批次 1 覆盖
  备份脚本/分项/provider/登录页，4 个测试文件 31 个测试通过；批次 2 覆盖备份页/
  “我的”/恢复进度，7 个受影响测试文件 72 个测试通过。当前仅剩最终删除
  `AppController` 接口实现的兼容断言。
- 2026-10-31 删除 `AppController` 的 `BackupDependencies` 实现、相关
  `@override` 与临时兼容断言；`BackupService` 字段统一改为 `dependencies`，
  恢复弹窗改用窄依赖读取数据库。增量 66 个测试文件 / 373 个测试通过，
  用例总数由 728 调整为 727。
- 2026-10-31 新增 `DefaultTransferDownloadPort`，将下载目标模式、目录解析、
  SAF 中转、临时文件清理和唯一保存路径从 `AppController` 移入生产端口；
  控制器仅保留兼容转发。新增 1 条路径冲突测试，增量 64 个测试文件 /
  365 个测试通过，当前总数由 727 增至 728。
- 2026-10-31 生产入口直接组装 `TransferDependencies`，复用启动时已初始化的
  数据库、账号、设置、下载目录和共享 Downloads 对象；不再读取
  `AppController.transferDependencies`。`TransferManager(app)` 测试兼容面仍保留，
  待分批迁移夹具后删除。增量分析 1 个文件无问题，目标测试文件 7 个测试通过，
  用例总数保持 728。
- 2026-10-31 新增 `AppCompositionRoot`，集中构造备份服务、四个传输端口和
  Riverpod 容器覆盖；`main()` 仍先执行 `AppController().init()`，通知、自动
  备份、传输恢复和 `runApp()` 的外部顺序不变。新增 1 条“组合根复用应用级状态
  与依赖”测试；增量分析 2 个文件无问题，目标测试文件 8 个测试通过。当前总数
  按 728 条全量基线加 1 条增量记为 729，本片尚未全量复验。
- 2026-10-31 传输测试夹具第一批迁移完成：`download_mark_test`、
  `transfer_retry_test` 与 `transfer_running_count_test` 共 14 处
  `TransferManager(app)` 改为通过 `transfer_dependencies_test.dart` 中的
  `buildTransferManager` 显式构造依赖。相关 4 个测试文件 / 23 个测试通过，
  用例总数保持 729。
- 2026-10-31 传输测试夹具第二批迁移完成：`transfers_animation_test` 与
  `transfers_delete_dialog_test` 的 2 处 `TransferManager(app)` 改用
  `buildTransferManager`。相关 2 个测试文件 / 2 个测试通过，用例总数保持 729。
- 2026-10-31 传输测试夹具第三批迁移完成：`empty_state_layout_test` 与
  `file_icons_test` 的 2 处 `TransferManager(app)` 改用
  `buildTransferManager`，并移除替换后遗留的旧导入。相关 2 个测试文件 /
  11 个测试通过，用例总数保持 729。
- 2026-10-31 网盘测试夹具第四批迁移完成：`drive_multi_select_test` 与
  `drive_paging_test` 的 4 处 `TransferManager(app)` 改用
  `buildTransferManager`。相关 2 个测试文件 / 10 个测试通过，用例总数保持
  729。
- 2026-10-31 分享文件夹测试夹具第五批迁移完成：
  `share_folder_password_test`、`share_folder_top_bar_test` 与
  `share_folder_paging_test` 的 3 处 `TransferManager(app)` 改用
  `buildTransferManager`。相关 3 个测试文件 / 16 个测试通过，用例总数保持
  729。
- 2026-10-31 分享密码恢复夹具第六批迁移完成：
  `share_password_recovery_test` 的 2 处 `TransferManager(app)` 改用
  `buildTransferManager`。该测试文件 5 个测试通过，用例总数保持 729。
- 2026-10-31 外壳测试夹具第七批迁移完成：`shell_inset_test` 的 2 处
  `TransferManager(app)` 改用 `buildTransferManager`。该测试文件 9 个测试
  通过，用例总数保持 729。
- 2026-10-31 属性弹窗测试夹具第八批迁移完成：
  `property_sheet_quick_actions_test` 的 5 处 `TransferManager(app)` 改用
  `buildTransferManager`。该测试文件 26 个测试通过，用例总数保持 729。
- 2026-10-31 分享文件弹窗夹具第九批迁移完成：`share_file_sheet_test` 的
  6 处 `TransferManager(app)` 改用 `buildTransferManager`。该测试文件 8 个
  测试通过，用例总数保持 729。
- 2026-10-31 传输选择夹具第十批迁移完成：`transfers_selection_test` 的
  9 处 `TransferManager(app)` 全部改用 `buildTransferManager`。该测试文件
  18 个测试通过，用例总数保持 729；测试代码中的旧控制器构造入口已清零。
- 2026-10-31 移除传输依赖兼容层：删除 `TransferDependenciesProvider`、
  `TransferManager(TransferDependenciesProvider)` 工厂，以及 `AppController`
  中存储、账号、设置端口和 `TransferDependencies` 聚合。控制器仅保留
  `_transferDownload` 以支持现有 SAF 目录兼容方法与测试。增量分析 3 个生产
  文件无问题，64 个受影响测试文件 / 366 个测试通过，用例总数保持 729。
- 2026-10-31 下载兼容测试迁移完成：目录模式测试改为直接使用
  `DownloadDirectorySettingsState`，默认目录和公共 Downloads 测试改为验证
  `DownloadPathService` / `DefaultTransferDownloadPort`，不再读取
  `AppController` 下载兼容方法。相关 3 个测试文件 / 7 个测试通过，用例总数
  保持 729。
- 2026-10-31 移除 `AppController` 的下载兼容层：删除 `_sharedDownloads`、
  `_downloadPaths`、`_transferDownload` 以及默认目录 / 目标模式 / SAF 中转 /
  唯一路径方法；`main.dart` 与依赖测试改用无参控制器，下载能力继续由
  `DefaultTransferDownloadPort` 提供。增量分析 2 个生产文件无问题，61 个
  受影响测试文件 / 359 个测试通过，用例总数保持 729。
- 2026-10-31 移除更新设置兼容 API：删除
  `AppController.setUpdateChannel` / `setUpdateAutoCheck` 及仅验证旧控制器
  通知行为的测试；`UpdateSettingsState` 自身读写和 provider 覆盖测试保留。
  增量分析 1 个生产文件无问题，61 个受影响测试文件 / 358 个测试通过，
  用例总数由 729 调整为 728。
- 2026-10-31 移除通知设置兼容 API：删除
  `AppController.setNotifyProgress` / `setNotifyDone` 及只验证旧控制器通知
  行为的测试；`NotificationSettingsState` 自身读写和 provider 覆盖测试保留。
  增量分析 1 个生产文件无问题，60 个受影响测试文件 / 355 个测试通过，
  用例总数由 728 调整为 727。
- 2026-10-31 移除导航外观兼容 API：删除控制器上的滑动切页、顶/底栏隐藏、
  悬浮导航、转场动画和底栏显示项共 7 个转发方法，以及 2 条只验证旧控制器
  行为的测试。增量分析 1 个生产文件无问题，59 个受影响测试文件 / 351 个测试
  通过，用例总数由 727 调整为 725。
- 2026-10-31 移除列表/首页兼容 API：删除控制器上的排序、首页折叠、最近使用
  展开/上限和首页目录打开方式共 5 个转发方法及 1 条旧控制器专用测试；
  Cookie 设置行测试改为直接触发 `ListHomeSettingsState`。增量分析 1 个生产
  文件无问题，58 个受影响测试文件 / 346 个测试通过，用例总数由 725 调整为
  724。
- 2026-10-31 移除传输连接兼容 API：删除控制器上的请求间隔、上传/下载并发、
  API 域名、User-Agent 和上传路径共 6 个转发方法及 1 条旧控制器专用测试。
  增量分析 1 个生产文件无问题，57 个受影响测试文件 / 342 个测试通过，
  用例总数由 724 调整为 723。
- 2026-10-31 移除主题设置兼容 API：自动动态取色改走 `ThemeSettingsState`；
  删除控制器上的主题模式、全局动画、OLED、动态取色和主题色共 5 个转发方法，
  以及 2 条只验证旧控制器行为的测试。增量分析 1 个生产文件无问题，56 个
  受影响测试文件 / 338 个测试通过，用例总数由 723 调整为 721。
- 2026-10-31 移除语言/剪贴板兼容 API：删除控制器上的语言和剪贴板提示共
  2 个转发方法及 1 条旧控制器专用测试。增量分析 1 个生产文件无问题，55 个
  受影响测试文件 / 335 个测试通过，用例总数由 721 调整为 720。
- 2026-10-30 人工复验：Android `NOH AN00` / Android 12 / arm64，debug 覆盖安装
  保留数据；首页、我的、设置页、缓存/自动加载开关、深浅主题、并发/请求间隔和
  Android 下载目录提示正常，进程日志无本轮相关异常。Windows 10 x64 Release
  重新构建运行；导航、设置页、启动页弹窗、主题切换、传输并发、下载目录弹窗
  均正常，运行日志无本轮相关异常。
- 若临时再改 `analysis_options.yaml` 加规则，issue 数会变；先把预期数量记在这里再跑，
  避免和「本次改坏」混淆。
