# ClaudeMac 当前完善程度

> 更新日期：2026-05-10
> 目的：给接手项目的人快速判断当前完成到哪里、哪些链路可用、哪些地方还只是骨架或待验证。

## 一句话状态

ClaudeMac 目前已经从“外部 Terminal 启动器”推进到“macOS 原生 IDE 式工作台 + 内嵌 Claude Code/Codex 对话 MVP”。项目管理、文件树、编辑器、多标签、右侧真实 CLI 会话、多会话后台运行、队列持久化、输入框自动高度、Agent process 详情、会话本地保存和按 CLI 分流的历史列表已经具备；Codex app-server 代码链路已接入，完整模型 turn 仍需 App 内手工确认。

## 当前完成度总览

| 模块 | 完成度 | 当前状态 |
| --- | --- | --- |
| macOS 主界面 | 较高 | 三栏 IDE 布局已成型：左侧项目/文件，中间编辑器，右侧对话，编辑器/对话可横向拖拽调整。 |
| 项目管理 | 较高 | 支持添加/删除项目、security-scoped bookmark、项目持久化、启动时恢复。 |
| 文件树 | 中等偏高 | 支持懒加载目录、忽略常见大目录、点击文本文件打开；暂未做 Git 状态、搜索、批量操作。 |
| 编辑器 | 中等 | AppKit `NSTextView` 编辑器、行号、多标签、UTF-8 保存、基础语法高亮已实现；还不是完整 IDE 编辑器。 |
| 顶部文件标签 | 进行中 | 已多轮贴近设计图，但视觉还在调细节，当前主要问题是尺寸、融合度和设计稿一致性仍需人工复核。 |
| 右侧聊天 UI | 较高 | 已是 IDE 式消息流，支持 user/assistant/tool/permission/error/diff、队列、自动高度输入框、Agent process、长对话缓存和轻量滚动策略。 |
| Claude Code 对接 | MVP 可用 | 通过 `Process + Pipe + stream-json` 真实启动 Claude Code，并已用最小探针验证收到 `OK` 回复；Claude ask/交互回写仍需真实样本。 |
| Codex 对接 | MVP 可试用，待完整闭环 | 已实现 `codex app-server --listen stdio://` 启动、initialize、thread/start、turn/start、权限响应和事件适配；完整模型 turn 仍需 App 内手工确认。 |
| CLI 能力探针 | 中等 | 支持查找 Homebrew 路径、读取版本、判断 Claude stream-json / resume / continue 和 Codex app-server。 |
| 会话保存/历史 | 中等偏高 | App 自建聊天会话保存到 Application Support/Acode，并和扫描到的 Claude/Codex 历史合并；侧栏按当前 CLI 分流，删除会清理相关索引。 |
| 外部 Terminal fallback | 可用 | 仍保留 Terminal/iTerm2 启动命令路径，但不再是主要对话路径。 |
| 设置页 | 基础可用 | 默认 CLI、默认终端、命令预览、历史扫描、忽略目录等已有。 |
| 测试自动化 | 低 | 当前无 XCTest target；主要依赖 `xcodebuild`、源码级探针和手工验证。 |
| 发布/安装 | 低 | 目前是本地 Debug 构建形态，未整理正式分发、签名、公证、更新链路。 |

## 已有核心能力

### 1. 工作台布局

- 入口：`ClaudeMac/Views/RootView.swift`
- 当前结构：左侧 `ProjectSidebarView`，右侧大 workbench card。
- 大卡片顶部是 `EditorTabBarView`，下方是编辑器和聊天面板。
- 中间透明拖拽条控制右侧聊天面板宽度，宽度限制为 300 到 640。

### 2. 项目、文件树和多标签

- 状态入口：`ClaudeMac/ViewModels/AppState.swift`
- 已有能力：
  - 添加项目目录。
  - 删除项目。
  - 选择项目后刷新文件树和聊天历史。
  - 自动打开 README 或第一个文本文件。
  - 文件树点击打开文本文件。
  - 标签重复打开时切换已有 tab。
  - 顶部 `+` 可以打开外部文件，支持多选。
  - `⌘S` 保存当前文本 tab。
- 文件保护：
  - 超过 5 MB 的文件不打开。
  - 二进制文件不打开。
  - 非 UTF-8 文件不打开。

### 3. 编辑器

- 入口：`ClaudeMac/AppKit/TextEditorRepresentable.swift`
- 技术：`NSScrollView + NSTextView + NSRulerView`
- 已有能力：
  - 行号。
  - 基础语法高亮。
  - Markdown / Swift / JS / Python / Go / JSON / YAML / Shell 等基础识别。
  - 光标行列状态。
  - 横向/纵向滚动。
  - 文本选择、编辑、保存。
- 当前限制：
  - 不是 Monaco/VS Code 级编辑器。
  - 没有 LSP、补全、诊断、格式化、查找替换、diff 编辑器。
  - 大文件保护比较粗粒度。

### 4. 右侧真实 CLI 对话

- UI 入口：`ClaudeMac/Views/ClaudeSessionPanelView.swift`
- 状态入口：`ClaudeMac/ViewModels/ChatPanelState.swift`
- 模型入口：`ClaudeMac/Models/ChatModels.swift`
- backend 协议：`ClaudeMac/Services/Chat/ChatProcessBackend.swift`

已实现：

- 新会话发送消息。
- running 时 action button 执行停止；运行中继续发送会进入队列。
- Claude/Codex CLI 切换。
- 模型选择。
- 权限模式选择：询问、自动编辑、完全访问。
- assistant 流式 delta 合并。
- tool / command / permission / error / diff 行显示；system/result/raw output 默认不进入主 transcript。
- 权限请求 allow/deny 写回 backend；Claude ask/交互回写仍按未验证能力处理。
- 消息、队列、草稿和运行态本地持久化。
- 选择本地历史后加载消息。
- 选择外部历史后提供 resume 提示。
- Agent 工具行可打开子代理 process 详情。

当前限制：

- 对 Claude Code JSON 事件的适配仍需用更多真实工具/权限/AskUserQuestion 样本回归。
- Permission prompt 的真实复杂交互仍需更多场景验证。
- 长输出已做批量 flush、滚动节流和缓存，但多个真实长任务并发仍需 profiler 压测。
- diff/file edit UI 有样式基础，但还不是完整可应用/撤销 patch 的编辑器级体验。

### 5. Claude Code backend

- 入口：`ClaudeMac/Services/Chat/ClaudeCodeProcessBackend.swift`
- 启动方式：`claude -p <prompt> --output-format stream-json --verbose --permission-mode <mode>`
- 支持：
  - `--continue`
  - `--resume <id>`
  - `--model <id>`
  - permission mode 映射
  - stdout/stderr 并发读取
  - JSONL 解析
  - 进程停止

本地已验证：

- `claude` 可在 GUI 环境通过 Homebrew PATH 找到。
- Claude Code 版本探针可返回版本。
- 最小真实对话探针收到 assistant `OK`，并正常 finished。
- Debug 构建通过。

### 6. Codex backend

- 入口：`ClaudeMac/Services/Chat/CodexAppServerBackend.swift`
- 设计路径：`codex app-server --listen stdio://`
- 已写入：
  - initialize
  - thread/start
  - turn/start
  - turn/interrupt
  - approval/respond
  - stdout/stderr JSONL 事件适配
- 当前状态：
  - 代码链路已接入 app-server JSON-RPC。
  - UI 会显示 Codex 缺失或 app-server 不支持。
  - 没有完成真实 Codex 端到端模型 turn 验证。

### 7. CLI 探针和 GUI PATH 修复

- 入口：`ClaudeMac/Services/Chat/ChatCLICapabilityProbe.swift`
- 共享环境：`ClaudeMac/Services/Chat/ChatProcessBackend.swift`
- 已处理：
  - macOS GUI App 缺少 shell PATH 的问题。
  - 优先查找 `/opt/homebrew/bin`、`/usr/local/bin` 等路径。
  - fallback 到 zsh `command -v`。
  - 子进程统一注入 Homebrew PATH。
- entitlements 已包含：
  - app sandbox
  - user-selected read-write
  - bookmark
  - network client
  - `.claude/`、`.codex/` 临时读写例外
  - `/opt/homebrew/`、`/usr/local/` 临时只读例外

### 8. 本地会话和数据位置

App 自己的聊天会话：

- `~/Library/Application Support/Acode/chat-sessions.json`
- `~/Library/Application Support/Acode/chat-messages/<session-id>.jsonl`
- `~/Library/Application Support/Acode/chat-drafts.json`

项目和启动记录：

- `~/Library/Application Support/Acode/projects.json`
- `~/Library/Application Support/Acode/launch-history.json`

外部 Claude 历史扫描：

- `~/.claude/projects`

## 当前主要风险和缺口

### 高优先级

1. **Codex 完整 turn 仍需 App 内手工验证**  
   本机已验证 Codex app-server initialize、schema 和 model/list；由于直接命令探针受当前 shell 沙盒限制，完整 thread 写入和模型 turn 需要用带 `.codex` entitlement 的 App 构建手工确认。

2. **聊天权限链路需要更多真实场景**  
   目前有 permission row 和 response 写回，但真实文件编辑、命令执行、拒绝权限、重复权限请求仍需矩阵验证。

3. **顶部标签视觉仍需设计对齐**  
   已按截图多轮调整，但仍依赖人工截图复核，建议后续固定一版尺寸规范。

4. **缺少自动化测试 target**  
   JSONL 半包解析、Claude 事件适配、ChatSessionStore、AppState 文件保护目前没有 XCTest 覆盖。

5. ~~**README 已落后于当前形态**~~  
   ✅ 已修复。README 已重写为”内嵌 CLI 对话工作台”形态，分类列出已实现功能、修正了毛玻璃/语法高亮/图标等描述偏差。

### 中优先级

1. 编辑器能力不足：没有搜索、替换、LSP、格式化、diff apply。
2. 文件树能力不足：没有搜索、Git 状态、右键菜单、拖拽批量导入完整闭环。
3. 外部 CLI 历史恢复仍是轻量占位，不完整还原外部 transcript。
4. full access 虽不是默认，但还需要更明确的 UI 风险提示和二次确认。
5. 长输出、多会话并发、大量 tool event 和大项目文件树性能仍需要实际压测。

### 低优先级

1. ~~正式 App 图标和品牌视觉。~~  ✅ App 图标已完成（10 尺寸齐全）。品牌视觉待定。
2. 发布签名、公证、自动更新。
3. 插件系统、MCP marketplace、多 agent、云同步。
4. Git 集成、SSH、远程开发。

## 上手建议

### 推荐先读

1. `README.md`：了解当前工作台能力概览。
2. `docs/对话系统改造与Windows开发交接.md`：了解对话系统和 Windows 复刻基线。
3. `docs/chat-cli-panel-research.md`：了解 Claude/Codex 对接调研和实现记录。
4. `docs/project-current-status.md`：了解当前完成度和缺口。
5. `ClaudeMac/Views/RootView.swift`：看整体布局。
5. `ClaudeMac/ViewModels/AppState.swift`：看项目、文件、历史、终端 fallback 的全局状态。
6. `ClaudeMac/ViewModels/ChatPanelState.swift`：看聊天状态机。
7. `ClaudeMac/Services/Chat/ClaudeCodeProcessBackend.swift`：看 Claude Code 真实对接。
8. `ClaudeMac/Services/Chat/CodexAppServerBackend.swift`：看 Codex app-server 骨架。

### 推荐本地启动

```bash
xcodebuild -project ClaudeMac.xcodeproj -scheme ClaudeMac -configuration Debug build
open ClaudeMac.xcodeproj
```

### 推荐手工验收路径

1. 添加一个本地项目目录。
2. 确认文件树加载。
3. 打开 README 或其他文本文件。
4. 编辑后保存。
5. 点击顶部 `+` 打开外部文件。
6. 右侧选择 Claude Code。
7. 使用“询问权限”模式发送一句简单消息。
8. 确认有真实流式回复。
9. 停止一次运行中的回复。
10. 重启 App 后确认项目、历史、聊天会话仍在。

### 推荐下一步开发顺序

1. 固定顶部标签栏视觉规范，结束 UI 反复调参。
2. 给 JSONLStreamReader、ClaudeCodeProcessBackend event adapter、ChatSessionStore 加 XCTest。
3. 安装 Codex 后做 app-server 协议真实验证。
4. 补齐权限请求真实场景：命令执行、文件修改、允许/拒绝、停止。
5. ~~更新 README，使其和当前内嵌聊天形态一致。~~ ✅ 已完成。
6. 做一次 UI 手工回归：文件树、编辑器、聊天、历史、外部文件打开、终端 fallback。

## 最近验证记录

本轮已验证：

- `xcodebuild -project ClaudeMac.xcodeproj -scheme ClaudeMac -configuration Debug build`：通过。
- Claude Code GUI PATH/sandbox 修复后，能力探针可找到 `/opt/homebrew/bin/claude`。
- Claude Code 最小真实 backend probe 收到 assistant `OK` 并 finished。
- Codex 本机缺失，缺失态已验证；真实 app-server 未验证。

## 接手判断

如果目标是继续做 macOS 版 ClaudeMac：当前代码已经适合继续迭代，不需要推倒重写。

如果目标是做 Windows 版：建议不要直接复用 SwiftUI/AppKit UI，应该复用产品设计和状态模型，技术路线另起为 Tauri 2 + Rust core + Web UI。Claude/Codex CLI 对接思路可以参考当前 `Services/Chat` 的 Process、Pipe、JSONL、session store 结构。
