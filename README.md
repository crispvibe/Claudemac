# Codevoke

Codevoke 是一个 macOS 原生 AI CLI 工作台，用来管理项目、快速浏览/编辑文件，并在内嵌面板中与 Claude Code / Codex 进行真实对话。同时保留外部 Terminal / iTerm2 启动作为 fallback。

> 当前完善程度、已验证链路和接手建议见：[`docs/project-current-status.md`](docs/project-current-status.md)。

## 运行方式

要求：macOS 14+，Xcode 15/16。

```bash
xcodebuild -list -project Codevoke.xcodeproj
xcodebuild -project Codevoke.xcodeproj -scheme Codevoke -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData
```

也可以直接用 Xcode 打开：

```bash
open Codevoke.xcodeproj
```

## 打包到桌面

本地测试包固定使用本机 Developer ID 证书签名：

- 签名身份：`Developer ID Application: Zhang XueFeng (XY6Z92AMPS)`
- Team ID：`XY6Z92AMPS`
- 当前阶段：Developer ID 签名、公证、stapler 和 Gatekeeper 校验流程已接入脚本；正式发布用 `NOTARIZE=1` 打包。

以后重新打包并替换桌面端，统一运行：

```bash
scripts/package-macos-app.sh
```

产物会替换到 `~/Desktop/Codevoke.app`，并默认生成 `build/releases/acode-macos.dmg`。脚本会执行 Universal Release build（`arm64 x86_64`）、strip 发布包符号、校验 `lipo` 架构、校验 `codesign` 签名链和 Team ID，并拒绝带 `get-task-allow` 的调试 entitlement。

正式公证包使用：

```bash
NOTARIZE=1 scripts/package-macos-app.sh
```

更详细的发布约定见：[`docs/macos-packaging.md`](docs/macos-packaging.md)。

## 已实现功能

### 工作台

- macOS 原生 SwiftUI 三栏界面（左侧项目/文件、中间编辑器、右侧 CLI 对话）。
- 左侧栏使用 `NSVisualEffectView` 毛玻璃效果（`GlassPanel`）。
- 编辑器和聊天面板之间可拖拽调整宽度（300–640）。
- 隐藏标题栏，菜单栏全中文化。

### 项目管理

- 添加 / 删除项目目录。
- 使用 security-scoped bookmark 持久化项目访问权限。
- 项目列表持久化到 Application Support。
- 启动时自动恢复项目列表和最近打开状态。

### 文件树

- 懒加载目录树，只读取当前展开目录的直接子级。
- 默认忽略 `.git`、`node_modules`、`dist`、`build`、`.dart_tool`、`.idea`、`.vscode` 等 16 个目录。
- 点击文本文件打开到中间编辑器。
- 文件节点支持拖拽到聊天输入框。

### 编辑器

- 多标签编辑，顶部 tab 栏支持关闭和外部文件打开（`+` 按钮）。
- `NSTextView` + `NSRulerView` 行号编辑器。
- 基础语法高亮：Swift / JS / Python / Go / JSON / YAML / Markdown / Shell 八种语言的 regex 级着色。
- UTF-8 文本保存（`⌘S`）。
- 二进制文件、大文件（>5 MB）、非 UTF-8 文件打开保护。
- 底部状态栏：文件名、大小、行数、光标位置、修改时间。

### 内嵌 CLI 对话

- 右侧面板可切换 Claude Code / Codex。
- Claude Code 通过 `claude -p <prompt> --output-format stream-json --verbose` 真实启动，流式接收 assistant delta。
- Codex 通过 `codex app-server --listen stdio://` 对接（JSON-RPC），已接入 initialize / thread / turn / approval / event adapter。Codex 完整模型 turn 仍需 App 内手工确认。
- 模型选择：Claude 支持 Opus 4.7 / Sonnet 4.6 / Haiku 4.5；Codex 支持 GPT-5.x 系列。
- 权限与思考强度选择：默认自动编辑（Claude `acceptEdits` / Codex `on-failure`），完全访问会二次确认后使用 Claude `bypassPermissions` / Codex `danger-full-access`；思考强度按当前 CLI 显示合法选项。
- 权限请求 UI：拒绝 / 允许 / 本会话允许。Codex 三态完整；Claude ask 当前禁用，等待真实 stdin/control 回写协议验证。
- 消息流支持 user / assistant / reasoning / tool / command / permission / diff / error 等主线行样式，system/result/raw 默认不进入主 transcript。
- 新建会话 / 继续上次（`--continue`）/ 恢复历史（`--resume <id>`）。
- 会话本地持久化（`chat-sessions.json` + `chat-messages/<uuid>.jsonl` + `chat-drafts.json`），包含队列和运行态快照。

### 历史会话

- 历史侧栏只显示和管理 Codevoke 本地 `ChatSessionStore` 会话。
- 会话按当前 CLI 分流显示，使用本地 `chat-sessions.json` 索引和 `chat-messages/<uuid>.jsonl` transcript。
- 支持删除本地会话，删除时同步清理相关索引和 transcript。

### 外部终端 fallback

- 安全 shell quoting，支持中文、空格、单引号等路径。
- Apple Terminal / iTerm2 AppleScript 启动。
- 本 App 最近启动记录持久化（最多 50 条）。

### 设置

- macOS Settings 窗口：默认 CLI、默认终端、忽略目录列表、追加规则、Claude/Codex 配置、全局规则、更新与关于。

### 远程账号 / 信令

- Go 后端提供 `GET /remote/signaling/ws?token=<accessToken>`，客户端升级 WebSocket 后首帧发送 `hello { deviceId }`。
- 信令通道负责设备在线状态、连接审批通知和未来 WebRTC `offer` / `answer` / `ice_candidate` 的透明 relay；聊天正文仍不经过 Go 后端，18765 局域网服务不对公网暴露。
- 当前单实例 MVP 使用进程内 `sync.Map[deviceId]*Conn` 保存在线连接；多实例部署需要引入 Redis pub/sub 或等价的跨实例信令 fan-out。

### 其他

- App 图标已设计（10 个尺寸齐全）。
- GUI App PATH 修复：自动注入 Homebrew / npm-global / cargo / bun 等路径，解决图形 App 启动环境下找不到 CLI 的问题；当前本地分发未正式启用 App Sandbox。

## 未实现 / 待完善

- LSP / tree-sitter 级完整语法高亮（当前为 regex 基础高亮）。
- Git 集成（状态、diff、blame）。
- 内嵌终端（PTY）。
- Codex 完整模型 turn 端到端验证。
- 自动化测试（无 XCTest target）。
- 远程 SSH。
- 插件系统。
- 编辑器搜索 / 替换 / LSP 补全。
- 聊天 delta 节流优化（长输出性能）。

## 项目结构

```text
Codevoke.xcodeproj/
Codevoke/
  CodevokeApp.swift          # @main 入口，窗口配置，菜单中文化
  Models/
    AppModels.swift           # ProjectItem, FileNode, EditorTab, LaunchRecord, CLIHistorySession, AppSettings
    ChatModels.swift          # ChatMessage, ChatSessionRecord, ChatRunOptions, ChatBackendEvent, 权限/模型枚举
  ViewModels/
    AppState.swift            # 全局状态中心：项目、文件树、标签、历史、设置
    ChatPanelState.swift      # 聊天状态机：idle → starting → streaming → completed/failed
  Views/
    RootView.swift            # 三栏布局 + 拖拽调整
    ProjectSidebarView.swift  # 项目列表 + 历史子行 + 文件树
    FileTreeView.swift        # 懒加载文件树节点
    EditorTabBarView.swift    # 顶部标签栏
    EditorAreaView.swift      # 编辑器 + 状态栏
    ClaudeSessionPanelView.swift  # 聊天面板（消息流 + composer）
    GlassPanel.swift          # AppTheme 调色板 + 毛玻璃容器
    SettingsView.swift        # macOS Settings 窗口
  AppKit/
    VisualEffectView.swift    # NSVisualEffectView SwiftUI 包装
    TextEditorRepresentable.swift  # NSTextView + 语法高亮
    LineNumberRulerView.swift # 行号绘制
  Services/
    ProjectStore.swift        # 项目持久化 + bookmark
    FileTreeScanner.swift     # 目录扫描 + 忽略规则
    CommandBuilder.swift      # shell quoting
    TerminalLauncher.swift    # AppleScript 启动终端
    LaunchHistoryStore.swift  # 启动记录持久化
    Chat/
      ChatProcessBackend.swift      # 协议 + 环境 + PATH 修复 + 进程运行器
      ChatCLICapabilityProbe.swift  # CLI 能力探测
      ClaudeCodeProcessBackend.swift  # Claude Code stream-json 对接
      CodexAppServerBackend.swift     # Codex app-server JSON-RPC 对接
      JSONLStreamReader.swift         # Pipe → AsyncThrowingStream<String>
      ChatSessionStore.swift          # 本地会话持久化
  Assets.xcassets/
  Info.plist
  Codevoke.entitlements
```

## 关键技术说明

### NSVisualEffectView 毛玻璃

`AppKit/VisualEffectView.swift` 将 `NSVisualEffectView` 封装为 SwiftUI `NSViewRepresentable`。左侧栏通过 `GlassPanel` 使用系统 `.sidebar` material，保持浅色半透明和原生 macOS 质感。右侧聊天面板使用 `editorSurface` 半透明背景，不使用 NSVisualEffectView。

### Security-scoped bookmark

`Services/ProjectStore.swift` 在添加项目时通过 `NSOpenPanel` 获取用户授权目录，并保存 `.withSecurityScope` bookmark。读取文件树、打开文件、保存文件时都会 resolve bookmark 并临时 `startAccessingSecurityScopedResource()`。

### GUI App PATH 修复

macOS sandbox App 启动时 `$PATH` 极简，找不到 Homebrew 安装的 CLI。`ChatCLIEnvironment` 通过 `getpwuid` 获取真实 HOME，把 `~/.local/bin`、`~/.bun/bin`、`~/.cargo/bin`、`/opt/homebrew/bin`、`/usr/local/bin` 等路径注入子进程环境。Capability probe 会试运行候选 CLI 的 `--version`，跳过不可执行或架构不兼容的残留路径，再兜底 `zsh -lc 'command -v -a'`。

### 文件树

`Services/FileTreeScanner.swift` 只读取当前展开目录的直接子级，并跳过常见大目录和隐藏构建目录，避免大项目一次性深扫卡顿。

### NSTextView 编辑器

`AppKit/TextEditorRepresentable.swift` 封装 `NSScrollView + NSTextView`。`AppKit/LineNumberRulerView.swift` 通过 `NSRulerView` 绘制行号。内置 `SyntaxHighlighter` 提供八种语言的 regex 级基础高亮（关键字、类型、字符串、注释、数字、函数、属性），用 protected ranges 避免字符串/注释内被误着色。

### CLI 对话 Backend

统一协议 `ChatProcessBackend`，输出 `AsyncThrowingStream<ChatBackendEvent>`：

- **Claude Code**：`claude -p <prompt> --output-format stream-json --verbose --permission-mode <mode>`，解析 JSONL 事件。
- **Codex**：`codex app-server --listen stdio://`，JSON-RPC 协议（`initialize → thread/start → turn/start`），通知事件适配为相同的 `ChatBackendEvent`。

UI 层 `ChatPanelState.apply(event)` 统一处理，换 CLI 不改 UI。

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

不会使用 `cd “~/...”`，避免 `~` 在引号内无法展开。

## 手工验收建议

1. 添加一个中文或带空格路径的项目。
2. 展开文件树，确认大目录被忽略。
3. 打开 Markdown 文件，确认语法高亮（标题、链接、列表）。
4. 编辑文本并使用 `⌘S` 保存。
5. 右侧选择 Claude Code，发送一句简单消息，确认流式回复。
6. 停止一次运行中的回复。
7. 切换到外部终端模式，确认 Terminal 新窗口执行命令。
8. 重启 App，确认项目、历史、聊天会话仍存在。

## 数据位置

本 App 数据写入：

```text
~/Library/Application Support/Codevoke/projects.json
~/Library/Application Support/Codevoke/settings.json
~/Library/Application Support/Codevoke/launch-history.json
~/Library/Application Support/Codevoke/file-tree-state.json
~/Library/Application Support/Codevoke/config-profiles.json
~/Library/Application Support/Codevoke/chat-sessions.json
~/Library/Application Support/Codevoke/chat-messages/<session-id>.jsonl
~/Library/Application Support/Codevoke/chat-drafts.json
```

旧版 `~/Library/Application Support/ClaudeMac` 数据会迁移到 `~/Library/Application Support/Codevoke`。Codevoke 不再扫描外部 Claude/Codex 历史文件，历史侧栏以本地会话存储为准。
