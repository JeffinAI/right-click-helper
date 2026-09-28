<div align="center">
  <img src="docs/AppIcon.png" width="120" alt="右键助手">
  <h1>右键助手 · right-click-helper</h1>
  <p>macOS 访达（Finder）右键菜单增强工具，基于 Apple 官方 Finder Sync Extension 实现</p>
  <p>
    <img src="https://img.shields.io/badge/macOS-13.0%2B-blue" alt="macOS 13.0+">
    <img src="https://img.shields.io/badge/Swift-5.0-orange" alt="Swift 5.0">
    <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
  </p>
</div>

---

复刻 iMenuX 的三个核心功能，直接在访达右键菜单里完成：

| 功能 | 触发位置 | 说明 |
|---|---|---|
| **新建文件** | 文件夹**空白处**右键 | TXT、Markdown、Word、Excel、PowerPoint |
| **移动到 / 复制到** | 选中文件右键 | 子菜单列出常用文件夹，也可手动选择任意文件夹 |
| **复制路径** | 选中文件右键 | 复制「绝对路径」或「纯文件名」 |

## 菜单结构

```
文件夹空白处右键
└── 新建文件
    ├── TXT 文本
    ├── Markdown
    ├── Word 文档
    ├── Excel 表格
    └── PowerPoint 演示

选中文件右键
├── 复制到
│   ├── 下载
│   ├── 文稿
│   ├── 桌面
│   ├── ──────────
│   └── 选择文件夹…
├── 移动到
│   ├── 下载
│   ├── 文稿
│   ├── 桌面
│   ├── ──────────
│   └── 选择文件夹…
├── ──────────
├── 复制绝对路径
└── 复制文件名
```

菜单项都带系统图标，文件夹名跟随 macOS 语言（中文系统显示「下载 / 文稿 / 桌面」）。

## 系统要求

- macOS 13.0 或更高
- Xcode 命令行工具（`xcode-select --install`）
- [xcodegen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

## 快速开始

```bash
git clone https://github.com/JeffinAI/right-click-helper.git
cd right-click-helper
./scripts/deploy.sh
```

`deploy.sh` 会依次完成：生成 Xcode 工程 → Release 编译 → 生成空白模板与默认配置 → 安装到 `/Applications/右键助手.app` → 注册并启用 Finder 扩展。

## 首次启用扩展

macOS 不允许应用自动开启 Finder 扩展，**首次必须手动勾选一次**：

> 系统设置 → 通用 → 登录项与扩展 → Finder 扩展 → 勾选「右键助手」

然后执行 `killall Finder` 刷新访达。之后每次开机系统会自动加载，无需重复操作。

## 配置

配置文件与模板存放在 `~/.finderquickactions/`：

```
~/.finderquickactions/
├── config.json              # 目标文件夹列表
└── templates/               # 新建文件用的空白模板
    ├── template.docx
    ├── template.xlsx
    └── template.pptx
```

`config.json`：

```json
{
  "targetFolders": [
    "/Users/你/Downloads",
    "/Users/你/Documents",
    "/Users/你/Desktop"
  ]
}
```

改完保存即可生效，无需重新部署。删除该文件后重新运行 `deploy.sh` 会生成默认配置。

## 项目结构

```
right-click-helper/
├── project.yml                              # xcodegen 工程定义（唯一的工程配置来源）
├── FinderQuickActions/                      # 宿主 App（LSUIElement，无 Dock 图标）
│   ├── main.swift
│   ├── AppDelegate.swift                    # 处理「选择文件夹…」弹出的系统选择器
│   ├── Info.plist
│   ├── AppIcon.icns
│   └── FinderQuickActions.entitlements
├── FinderQuickActionsFinderExtension/       # Finder Sync 扩展（功能主体）
│   ├── FinderSync.swift                     # 菜单构建 + 文件操作
│   ├── Info.plist
│   ├── AppIcon.icns
│   └── FinderQuickActionsFinderExtension.entitlements
├── scripts/
│   ├── deploy.sh                            # 一键构建 + 安装 + 注册
│   └── make_templates.py                    # 生成 Office 空白模板与默认配置
└── docs/
    ├── AppIcon.png                          # 图标设计稿
    └── icon-variants.png                    # 图标方案对比
```

> `FinderQuickActions.xcodeproj` 由 `xcodegen generate` 生成，已加入 `.gitignore`，不入库。

## 实现要点

- **为什么用 Finder Sync Extension**：Quick Action（快捷操作）必须有选中项才能触发，**无法在文件夹空白处右键**；只有 Finder Sync Extension 同时提供 `contextualMenuForContainer`（空白处）与 `contextualMenuForItems`（选中项）两类菜单，三个功能一个扩展全覆盖。
- **Office 模板**：`make_templates.py` 直接拼装最小合法 OOXML（`.docx / .xlsx / .pptx`），不依赖 Office 或任何第三方库，生成的空白文件可被 Office / WPS / Pages 正常打开。
- **沙盒主目录**：扩展运行在沙盒中，`homeDirectoryForCurrentUser` 会指向容器目录，因此改用 `getpwuid(getuid())` 取真实主目录，才能正确读写 `~/.finderquickactions/`。
- **「选择文件夹…」的实现**：Apple 规定 Finder Sync 扩展不得直接弹出 UI，因此扩展把请求写入 `~/.finderquickactions/request.json` 并唤起宿主 App，由宿主 App 弹出系统文件夹选择器并执行复制/移动。

## 已知限制

- 菜单项**位置由系统决定**，会归入右键菜单的「Finder 扩展」区块，无法排到「新建文件夹」等系统项之前，也不能自定义排序。
- **首次需要手动启用扩展**；macOS 大版本更新后可能需重新启用。
- 使用 ad-hoc 签名，仅限本机使用，**无法分发给他人**（他人需自行编译）。
- 沙盒开启了 `temporary-exception.files.absolute-path.read-write`（全盘读写）以支持在任意目录新建/移动文件，因此**不适合上架 App Store**。

## 卸载

```bash
rm -rf "/Applications/右键助手.app"
rm -rf ~/.finderquickactions
killall Finder
```

再回到 系统设置 → 登录项与扩展 → Finder 扩展 取消勾选即可。

## 开源协议

[MIT](LICENSE)