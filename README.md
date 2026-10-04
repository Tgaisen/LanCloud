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

## 构建

```powershell
flutter pub get
flutter build apk --release --split-per-abi
```

### 版本号规范

从第一个正式版开始，版本号采用「年份.内容更新序号.热修号」：`26.1.0` 表示 2026 年第 1 次内容更新，
`26.1.1` 表示对该版本的首次热修，`26.2.0` 表示同年下一次内容更新。

Android 的 `versionCode` 由前两段推导：`YY * 10000 + 内容更新序号 * 100 + 热修号`。

| 版本号 | versionCode |
| --- | --- |
| `26.1.0` | `260100` |
| `26.1.1` | `260101` |
| `26.2.3` | `260203` |

### 签名

本仓库 Android 产物的签名公钥信息如下：

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

本应用是非官方的第三方客户端，与蓝奏云官方无任何关联，也未获得官方授权。应用按「现状」
提供，不提供任何担保；因使用本应用造成的账号受限、数据丢失、上传或下载失败等风险，由使用者
自行承担。请勿将其用于商业用途或大规模分发。

## 文档

- 开发路线图：[docs/ROADMAP.md](docs/ROADMAP.md)
- 接口协议笔记：[docs/PROTOCOL.md](docs/PROTOCOL.md)

## 开发环境

| 组件 | 备注 |
| --- | --- |
| Flutter | `3.47.5` |
| JDK | `17` |
| Android SDK | `platform 34/35/36、build-tools、NDK 28.2、CMake` |
