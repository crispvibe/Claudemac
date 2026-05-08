# ClaudeMac 右侧 CLI 对话面板调研与开发报告

访问日期：2026-05-08  
目标：把当前右侧“打开终端”面板升级为类似 VS Code / IDE 插件的内嵌对话面板，支持 Claude Code 与 Codex CLI、模型选择、完全访问权限、权限请求、工具输出、会话历史和可验证开发切片。

## 1. 结论

建议主路径放弃 AppleScript/Terminal 自动化，改为 **SwiftUI 原生对话 UI + 后台 CLI 进程桥接 + 统一事件模型**。

- Claude Code：优先通过 `Process + Pipe` 启动 `claude`，使用 stream-json / 非交互模式读取 stdout JSONL，stdin 写入用户消息和权限响应。
- Codex：优先采用官方 `codex app-server --listen stdio://` 协议；若本机 Codex 版本不支持 app-server，再临时降级到 `codex proto`。
- UI：输入框下方固定放 CLI 选择、模型选择、权限模式选择；消息区按 user / assistant / reasoning / tool / command / diff / permission / error / result 分类渲染。
- 权限：不能只有“完全访问”。必须同时保留默认安全模式、自动编辑/自动批准模式、完全访问模式，并在 UI 中显式提示风险。
- 开发顺序：先做 Claude Code MVP，再接 Codex app-server；先纯文字流式对话，再扩展权限卡片、工具卡片、diff、历史、附件。

## 2. 调研范围与可信度

| 来源 | 类型 | 可信度 | 关键用途 |
| --- | --- | --- | --- |
| Claude Code 官方 VS Code 文档 | 一手 | 9/10 | 确认官方推荐图形对话面板、模式选择、模型切换、终端模式只是可选 |
| Claude Code 官方 CLI/headless/settings/permission 文档 | 一手 | 9/10 | 确认 stream-json、permission-mode、model/defaultMode、VS Code mode selector |
| OpenAI Codex 官方仓库 `openai/codex` | 一手 | 10/10 | 确认 app-server、thread/turn、model/list、approval、sandbox、stdio JSONL |
| `andrepimenta/claude-code-chat` | 源码案例 | 7/10 | 观察 Claude Code Chat VS Code 扩展如何通过 spawn + stream-json 做图形聊天 |
| `milisp/codexia-vscode` | 源码案例 | 6/10 | 观察 Codex CLI proto 方式、模型/approval/sandbox 配置 |
| `cline/cline` | 源码案例 | 8/10 | 完整 AI IDE 对话应用的消息类型、状态、工具/命令/diff/历史/检查点 |
| `RooCodeInc/Roo-Code` | 源码案例 | 8/10 | Cline 衍生架构，补充 ask/say 状态、idle/interactive/resumable 分类 |
| `continuedev/continue` | 源码案例 | 8/10 | 补充通用 IDE-webview 协议、history/config/tools/model fetch/terminal process 管理 |

不确定项：Claude Code `--permission-prompt-tool stdio` 在第三方源码里出现，但官方公开文档只写 “Specify an MCP tool”。实现前必须用本机 `claude --version` 和最小 stdin/stdout demo 验证。

## 3. 官方事实

### 3.1 Claude Code 官方 VS Code 形态

官方文档明确：VS Code 扩展提供 native graphical interface，是在 VS Code 中使用 Claude Code 的推荐方式。功能包括：

- review/edit plans before accepting；
- auto-accept edits；
- `@` mention files with line ranges；
- conversation history；
- multiple conversations in tabs/windows；
- 默认 graphical chat panel；
- `Use Terminal` 只是偏好 CLI-style interface 的可选设置；
- command menu 支持 attach files、switch models、extended thinking、usage、Remote Control；
- mode selector 支持 permission modes；
- `allowDangerouslySkipPermissions` 会把 Auto mode 和 Bypass permissions 加入 mode selector；
- 官方提示 Bypass permissions 只应在无互联网的 sandbox 中使用。

对 ClaudeMac 的影响：右侧面板不能只是一个命令启动器，至少要有对话、模式、模型、历史、权限状态和多会话能力的架构预留。

### 3.2 Claude Code CLI/headless 能力

官方 CLI/headless 文档确认：

- `--output-format` 支持 `text | json | stream-json`；
- `--input-format` 支持 `text | stream-json`；
- `--permission-mode` 支持 `default | acceptEdits | plan | auto | dontAsk | bypassPermissions`；
- settings 里 `permissions.defaultMode` 可持久化默认权限模式；
- settings 里有 `model`；
- `--permission-prompt-tool` 用于非交互模式权限提示；
- headless/Agent SDK CLI 用 `-p` 非交互执行，支持结构化输出和 streaming JSON。

实现风险：官方文档把 `--input-format` 标注为 print mode，所以 ClaudeMac 需要先跑最小兼容实验，确认当前本机 Claude Code 版本在长会话 stdin 流下的行为。

### 3.3 Codex app-server 官方协议

OpenAI `openai/codex` 仓库 README 写明 Codex CLI runs locally。`codex-rs/app-server/README.md` 进一步说明：

- `codex app-server` 是 Codex VS Code extension 等 rich interface 使用的接口；
- 协议类似 MCP，使用 JSON-RPC 2.0，线上省略 `jsonrpc` header；
- 默认传输是 stdio：newline-delimited JSON；
- 核心对象是 Thread、Turn、Item；
- `thread/start` 创建新会话，`thread/resume` 继续会话，`thread/fork` 分叉会话；
- `turn/start` 发送用户输入，可覆盖 model、cwd、sandbox policy、approval policy、approvals reviewer；
- stdout 持续收 JSON-RPC notifications：`item/started`、`item/completed`、`item/agentMessage/delta`、tool progress 等；
- `turn/interrupt` 取消当前 turn；
- `model/list` 返回模型列表、reasoning effort、service tiers；
- `command/exec`、`process/spawn`、`fs/readFile`、`fs/writeFile` 等支持 IDE rich client；
- `approvalPolicy` 和 `sandbox` 可在 thread/start 示例中传：`approvalPolicy: "never"`、`sandbox: "workspaceWrite"`。

对 ClaudeMac 的影响：Codex 不应该走“拼接一条 terminal 命令”的路线，官方 app-server 已经给了桌面 App/IDE 应用所需的协议层。

## 4. 开源源码观察

### 4.1 Claude Code Chat：Claude CLI 进程桥接

`andrepimenta/claude-code-chat` 源码观察点：

- VS Code 侧注册 webview/sidebar provider；
- 后端 `ClaudeChatProvider` 管理 webview lifecycle、message routing、Claude CLI process、session；
- 启动参数包含：`--output-format stream-json`、`--input-format stream-json`、`--verbose`；
- 权限模式：yolo 时加 `--dangerously-skip-permissions`，否则加 `--permission-prompt-tool stdio`；
- `cp.spawn(executable, args, { cwd, stdio: ['pipe','pipe','pipe'], env })`；
- stdin 首先写 initialize control request；再写 user message JSON；
- stdout 按 `\n` 切分 JSONL，处理 `control_request`、`control_response`、`result` 和普通 stream event；
- 权限请求以 UI 卡片保存，用户允许/拒绝后通过 stdin 写 `control_response`；
- 取消用 AbortController + kill process group，先 SIGTERM 后超时 SIGKILL。

可借鉴：process bridge、stdout line buffer、permission request card、stop/cancel、session id resume。  
不可直接照搬：许可证为 NOASSERTION，且部分 CLI flag 需本机版本验证。

### 4.2 Codexia：Codex proto 快速桥接

`milisp/codexia-vscode` 观察点：

- `CodexService` 用 `spawn("codex", args, { cwd, stdio: ['pipe','pipe','pipe'], env })`；
- full config 下 args 来自 ConfigManager，然后追加 `proto`；
- stdout 按行切分并交给 event handler；
- sendMessage 写入 `{ op: { type: "user_input", items: [{ type: "text", text }] } }`；
- 支持 `exec_approval`、`patch_approval`、`interrupt`；
- 配置包括 `model`、`reasoning`、`provider`、`approvalPolicy`、`sandboxMode`；
- full access 对应方向是 `approval_policy=never` + `sandbox_mode=danger-full-access`。

可借鉴：最小 Codex bridge、模型/权限/sandbox 配置映射。  
更推荐：官方 app-server，因为协议更完整，有 thread/list、turn/start、model/list、approval、command/exec 等。

### 4.3 Cline：完整对话应用不是“聊天框”

`cline/cline` 的 `ExtensionState` 包含：

- `apiConfiguration`、`autoApprovalSettings`、`browserSettings`；
- `mode`；
- `clineMessages`；
- `taskHistory`；
- checkpoint 状态；
- terminal 设置、background command 状态；
- workspace roots / multi-root workspace；
- MCP marketplace/display；
- favorited models；
- rules/workflows/skills toggles；
- native tool call / parallel tool call 等设置。

`ClineMessage` 结构不是单纯 role/content：

- `type: ask | say`；
- `ask`: followup、plan/act respond、command、command_output、completion_result、tool、api_req_failed、resume_task、browser_action、use_mcp_server、new_task、condense、summarize_task、subagents 等；
- `say`: task、error、api_req_started/finished/retried、text、reasoning、completion_result、command、command_output、tool、browser、mcp、diff_error、checkpoint_created、info、task_progress、hook、subagent 等；
- 附带 images、files、partial、commandCompleted、checkpoint hash、conversationHistoryIndex、modelInfo。

对 ClaudeMac 的影响：我们需要设计“事件/消息统一模型”，不能只存 user/assistant 两种字符串。

### 4.4 Roo Code：状态分类和上下文压缩

`Roo-Code` 把 ask/say 进一步分类：

- interactive asks：followup、command、tool、use_mcp_server；
- idle asks：completion_result、api_req_failed、resume_completed_task、mistake_limit_reached、auto_approval_max_req_reached；
- resumable asks：resume_task；
- non-blocking asks：command_output；
- say 类型覆盖 api retry/rate limit、reasoning、command_output、MCP、checkpoint、diff_error、context condensation、sliding window truncation、tool。

对 ClaudeMac 的影响：UI 状态机需要区分“等待用户批准”“正在生成”“已完成”“失败可重试”“可恢复”“非阻塞输出”。

### 4.5 Continue：通用 IDE 协议能力

`continuedev/continue` 的协议说明完整 AI IDE 面板还应包括：

- history/list、history/load、history/save、history/delete、history/share、history/clear；
- config/addModel、config/updateSelectedModel；
- context/getContextItems、context/loadSubmenuItems；
- mcp/reloadServer、mcp auth；
- tools/call、tools/evaluatePolicy、tools/preprocessArgs；
- process/markAsBackgrounded、process/isBackgrounded、process/killTerminalProcess；
- models/fetch；
- terminal command tool 默认 policy 是 `allowedWithPermission`，并有 timeout、background process、partial output 管理。

对 ClaudeMac 的影响：最小版可以不做所有功能，但协议和数据模型必须预留 history/config/context/tools/process/models 几类边界。

## 5. ClaudeMac 目标产品定义

### 5.1 非目标

- 不做完整 Cline/Roo/Continue 级 agent 平台。
- 不复制第三方源码或 UI。
- 不在第一版实现浏览器自动化、MCP marketplace、插件市场、云同步、多 agent/subagent。
- 不默认开启完全访问权限。

### 5.2 第一版必须支持

1. 右侧对话面板取代 Terminal 启动主路径。
2. 输入框下方选择：
   - CLI：Claude Code / Codex；
   - 模型：按 CLI 区分；
   - 权限：默认 / 自动编辑或自动批准 / 完全访问。
3. 新会话默认创建新对话。
4. 支持流式输出。
5. 支持停止当前响应。
6. 支持权限请求卡片：允许、拒绝、始终允许当前模式内同类操作。
7. 支持命令/工具输出折叠展示。
8. 支持错误和重试。
9. 支持按项目存储会话元信息。
10. 保留“外部终端打开”作为 fallback，而不是主入口。

### 5.3 第二版再做

- 文件/图片附件；
- `@file`/`@selection`/`@folder` mentions；
- diff 预览；
- 会话搜索、分叉、恢复；
- token/context 指示器；
- MCP server 状态；
- checkpoint / rollback；
- 多会话 tab。

## 6. 信息架构与 UI 设计

### 6.1 面板结构

```text
┌────────────────────────────────┐
│ Header                         │
│ Claude / Codex conversation    │
│ 当前项目名 · 状态 · 新建/历史   │
├────────────────────────────────┤
│ Transcript                     │
│ - User bubble                  │
│ - Assistant markdown           │
│ - Reasoning collapsed          │
│ - Tool / command cards         │
│ - Permission request card      │
│ - Error / retry card           │
│ - Result summary               │
├────────────────────────────────┤
│ Composer                       │
│ multiline input                │
│ [CLI] [Model] [Permission]     │
│ [Attach] [Stop/Send]           │
└────────────────────────────────┘
```

### 6.2 输入框下方控制区

| 控件 | Claude Code 映射 | Codex 映射 |
| --- | --- | --- |
| CLI Picker | `claude` backend | `codex app-server` backend |
| Model Picker | `--model` 或 settings `model` | `thread/start.model` / `turn/start.model` / config model |
| Permission Picker: 默认 | `--permission-mode default` | `approvalPolicy=on-request` + sandbox/workspace |
| Permission Picker: 自动编辑 | `--permission-mode acceptEdits` 或 auto | `approvalPolicy=on-failure/on-request` + workspace-write |
| Permission Picker: 完全访问 | `--permission-mode bypassPermissions` 或兼容 `--dangerously-skip-permissions` | `approvalPolicy=never` + `sandbox=dangerFullAccess` |

UI 文案建议：

- 默认：执行命令/写文件前询问。
- 自动编辑：允许普通编辑，危险操作仍需确认。
- 完全访问：跳过大多数确认，可能修改/删除文件或执行命令；仅在可信项目使用。

### 6.3 消息类型

Swift 层建议定义统一模型，而不是直接暴露 Claude/Codex 原始 JSON：

```swift
enum ChatMessageKind: String, Codable {
    case user
    case assistant
    case reasoning
    case toolCall
    case toolResult
    case command
    case commandOutput
    case permissionRequest
    case diff
    case error
    case system
    case result
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let sessionId: UUID
    var providerMessageId: String?
    var timestamp: Date
    var kind: ChatMessageKind
    var status: ChatMessageStatus
    var text: String
    var metadata: ChatMessageMetadata
}
```

### 6.4 状态矩阵

| 状态 | UI 表现 | 后端动作 |
| --- | --- | --- |
| idle | 输入可编辑，Send 可点 | 无进程或进程空闲 |
| starting | 显示“正在启动 Claude/Codex” | spawn process / initialize |
| streaming | Stop 可点，输入可暂存 | 读取 stdout JSONL |
| waitingPermission | 显示权限卡片，Send 禁用或允许追加 steer | 等待用户 allow/deny |
| stopping | Stop disabled，显示停止中 | interrupt / SIGTERM |
| completed | 显示 usage/result | 保存 session |
| failed | 显示错误 + retry | 保留 stderr/exit code |
| recoverable | 显示“恢复会话” | resume thread/session |
| unsupportedVersion | 显示升级/降级方案 | fallback Terminal 或提示安装 |

## 7. 后端架构

### 7.1 核心类型

```swift
enum ChatCLI: String, Codable, CaseIterable {
    case claudeCode
    case codex
}

enum ChatPermissionMode: String, Codable, CaseIterable {
    case ask
    case autoEdit
    case fullAccess
}

struct ChatRunOptions: Codable {
    var cli: ChatCLI
    var model: String
    var permissionMode: ChatPermissionMode
    var projectPath: String
    var sessionMode: SessionMode
    var resumeId: String?
}

protocol ChatProcessBackend {
    func start(options: ChatRunOptions) async throws
    func send(_ message: String) async throws
    func approve(_ requestId: String, behavior: PermissionBehavior) async throws
    func interrupt() async
    func stop() async
    var events: AsyncStream<ChatEvent> { get }
}
```

### 7.2 ClaudeCodeProcessBackend

建议启动参数第一候选：

```bash
claude -p \
  --output-format stream-json \
  --input-format stream-json \
  --verbose \
  --permission-mode <default|acceptEdits|auto|bypassPermissions> \
  --model <opus|sonnet|...>
```

兼容候选：

```bash
claude \
  --output-format stream-json \
  --input-format stream-json \
  --verbose \
  --permission-prompt-tool stdio
```

必须实测：

1. 是否必须带 `-p`；
2. stdin 是否可在一个进程内多轮写入；
3. `--permission-prompt-tool stdio` 是否在当前版本存在；
4. `bypassPermissions` 与旧 `--dangerously-skip-permissions` 的兼容关系；
5. `--resume` 与 stream-json 输入能否共用。

Claude 事件适配：

| 原始事件 | 统一事件 |
| --- | --- |
| assistant text delta | `.messageDelta` |
| tool_use / tool_result | `.toolStarted/.toolCompleted` |
| control_request can_use_tool | `.permissionRequested` |
| control_response | `.permissionResolved` |
| result | `.completed` |
| stderr/exit nonzero | `.failed` |

### 7.3 CodexProcessBackend

优先 app-server：

```bash
codex app-server --listen stdio://
```

初始化：

```json
{ "method": "initialize", "id": 1, "params": { "clientInfo": { "name": "claudemac", "title": "ClaudeMac", "version": "0.1.0" } } }
```

新会话：

```json
{ "method": "thread/start", "id": 2, "params": { "model": "gpt-5.1-codex", "cwd": "/path/to/project", "approvalPolicy": "on-request", "sandbox": "workspaceWrite" } }
```

发送消息：

```json
{ "method": "turn/start", "id": 3, "params": { "threadId": "thr_x", "input": [{ "type": "text", "text": "...", "text_elements": [] }] } }
```

停止：

```json
{ "method": "turn/interrupt", "id": 4, "params": { "threadId": "thr_x", "turnId": "turn_x" } }
```

模型列表：

```json
{ "method": "model/list", "id": 5, "params": { "includeHidden": false } }
```

权限映射：

| UI 模式 | Codex 参数 |
| --- | --- |
| 默认 | `approvalPolicy: "on-request"`, `sandbox: "workspaceWrite"` |
| 自动编辑 | `approvalPolicy: "on-failure"`, `sandbox: "workspaceWrite"` |
| 完全访问 | `approvalPolicy: "never"`, `sandbox: "dangerFullAccess"` |

如果 app-server 不可用，fallback：

```bash
codex -c model="gpt-5" -c approval_policy=never -c sandbox_mode=danger-full-access proto
```

但 fallback 只作为兼容策略，不作为最终架构。

## 8. 文件/模块建议

建议新增：

```text
ClaudeMac/Models/ChatModels.swift
ClaudeMac/ViewModels/ChatPanelState.swift
ClaudeMac/Services/Chat/ChatProcessBackend.swift
ClaudeMac/Services/Chat/ClaudeCodeProcessBackend.swift
ClaudeMac/Services/Chat/CodexAppServerBackend.swift
ClaudeMac/Services/Chat/JSONLStreamReader.swift
ClaudeMac/Services/Chat/ChatSessionStore.swift
ClaudeMac/Views/Chat/ChatPanelView.swift
ClaudeMac/Views/Chat/ChatTranscriptView.swift
ClaudeMac/Views/Chat/ChatMessageRow.swift
ClaudeMac/Views/Chat/ChatComposerView.swift
ClaudeMac/Views/Chat/PermissionRequestCard.swift
ClaudeMac/Views/Chat/ToolEventRow.swift
ClaudeMac/Views/Chat/CommandOutputRow.swift
ClaudeMac/Views/Chat/DiffSummaryRow.swift
```

建议保留并降级：

```text
ClaudeMac/Services/TerminalLauncher.swift  // fallback only
ClaudeMac/Views/ClaudeSessionPanelView.swift // 被 ChatPanelView 替换或重命名
```

## 9. 存储设计

会话元信息：

```swift
struct ChatSessionRecord: Identifiable, Codable {
    let id: UUID
    var providerThreadId: String?
    var cli: ChatCLI
    var model: String
    var permissionMode: ChatPermissionMode
    var projectId: UUID
    var projectPath: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var status: ChatSessionStatus
    var tokenUsage: ChatTokenUsage?
}
```

消息存储：

```text
~/Library/Application Support/ClaudeMac/chat-sessions.json
~/Library/Application Support/ClaudeMac/chat-messages/<session-id>.jsonl
```

存储原则：

- 本地存储，不上传；
- 只存 UI 需要的 normalized events；
- 原始 JSON 可选 debug 模式保存，默认关闭；
- stderr/错误摘要可保存，避免保存敏感完整环境变量；
- session list 按项目过滤。

## 10. 权限与安全

### 10.1 完全访问权限

必须显式用户选择，不默认开启。UI 必须提示：

- Claude：`bypassPermissions` / `--dangerously-skip-permissions` 会减少确认；
- Codex：`approvalPolicy=never` + `dangerFullAccess` 会放开 sandbox；
- 完全访问可能执行 shell、写文件、删除文件、联网；
- 建议仅在可信目录使用。

### 10.2 macOS sandbox 影响

ClaudeMac 自身是 sandbox app。外部 CLI 子进程文件访问可能受以下因素影响：

- App sandbox 对子进程继承限制；
- security-scoped bookmark 只保证 App 访问，不一定等价于 CLI 完整 shell 环境；
- Claude/Codex 自己的权限模式和 sandbox 也会约束；
- 如果子进程无法访问项目目录，需要验证是否要用 `/usr/bin/env`、shell wrapper、或改 entitlements。

必须把“进程能否在 selected project cwd 读写文件”作为第一个本机验证。

### 10.3 危险动作 UI

权限卡片必须展示：

- tool name；
- 命令或文件路径；
- 操作类型：读/写/删除/执行/联网；
- cwd；
- allow / deny；
- full access 模式下是否被自动允许；
- 日志中保留 decision。

## 11. 事件解析策略

### 11.1 JSONLStreamReader

要求：

- 按 bytes 读取 stdout/stderr；
- UTF-8 安全拼接；
- 按 newline 切分；
- 保留 incomplete line；
- 每行独立 JSON decode；
- decode 失败转 `.rawOutput` 或 `.parseError`；
- stderr 与 stdout 分通道记录；
- 进程 exit 后 flush buffer。

### 11.2 不可阻塞 MainActor

- `Process` 启动、pipe 读取、JSON decode 放后台 actor/task；
- UI 更新通过 MainActor 合并；
- streaming delta 做 throttle，避免每个 token 都触发 SwiftUI 大刷新；
- Stop 必须能取消当前 reader 和 process。

## 12. 开发切片

### Slice 0：本机能力探针

目标：不改 UI，验证 CLI 是否可控。

- `which claude`, `claude --version`；
- `which codex`, `codex --version`；
- Claude stream-json 最小输入输出；
- Claude permission/fullAccess flag 可用性；
- Codex app-server initialize/thread/start/turn/start；
- 子进程 cwd 能否访问用户选中的 project path。

产物：`ChatCLICapabilityProbe` 或临时命令记录。

### Slice 1：Claude Code MVP

目标：右侧可直接对话。

- 新建 ChatPanelView；
- 输入框 + CLI/model/permission pickers；
- Claude backend；
- user/assistant/error/loading/stop；
- 默认 new session；
- Terminal 按钮移到 fallback。

### Slice 2：权限卡片和工具输出

- 解析 permission request；
- 显示 command/tool card；
- allow/deny 写回 stdin；
- command output 折叠；
- stderr 错误卡片。

### Slice 3：Codex app-server

- 初始化 app-server；
- thread/start；
- turn/start；
- turn/interrupt；
- model/list；
- approvalPolicy/sandbox 映射；
- fallback 到 `codex proto`。

### Slice 4：历史和恢复

- 存 session list；
- 存 message JSONL；
- 最近会话列表替换旧 launch history；
- Claude resume / Codex thread/resume；
- 新会话、继续、恢复明确分开。

### Slice 5：附件、diff、上下文

- `@file` 插入；
- 图片路径/附件；
- diff summary row；
- token/context 指示器；
- context compaction / truncation message。

## 13. 验证矩阵

| 维度 | 用例 | 证据 |
| --- | --- | --- |
| UI 主路径 | 选择项目，输入消息，Claude 流式回复 | 截图/录屏 |
| CLI 切换 | Claude/Codex 切换后模型列表变化 | 截图 + 日志 |
| 模型选择 | 选 sonnet/opus/gpt-5 后 backend 参数正确 | debug log |
| 权限默认 | 写文件/运行命令前出现权限卡片 | 截图 + stdout 原始事件 |
| 完全访问 | full access 下不反复询问，且 UI 有风险提示 | 截图 + 参数日志 |
| Stop | 生成中点击 Stop，进程/turn 被取消 | exit/interrupted event |
| 错误 | CLI 不存在、未登录、参数不支持 | 错误卡片 |
| 历史 | 新建、加载、恢复、删除会话 | 本地 JSON 文件 |
| 项目 cwd | CLI 在所选项目执行 pwd/read/write | 命令输出 |
| 主线程 | 长响应期间 App 不冻结 | Instruments 或手测录屏 |
| 边界 | stdout 半包、JSON parse error、stderr 大输出 | 单元测试 |
| 安全 | full access 不默认启用；危险动作需显式选择 | UI 状态检查 |

## 14. 测试建议

单元测试：

- JSONLStreamReader 半包、多行、非法 JSON；
- Claude event adapter；
- Codex JSON-RPC adapter；
- permission mode 参数映射；
- session store read/write/migration；
- message grouping / partial delta 合并。

集成测试：

- 用 mock process 输出固定 JSONL；
- send -> stdout delta -> completed；
- permission request -> approve/deny；
- interrupt；
- stderr + nonzero exit。

手工验收：

- 真实 Claude Code 对话；
- 真实 Codex app-server 对话；
- 权限请求；
- 完全访问风险提示；
- App 不冻结；
- 切换项目后 cwd 正确。

## 15. 风险与待验证项

1. Claude Code CLI 版本差异：stream-json 输入、stdio 权限响应、`-p` 是否必需需要本机实测。
2. Codex app-server 是否已安装在用户本机版本中；如果没有，需要 fallback 到 `codex proto` 或提示升级。
3. macOS App sandbox 下子进程读写项目目录的行为必须实测。
4. 完全访问权限风险大，不能默认启用，且需要 UI 明示。
5. 不应复制第三方仓库代码；只参考架构与类型设计。
6. App 当前没有测试 target，若新增解析器/状态机，建议同时加最小 XCTest。

## 16. 推荐最终技术路线

```text
RootView
└── ChatPanelView
    ├── ChatTranscriptView
    │   └── ChatMessageRow
    │       ├── AssistantMessageRow
    │       ├── ToolEventRow
    │       ├── PermissionRequestCard
    │       ├── CommandOutputRow
    │       ├── DiffSummaryRow
    │       └── ErrorRow
    └── ChatComposerView
        ├── TextEditor
        ├── CLI Picker
        ├── Model Picker
        ├── Permission Picker
        └── Send/Stop

ChatPanelState
└── ChatBackendFactory
    ├── ClaudeCodeProcessBackend
    └── CodexAppServerBackend
        └── JSONLStreamReader
```

第一版不要追求“完美兼容所有功能”，而是做到：

1. Claude Code 真对话；
2. Codex 预留并尽快接 app-server；
3. CLI/model/permission 在输入框下方；
4. 权限请求可视化；
5. 不再依赖 Terminal。

## 17. Sources

- Claude Code VS Code docs: https://code.claude.com/docs/en/vs-code
- Claude Code IDE integrations docs: https://code.claude.com/docs/en/ide-integrations
- Claude Code permission modes: https://code.claude.com/docs/en/permission-modes
- Claude Code settings: https://code.claude.com/docs/en/settings
- Claude Code CLI reference: https://code.claude.com/docs/en/cli-reference
- Claude Code headless / programmatic usage: https://code.claude.com/docs/en/headless
- `andrepimenta/claude-code-chat`: https://github.com/andrepimenta/claude-code-chat
- `openai/codex`: https://github.com/openai/codex
- Codex app-server README: https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md
- `milisp/codexia-vscode`: https://github.com/milisp/codexia-vscode
- `cline/cline`: https://github.com/cline/cline
- `RooCodeInc/Roo-Code`: https://github.com/RooCodeInc/Roo-Code
- `continuedev/continue`: https://github.com/continuedev/continue

## 18. 2026-05-08 实际实现记录

### 18.1 已落地文件

- `ClaudeMac/Models/ChatModels.swift`：统一 `ChatMessage`、`ChatSessionRecord`、`ChatRunOptions`、`ChatPermissionMode`、模型选项。
- `ClaudeMac/ViewModels/ChatPanelState.swift`：右侧对话状态机，覆盖 idle / starting / streaming / waitingPermission / stopping / completed / failed / unsupportedVersion。
- `ClaudeMac/Services/Chat/ChatCLICapabilityProbe.swift`：检测 Claude/Codex 可执行文件、版本、stream-json、resume、Codex app-server；GUI 环境下显式搜索 `/opt/homebrew/bin`、`/usr/local/bin` 并用 zsh fallback。
- `ClaudeMac/Services/Chat/ChatProcessBackend.swift`：统一 backend 协议和短命令 runner；为子进程注入 Homebrew PATH，避免 macOS GUI App 继承的 PATH 找不到 CLI。
- `ClaudeMac/Services/Chat/JSONLStreamReader.swift`：按 bytes 读取 pipe，按 newline 切分并 flush incomplete line。
- `ClaudeMac/Services/Chat/ClaudeCodeProcessBackend.swift`：通过 `Process + Pipe` 启动 `claude -p ... --output-format stream-json --verbose --permission-mode ...`，解析 `system / assistant / result / permission / tool / raw`。
- `ClaudeMac/Services/Chat/CodexAppServerBackend.swift`：实现 `codex app-server --listen stdio://` 启动、initialize、thread/start、turn/start、turn/interrupt、approval respond 的预留路径。
- `ClaudeMac/Services/Chat/ChatSessionStore.swift`：本地保存 `~/Library/Application Support/ClaudeMac/chat-sessions.json` 和 `chat-messages/<session-id>.jsonl`。
- `ClaudeMac/Views/ClaudeSessionPanelView.swift`：移除 preview 主路径，改为真实 `ChatPanelState` 数据源；Send 在 streaming 中变 Stop；权限卡片 allow/deny 写回 backend；默认权限为“询问”。
- `ClaudeMac/ViewModels/AppState.swift`：左侧历史合并 ClaudeMac 本地会话；删除本地会话时同步删除 store。
- `ClaudeMac/Services/CommandBuilder.swift`：Terminal fallback 改为安全默认，不再自动追加 `--dangerously-skip-permissions`。
- `ClaudeMac/ClaudeMac.entitlements`：补充 network client、Homebrew 只读临时例外、`.claude/.codex` 读写临时例外，保证 sandbox App 内 CLI 可联网和写本地会话。
- `ClaudeMac.xcodeproj/project.pbxproj`：新增 Swift 文件全部显式加入 target Sources。

### 18.2 本机 CLI 探针结果

- `claude`：`/opt/homebrew/bin/claude`，版本 `2.1.132 (Claude Code)`。
- `codex`：本机未找到，UI 会显示 “未找到 codex，请先安装或把它加入 PATH。”。
- Claude stream-json 最小探针已跑通：`claude -p "Reply exactly: OK" --output-format stream-json --permission-mode default --verbose` 返回 `system init`、`assistant`、`result`、`session_id`。
- 本次探针消耗一次真实 Claude Code 调用；输出显示 `total_cost_usd` 约 `0.149365`。

### 18.3 当前实现边界

- Claude 采用每次 send 启动一次 headless `-p` 进程；后续 turn 通过上一次 `session_id` 自动追加 `--resume`。
- `system init` 原始大 JSON 不展示到 UI，仅保留 `session_id`；stderr 会显示为命令输出行。
- Codex app-server 路径已实现但本机缺 CLI，未完成真实 E2E 验证。
- 权限请求解析和 allow/deny stdin 写回已接线，但 Claude `control_response` 具体字段仍需用真实权限请求样例复验。
- 目前无 XCTest target；JSONL 半包、adapter、store 仍是自动化测试缺口。
- macOS sandbox 下 Claude/Codex 子进程读写用户选择项目目录仍需 App 内手测确认。

### 18.4 已执行验证

- `xcodebuild -project ClaudeMac.xcodeproj -scheme ClaudeMac -configuration Debug build`：`BUILD SUCCEEDED`。
- `which claude; claude --version`：通过。
- `which codex; codex --version`：Codex 未安装。
- Claude stream-json 最小消息：通过。
- `ChatCLICapabilityProbe` 源码级探针：`claude|path=/opt/homebrew/bin/claude|version=2.1.132 (Claude Code)|error=nil`，`codex|path=nil|error=未找到 codex...`。
- `ClaudeCodeProcessBackend` 源码级真实对话探针：收到 `session_id`、`delta|assistant|OK`、`finished`，汇总 `assistant=true|finished=true`。
- 构建产物 entitlements 检查：Debug App 已包含 `network.client`、`/opt/homebrew/`、`/usr/local/`、`.claude/.codex` 权限。

### 18.5 下一步手测矩阵

- App 内选择项目后发送 Claude 消息，确认 UI 流式追加 assistant 行且 App 不冻结。
- 点击 Stop，确认进程结束且消息状态变为 stopped。
- 新建会话后左侧项目历史出现 ClaudeMac 本地会话，点击可加载消息。
- 删除 ClaudeMac 本地会话，确认 `chat-sessions.json` 和对应 JSONL 被清理。
- 触发一次需要写文件/执行命令的 Claude 请求，确认权限卡片和 allow/deny 行为。
- 安装 Codex 后复验 app-server initialize/thread/start/turn/start。
