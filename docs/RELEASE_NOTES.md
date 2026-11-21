# 发布说明约定

发布说明以 GitHub Releases 为唯一归档，不在仓库保存每个版本的副本。

## 默认生成

`gh release create --generate-notes` 按
[`.github/release.yml`](../.github/release.yml) 生成正文。变更会归入
`更新日志` 分类，App 更新弹窗会截取这一节并转成逐行列表。

## 显式覆盖

需要定制说明时，可给发布脚本传入显式文件：

```powershell
powershell -ExecutionPolicy Bypass -File tools/release/publish.ps1 -NotesFile .\release-notes.md
```

建议正文至少包含一个列表小节：

```markdown
## 更新日志

- 修复示例问题
- 新增示例能力
```

App 会从「更新日志 / 更新说明 / Changelog」标题开始，到下一个小节结束；
列表项会显示为项目符号，引用行和 Markdown 链接只保留可读文本。
