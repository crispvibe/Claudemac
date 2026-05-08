# ClaudeMac

ClaudeMac 是一个 macOS 原生 AI CLI 工作台，用来管理项目、快速浏览/编辑文件，并在内嵌面板或系统 Terminal / iTerm2 中启动 Claude Code / Codex 会话。

> 当前完善程度、已验证链路和接手建议见：[`docs/project-current-status.md`](docs/project-current-status.md)。

## 运行方式

要求：macOS 14+，Xcode 15/16。

```bash
xcodebuild -list -project ClaudeMac.xcodeproj
xcodebuild -project ClaudeMac.xcodeproj -scheme ClaudeMac -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData
```

也可以直接用 Xcode 打开：

```bash
open ClaudeMac.xcodeproj
```

## 已实现功能

- macOS 原生 SwiftUI 三栏界面。
- 左右侧栏使用 `NSVisualEffectView` 毛玻璃效果。
- 添加项目目录。
- 使用 security-scoped bookmark 持久化项目访问权限。
- 项目列表持久化到 Application Support。
- 文件目录树，默认忽略 `.git`、`node_modules`、`dist`、`build`、`.dart_tool`、`.idea`、`.vscode` 等目录。
- 点击文本文件打开到中间编辑器。
- 多标签编辑。
- `NSTextView` + `NSRulerView` 行号编辑器。
- UTF-8 文本保存。
- 二进制文件、大文件、非 UTF-8 文件打开保护。
- Claude Code 会话面板。
- 右侧面板可切换 Claude Code / Codex。
- 恢复历史支持手动输入 session id / name，留空则打开 Claude 选择器。
- macOS Settings 窗口，可配置默认 CLI、默认终端、命令预览、Claude 历史扫描和忽略目录。
- 新建会话：`claude`。
- 继续上次：`claude --continue`。
- 恢复历史：`claude --resume <sessionId>`。
- 安全 shell quoting，支持中文、空格、单引号等路径。
- Apple Terminal / iTerm2 AppleScript 启动。
- 本 App 最近启动记录持久化。
- 实验性只读扫描 `~/.claude/projects` 下的 Claude Code JSONL 历史。

## 未实现功能

- 完整语法高亮。
- Git 集成。
- 内嵌终端。
- Codex 私有历史解析。
- 远程 SSH。
- 插件系统。
- App 图标设计。

## 项目结构

```text
ClaudeMac.xcodeproj/
ClaudeMac/
  ClaudeMacApp.swift
  Models/
  ViewModels/
  Views/
  AppKit/
  Services/
  Assets.xcassets/
  Info.plist
  ClaudeMac.entitlements
```

## 关键技术说明

### NSVisualEffectView 毛玻璃

`AppKit/VisualEffectView.swift` 将 `NSVisualEffectView` 封装为 SwiftUI `NSViewRepresentable`。左右侧栏通过 `GlassPanel` 使用系统 material，保持浅色半透明和原生 macOS 质感。

### Security-scoped bookmark

`Services/ProjectStore.swift` 在添加项目时通过 `NSOpenPanel` 获取用户授权目录，并保存 `.withSecurityScope` bookmark。读取文件树、打开文件、保存文件时都会 resolve bookmark 并临时 `startAccessingSecurityScopedResource()`。

### 文件树

`Services/FileTreeScanner.swift` 只读取当前展开目录的直接子级，并跳过常见大目录和隐藏构建目录，避免大项目一次性深扫卡顿。

### NSTextView 编辑器

`AppKit/TextEditorRepresentable.swift` 封装 `NSScrollView + NSTextView`。`AppKit/LineNumberRulerView.swift` 通过 `NSRulerView` 绘制行号。MVP 不做复杂语法高亮，优先保证文本清晰、可编辑、可保存。

### Terminal / iTerm2 启动

`Services/TerminalLauncher.swift` 使用 AppleScript 控制 Terminal 或 iTerm2，在外部终端中新建会话并写入命令，不内嵌 PTY。

### 命令转义

`Services/CommandBuilder.swift` 使用单引号 shell quoting：

```text
'abc'       -> 'abc'
a'b        -> 'a'\''b'
```

生成命令形如：

```bash
cd '/Users/oreo/Desktop/公司/摄影 go-server/server' && claude --continue
```

不会使用 `cd "~/..."`，避免 `~` 在引号内无法展开。

## 手工验收建议

1. 添加一个中文或带空格路径的项目。
2. 展开文件树，确认大目录被忽略。
3. 打开 Markdown 文件。
4. 编辑文本并使用 `⌘S` 保存。
5. 点击“新建会话”，检查命令预览为 `claude`。
6. 点击“继续上次”，检查命令预览为 `claude --continue`。
7. 点击“打开终端”，确认 Terminal 新窗口执行命令。
8. 重启 App，确认项目和最近记录仍存在。

## 数据位置

本 App 数据写入：

```text
~/Library/Application Support/ClaudeMac/projects.json
~/Library/Application Support/ClaudeMac/launch-history.json
```

Claude Code 历史扫描只读访问：

```text
~/.claude/projects
```
