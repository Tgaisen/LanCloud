# LanCloud（蓝云）

蓝奏云第三方 Flutter 客户端，使用 DeepSeek + Codex 辅助开发与验证。

- 不收集个人信息，账号与数据只保存在本机
- 运行时直连蓝奏云官方接口，没有中间服务器

## 功能

- **MD 3 设计**：动态取色、自适应布局、悬浮底栏
- **网盘管理**：上传、下载、分享、新建文件夹、修改信息、移动、删除、搜索、排序
- **分享链接**：支持打开蓝奏云分享链接
- **多账号**：多账号支持
- **便利功能**：收藏 / 快速访问 / 最近使用
- **传输中心**：上传、下载任务管理，支持多选批量操作
- **备份与恢复**：本地备份 + WebDAV 自动备份
- **Android 系统集成**：可接收其他应用分享的链接 / 文件；适配 Android 12 启动屏与预测性返回手势
- **Windows 桌面端**：可把文件从资源管理器拖进窗口上传；导出走系统「另存为」对话框

## 平台

- [x] Android
- [x] Windows
- [ ] HarmonyOS NEXT
- [ ] iOS / iPadOS / MacOS（无相关设备，暂无计划）
- [ ] 其余平台暂无计划

## 构建

### Android

```powershell
flutter pub get
flutter build apk --release --split-per-abi
```

### Windows

前置条件（缺一不可）：

| 组件 | 说明 |
| --- | --- |
| Visual Studio（生成工具即可） | 勾选「使用 C++ 的桌面开发」工作负载（含 Windows SDK 与 CMake），并额外勾选 **「C++ ATL for x64/x86 (最新 MSVC)」**：`flutter_secure_storage` / `flutter_local_notifications` 的 Windows 实现需要 ATL 头文件 |
| 开发者模式 | 设置 → 系统 → 开发者选项 → 开发人员模式：Flutter 构建插件时需要创建符号链接 |
| NuGet CLI | 在 PATH 中：`flutter_inappwebview` 的 Windows 构建用它拉 WebView2 SDK |

```powershell
powershell -ExecutionPolicy Bypass -File tools/build_windows.ps1
```

脚本会先检查前置条件，再跑格式检查 / 静态分析 / 单元测试，然后构建
`build\windows\x64\runner\Release`，把整包复制到 `outputs\`（默认再打一个 zip）。
只要构建不跑检查加 `-SkipTests`，不打包 zip 加 `-SkipZip`。

发布形式是**绿色便携版**：`outputs\LanCloud-<版本>-windows-x64\`（或同名 zip）。
zip 里带一层同名目录，解压出来就是一个完整文件夹，直接跑 `lancloud.exe`；
已内置 VC++ 运行时可再分发副本（`msvcp140.dll` 等），没装过 Visual Studio 的机器也能用。

> 运行需要 WebView2 运行时（Windows 11 自带；Windows 10 需装 Evergreen Runtime）——
> 缺它应用能启动，但网页登录 / 分享浏览这类内嵌网页打不开。

#### Windows 与 Android 的差异

- **后台传输**：桌面端窗口即进程，没有前台服务（Android 用前台服务 + 常驻通知保活）
- **通知**：只保留「传输完成 / 失败」提醒，不做常驻进度通知（Windows toast 无此形态）
- **分享**：桌面端没有系统分享面板，文本走剪贴板、文件用资源管理器定位
- **保存 / 导出**：走系统「另存为」对话框，导出 Cookie 退化为复制到剪贴板
- **拖拽**：支持从资源管理器拖文件进窗口上传；Windows 平台拿不到拖拽文本，链接请粘贴
- **二维码**：只能选图片识别，没有拍照入口
- **设置**：「通知权限 / 安装应用 / 电池优化 / 默认打开链接」只在 Android 显示
- **窗口**：默认 850×576、最小 425×445（逻辑像素），再小网盘条目等列表行会溢出
- **显示名称**：跟随系统语言，中文「蓝云」/ 英文「LanCloud」（窗口标题、任务栏、任务管理器一致）
- **图标**：exe 图标为圆角方形（与微信 / QQ 同款观感）
- **字体**：中文兜底固定为微软雅黑，避免系统兜底挑到日文字形
- **滚动条**：统一用应用内的快速滑动条（桌面端同样显示，并让开浮层顶栏不被截断）
- **鼠标**：右键网盘条目 / 列表项 = 点该条的 ⋯ 菜单
- **设置**：动态取色只在 Android 显示（Windows 取不到完整色板）

代码风格：`dart format lib test tool`。仓库已配置保存自动格式化（`.vscode/settings.json`），
CI 会强制检查格式、静态分析与测试（`.github/workflows/ci.yml`）。

#### 版本号规范

版本号为 `年份.内容更新序号.热修号[-阶段.序号]`：

| 阶段 | Stage | Seq | 示例 |
| --- | --- | --- | --- |
| 快照 | `snapshot` = 1 | 1–999 | `26.1.0-snapshot.1` |
| 预览 | `pre` = 2 | 1–999 | `26.1.0-pre.1` |
| 候选 | `rc` = 3 | 1–999 | `26.1.0-rc.1` |
| 正式 | 9 | 999 | `26.1.0` |

Android `versionCode` 规则：

```text
versionCode = YY * 10_000_000 + Drop * 100_000 + Hotfix * 10_000 + Stage * 1_000 + Seq
```

```text
26.1.0-snapshot.1 → 260101001     26.1.0-rc.1 → 260103001
26.1.0-pre.1      → 260102001     26.1.0      → 260109999
26.1.1-rc.1       → 260113001     26.1.1      → 260119999
```

#### 签名

本仓库的签名公钥如下，可验证 APK 是否为本仓库产物：

```
70:BD:4A:A8:53:22:FE:26:E6:72:02:FA:C3:17:29:BD:E1:F8:54:FA:1B:D2:FD:52:C8:8F:FC:AA:02:ED:B5:BB
```

## 开源与致谢

本项目使用 DeepSeek + Codex 辅助开发与验证。

本项目以 Apache License 2.0 开源。

此项目的接口协议研究参考了以下开源实现：

- [LanZouCloud-API](https://github.com/zaxtyson/LanZouCloud-API)（MIT）
- [lanzouyun-disk](https://github.com/chenhb23/lanzouyun-disk)（MIT）
- [lanzouplus](https://github.com/nekobyran/lanzouplus)（MIT）

细节见 [docs/PROTOCOL.md](docs/PROTOCOL.md)。

## 免责声明

> 本应用是非官方的第三方客户端，与蓝奏云官方无任何关联，也未获得官方授权。应用按「现状」提供，不提供任何担保；因使用本应用造成的账号受限、数据丢失、上传或下载失败等风险，由使用者自行承担。请勿将其用于商业用途或大规模分发。

## 开发环境

| 组件 | 信息 |
| --- | --- |
| Flutter | `3.47.5` |
| JDK | `17` |
| Android SDK | `platform 37、build-tools、NDK 28.2、CMake` |
| Visual Studio | Build Tools 2026（Windows SDK 10.0.28000）+ 开发者模式 |
