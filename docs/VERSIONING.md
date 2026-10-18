# 版本号规范

版本号为： `年份(YY).内容更新序号(Drop).热修号(Hotfix)[-阶段(Stage).序号(Seq)]`

Android versionCode 规则： `YY * 10_000_000 + Drop * 100_000 + Hotfix * 10_000 + Stage * 1_000 + Seq`

| 阶段 | Stage | Seq | 版本号示例 | versionCode 示例 |
| --- | --- | --- | --- | --- |
| 快照 | `snapshot` = 1 | 1–999 | `26.1.0-snapshot.1` | `260101001` |
| 预览 | `pre` = 2 | 1–999 | `26.1.0-pre.1` | `260102001` |
| 候选 | `rc` = 3 | 1–999 | `26.1.0-rc.1` | `260103001` |
| 正式 | 9 | 999 | `26.1.0` | `260109999` |

**开发构建（装到设备 / 分发测试包）**

- 每次要安装或分发的构建都换一个新版本名：`Seq + 1`（例如 `26.1.0-pre.6`
  → `26.1.0-pre.7`）。versionCode 由公式推出，天然比上一次大，不会出现
  需要降级安装的情况。
- 用脚本一步完成（同时改 `pubspec.yaml` 和 `lib/core/app_info.dart`）：

  ```powershell
  dart run tool/bump_version.dart                 # Seq +1
  dart run tool/bump_version.dart --dry-run       # 只打印结果
  dart run tool/bump_version.dart --set <新版本名>  # 换内容更新序号 / 进入下一阶段
  ```

- 不要再用 `flutter build --build-number` 临时顶高 versionCode：那会绕开
  版本名，把「安装顺序」和「版本号」混在一起。同一版本号重复构建只适合
  本机覆盖调试，不要用来分发。
- 每个阶段有 999 个序号；用满后进入下一阶段（snapshot → pre → rc → 正式版），
  或换下一个内容更新序号。