# LanCloud（蓝云）

蓝奏云第三方客户端（Flutter / Android），个人自用并开源。

- 不收集个人信息，账号与数据只保存在本机
- 运行时直连蓝奏云官方接口，没有中间服务器
- 以 [Apache License 2.0](LICENSE) 开源

> 非官方客户端，与蓝奏云官方无任何关联。使用前请阅读应用内「关于 → 用户协议 / 隐私政策」。

## 功能

### 账号

- 应用内网页登录（自动抓取 Cookie、支持滑块验证）、手动粘贴 Cookie
- 多账号保存与切换、昵称自动解析
- Cookie 存系统加密存储；「显示 Cookie」需先通过生物识别 / 锁屏验证，并支持复制、导出

### 网盘

- 目录分页加载（可切换全部加载）、目录缓存、面包屑路径、列表 / 网格、排序、当前目录内联搜索
- 新建文件夹、上传（多选、队列、进度）、下载（直链解析、已下载标记）
- 批量操作：删除、下载、分享、收藏、改简介、设访问密码（带进度弹窗）
- 文件 / 文件夹属性：简介、分享链接、二维码、访问密码、修改信息
- 快速访问：把常用目录固定到首页
- 分享文件夹浏览：提取码、子目录、多选批量操作

### 首页 / 收藏 / 传输

- 首页：快速访问、最近使用（跟随账号实时刷新）、打开分享链接、我的（账号与设置入口）
- 收藏：独立底栏视图，支持多选删除、编辑标题
- 传输：进行中 / 已结束分组、多选删除、失败项重试、通知栏进度、前台服务后台传输

### 外观与设置

- 深浅色模式、OLED 纯黑、五种主题色、跟随系统语言（中文 / 英文）
- 顶栏 / 底栏滑动收起（与手指 1:1 跟手）、MD3 悬浮底栏、横滑切换视图
- 动画：目录切换、列表错峰出现、增删改局部刷新、顶底栏滑动显隐
- 权限管理：安装应用（打开 APK）、电池优化
- 识别二维码支持「拍照获取 / 从相册选取」，两种方式都不需要相机权限（纯 Dart 解码）
- 备份与恢复：本地 JSON 备份 + WebDAV 自动备份（默认不含 Cookie）
- 设置搜索；高级覆盖项：接口 / 上传 / 分享域名、自定义 UA

## 构建

需要 Flutter（3.35+，本机为 3.47.5）、JDK 17、Android SDK。

```powershell
flutter pub get
flutter build apk --release --split-per-abi
```

产物在 `build/app/outputs/flutter-apk/`：`app-arm64-v8a-release.apk`（推荐，绝大多数手机）、
`app-armeabi-v7a-release.apk`（老旧 32 位机型）、`app-x86_64-release.apk`。
分架构包体积约为通用包的一半，按手机架构选择即可。

### 版本号规范

从第一个正式版开始，版本号采用「年份.内容更新序号.热修号」：`26.1.0` 表示 2026 年第 1 次内容更新，
`26.1.1` 表示对该版本的首次热修，`26.2.0` 表示同年下一次内容更新。

Android 的 `versionCode` 由前两段推导：`YY * 10000 + 内容更新序号 * 100 + 热修号`。

| 版本号 | versionCode |
| --- | --- |
| `26.1.0` | `260100` |
| `26.1.1` | `260101` |
| `26.2.3` | `260203` |

发版时同步更新两处（`test/version_test.dart` 会校验两者一致、且符合上面的公式）：

- `pubspec.yaml` 的 `version:`，如 `26.1.0+260100`（`+` 后面就是 versionCode）
- `lib/core/app_info.dart` 的 `appVersion` / `appBuild`（关于页与备份文件名会用到）

`flutter build apk --split-per-abi` 时 Flutter 会按 ABI 给 versionCode 加偏移（armeabi-v7a +1000、
arm64-v8a +2000、x86_64 +4000），arm64 包实际是 `260100 + 2000 = 262100`；对外描述版本仍用
`26.1.0`。需要 APK 的 versionCode 与公式完全一致时可以加 `-Pforce-version-code-ignoring-abi=true`，
或改用通用包。

当前 `0.8.x` 是正式版之前的过渡版本；首个正式版计划为 `26.1.0+260100`。

### 签名

release 包由 `android/key.properties` 指定的密钥签名，密钥文件为
`android/app/lancloud-release.keystore`（别名 `lancloud`）；两个文件都在 `.gitignore` 里，
**不要提交、不要公开**，请和密码一起另存一份私密备份（密码丢了无法找回，应用也就无法再更新）：

```properties
storePassword=***
keyPassword=***
keyAlias=lancloud
storeFile=lancloud-release.keystore
```

换机器时把这两个文件恢复到原位即可。没有 `key.properties` 时 release 会退回 debug 签名并打印
警告（方便本地和 CI 出包），这种包不能对外发布。发布前可以用
`apksigner verify --print-certs <apk>` 核对签名，当前发布证书的 SHA-256 指纹：

release 包同时写入 v2 + v3 两种签名方案（Android 9+ 走 v3，将来换签名密钥时老用户不必卸载
重装；Android 7/8 走 v2）。`minSdk 24` 起 v1 已无必要，v4 只服务 `adb` 增量安装，都未启用。

```
70:BD:4A:A8:53:22:FE:26:E6:72:02:FA:C3:17:29:BD:E1:F8:54:FA:1B:D2:FD:52:C8:8F:FC:AA:02:ED:B5:BB
```

## 安装

1. 按手机架构选一个 APK 安装（不确定就选 arm64）
2. 遇到提示时允许「安装未知来源应用」
3. 首次启动阅读并同意用户协议与隐私政策，然后登录（推荐应用内网页登录）

早期 `0.8.x` 预览包用的是 debug 签名，换成正式签名后首次安装需要先卸载旧版（本地数据会清空，
建议先在应用内「设置 → 备份与恢复」导出备份）。

## 隐私

- 不收集、不上传任何个人信息；没有统计、广告、崩溃上报 SDK
- 蓝奏云账号（Cookie）、昵称、收藏、最近使用、传输记录与设置只保存在本机
- 运行时直接与蓝奏云官方接口通信（pc.woozooo.com、up.woozooo.com 等）
- 如启用 WebDAV 备份，备份文件只会上传到你填写的服务器，且默认不含 Cookie
- 完整条款见应用内「关于 → 隐私政策」

## 开源与致谢

本项目以 Apache License 2.0 开源，可自行修改与分发（请保留许可与版权声明）。

接口协议参考了以下开源实现（仅作协议研究，未直接复用其代码）：

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

## 本机开发环境

| 组件 | 位置 |
| --- | --- |
| Flutter 3.47.5 | `C:\dev\flutter` |
| JDK 17 | `C:\dev\java17` |
| Android SDK（platform 34/35/36、build-tools、NDK 28.2、CMake） | `C:\dev\android-sdk` |

已配置国内镜像：pub.dev / Flutter 资源（flutter-io.cn）、Gradle 发行包（腾讯云）、Maven（阿里云）。
