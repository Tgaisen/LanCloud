# 回归基线

> 记录日期：2026-10-30。用途：给人和 AI 代理一个「改之前长什么样」的锚点。
> 出现红灯时的第一步，是判断「本次改坏」还是「本来就红」。

## 实测结果

| 命令 | 结果 | 耗时 |
| --- | --- | --- |
| `.\tools\flutter.cmd analyze --no-pub` | No issues found | 约 58 s |
| `.\tools\flutter.cmd test --no-pub` | **616 tests, all passed** | 约 92 s |

工具链：Flutter 3.47.7（stable）/ Dart 3.13.5 / DevTools 2.60.0。

## 规模

| 指标 | 数量 |
| --- | ---: |
| `lib` Dart 文件 | 95 |
| `lib` 总行数 | 约 4.7 万 |
| `test` 测试文件 | 121（平铺，`<主题>_test.dart`） |
| `test` 总行数 | 约 2.1 万 |
| `lib/ui` 页面与组件 | 40 个平铺文件 |
| `lib/core` | 32 个平铺文件 + 5 个子系统目录 |
| 文案（`app_zh.arb`） | 1357 行 |

## 这个基线意味着什么

- 616 个测试是**唯一的自动化安全网**：没有 `integration_test`，没有 golden test。
  所以「跑测试」不是形式，是唯一能自动发现回归的手段。
- 全量 analyze 约 58 s、全量 test 约 92 s。代理每次改完都跑全量不现实，约定：
  **改完跑增量 analyze + 受影响的单测，全量由人兜底**（见 `AGENTS.md`）。
- `flutter analyze` / `flutter test` 默认会隐式执行 `pub get`；沙箱内联网被拦时会直接失败。
  因此日常命令一律加 `--no-pub`。
- 插件在 Stop 时会自动跑 `dart format` + `dart analyze`，其超时（90 s）与全量 analyze
  耗时（58 s）贴得比较近：机器忙的时候可能超时，属已知情况，不算改动失败。

## 已知偏差

- `pub get` 会把 `pubspec.lock` 里的 `flutter: ">=3.47.0"` 重写为 `flutter: "3.47.7"`。
  这是本机 SDK 注记，不是依赖变化。想保持工作区干净，可单独提交这一行。
