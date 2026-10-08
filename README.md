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

- [x] **Android** `7+`
- [x] **Windows** `10 1809 17763+`
- [ ] HarmonyOS NEXT
- [ ] iOS / iPadOS / MacOS（无相关设备，暂无计划）
- [ ] 其余平台暂无计划

## 构建

### 版本号规范

版本号为 `年份.内容更新序号.热修号[-阶段.序号]`：

| 阶段 | Stage | Seq | 示例 |
| --- | --- | --- | --- |
| 快照 | `snapshot` = 1 | 1–999 | `26.1.0-snapshot.1` |
| 预览 | `pre` = 2 | 1–999 | `26.1.0-pre.1` |
| 候选 | `rc` = 3 | 1–999 | `26.1.0-rc.1` |
| 正式 | 9 | 999 | `26.1.0` |

### Android

```powershell
flutter pub get
flutter build apk --release --split-per-abi
```

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

### Windows

前置条件见 [开发环境](#开发环境)。

```powershell
powershell -ExecutionPolicy Bypass -File tools/build_windows.ps1
```

> 运行需要 WebView2 运行时，如缺乏，则无法打开网页登录 / 分享浏览等内嵌网页。

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
| Flutter | 3.47.5 |
| JDK | 17 |
| Android SDK | platform 37、build-tools、NDK 28.2、CMake |
| Visual Studio Build Tools | 2026（Windows SDK 10.0.28000）；勾选「使用 C++ 的桌面开发」工作负载（含 Windows SDK 与 CMake），并额外勾选「C++ ATL for x64/x86 (最新 MSVC)」 |
| NuGet CLI | 用于拉取 WebView2 SDK |
