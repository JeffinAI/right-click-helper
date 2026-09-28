# FinderQuickActions — 复刻 iMenuX 三大功能 技术方案

> 本方案供审阅，确认后再开始编码。

## 1. 目标

复刻 iMenuX 的 3 个功能，全部集成到 macOS 访达（Finder）右键菜单：

| 功能 | 触发位置 | 说明 |
|---|---|---|
| 新建文件 | 文件夹**空白处**右键 | TXT、Markdown、Word、Excel、PowerPoint |
| 移动/复制到指定文件夹 | 选中文件右键 | 弹子菜单选择目标文件夹 |
| 复制路径 | 选中文件右键 | 复制「绝对路径」或「纯文件名」 |

## 2. 技术选型：Finder Sync Extension

- **为什么不用 Quick Action（方案A）**：Quick Action 必须有选中的文件/文件夹才能触发，**无法在空白处右键新建文件**。只有 Finder Sync Extension 提供「容器右键菜单」（空白处）。
- **Finder Sync Extension 优势**：同时提供 `contextualMenuForContainer`（空白处）和 `contextualMenuForFiles`（选中文件）两类菜单，三个功能一个扩展全部覆盖。
- 技术栈：**Swift + xcodegen**（用户已确认）。xcodegen 正在后台安装。

## 3. 工程结构

```
FinderQuickActions/
├── project.yml                        # xcodegen 工程定义
├── FinderQuickActions/                # 宿主 App（无 Dock 图标）
│   ├── AppDelegate.swift              # 空启动，仅承载扩展
│   └── FinderQuickActions.entitlements
└── FinderQuickActionsFinderExtension/ # Finder 扩展
    ├── FinderSync.swift               # 核心：菜单构建 + 动作实现
    └── FinderQuickActionsFinderExtension.entitlements
```

菜单只写在一个地方：`FinderSync.swift` 用 `NSCreateCommand` / `menu(for:)` 注册菜单项。

## 4. 功能实现逻辑

所有动作**纯用 FileManager + NSPasteboard** 完成，不需要外部进程或 AppleScript（因此避开沙盒对 `Process`/`NSAppleScript` 的禁止，**无需 Helper App**）。

### 4.1 新建文件（空白处右键）
- 空白处右键 → 子菜单「新建文件」→ TXT / Markdown / Word / Excel / PowerPoint
- 实现：取当前目录 `targetedURL()`，复制内置模板并重命名，文件名自动递增避免覆盖（`未命名.txt`、`未命名 2.txt`…）。
- **模板来源**：
  - TXT、Markdown：脚本直接生成纯文本
  - Word / Excel / PowerPoint：内置**最小合法 Office 空文件模板**（`.docx / .xlsx / .pptx`），构建/安装阶段用脚本生成，Extension 复制即可用 Office 打开

### 4.2 移动 / 复制到指定文件夹（选中文件右键）
- 选中文件 → 子菜单「移动/复制到」→ 目标文件夹列表 → 移动 / 复制
- 目标文件夹列表从配置文件读取，用户可增改

### 4.3 复制路径（选中文件右键）
- 子菜单「复制路径」→「绝对路径」/「纯文件名」
- `NSPasteboard` 写入剪贴板

## 5. 沙盒权限与签名

依据 Finder Sync Extension 的沙盒限制，配置如下：

| 项 | 配置 | 说明 |
|---|---|---|
| 沙盒 | `app-sandbox: true` | 扩展必须开启沙盒，否则不加载 |
| 文件读写 | `com.apple.security.temporary-exception.files.absolute-path.read-write: [/]` | 允许在任意路径新建/移动文件（本地 adhoc 发布，可接受） |
| 签名 | `CODE_SIGN_IDENTITY: "-"` | ad-hoc 签名，仅本机可用 |

## 6. 构建与注册流程

```bash
xcodegen generate                       # 生成 Xcode 工程
xcodebuild -project ... -scheme ... build
cp -R <产物>/FinderQuickActions.app /Applications/
open /Applications/FinderQuickActions.app    # 首次启动注册扩展
pluginkit -e use -i <bundle-id>.FinderExtension
# 若未自动启用：系统设置 → 通用 → 登录项与扩展 → 文件提供程序/Finder 扩展 → 勾选
killall Finder                          # 刷新访达
```

## 7. 配置

- 配置文件存放：`~/.finderquickactions/config.json`
  - `targetFolders`: 移动/复制目标文件夹列表
  - `newFileTemplates`: 新建文件模板配置
- 提供一键初始化脚本写入默认配置。

## 8. 已知限制（需知晓）

- 扩展菜单项**位置由系统决定**，会归入「Finder 扩展」区块，无法排到「新建文件夹」之前。
- **首次需要手动启用扩展**（系统设置 → 登录项与扩展）。
- ad-hoc 签名仅限本机，无法分发他人。
- **macOS 大版本更新后可能需重新启用扩展**。
- 菜单显示名可在代码中定制为中文（如「新建文件」「复制绝对路径」）。
- `temporary-exception` 允许全盘读写，属本机禁用式方案（不上架 App Store）。

## 9. 交付步骤（确认后执行）

1. 用 xcodegen 生成工程骨架
2. 实现 `FinderSync.swift` 三大功能与中文菜单
3. 编写模板生成脚本（Office 空文件）
4. 编写安装/注册脚本并执行
5. 引导你在系统设置启用扩展并实际验证