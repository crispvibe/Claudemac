# 域 A 审计：连接 + 协议 + 错误处理

审计员：独立 QA / 域 A。**仅静态分析 + 在运行中的 Mac server 上做只读探测**，未改任何代码。所有探测脚本写在 `/tmp/audit_a_tests*.py` 和 `/tmp/smoke*.py`，使用 Python 标准库。

## TL;DR

1. **P0 — Server 没有 `commandId` 幂等去重**：iOS `replayPendingCommands` 在重连后会重发同 commandId 的未 ack 命令；实测 `newDraftSession` 用同 commandId 发 3 次会创建 3 个独立 session、3 个独立 ok ack。`composerSend` 同理可能让用户消息被发两次（`Codevoke/Services/RemoteChat/RemoteChatCommandRouter.swift:25-218` 无 dedup；iOS 重发逻辑 `CodevokeIOS/Codevoke/ViewModels/ChatViewModel.swift:696-708`）。
2. **P0 — `remoteComposerSend` 空 composer 走 500ms 兜底，但同步 ack 返回 `rejected`**：iOS `handleAck` 直接把 reject message 写进 `lastError` 让用户看到弹窗式错误，即使 0.5s 后实际成功（`PanelStateBroadcasterAdapter.swift:207-257`、`ChatViewModel.swift:684-688`）。
3. **P1 — 默认 focus=nil 的连接收"所有 session"广播**：`RemoteChatServer.broadcastVNCEnvelope` 的过滤逻辑 `state.focusedSessionID != envelope.sessionId, state.focusedSessionID != nil` 在 focus 为 nil 时不过滤；多 session 并发时会泄漏其它 session 的 patch 给一个未聚焦的连接（`RemoteChatServer.swift:411`）。
4. **P1 — 重连退避无指数策略 + 不区分错误类型**：iOS 固定 1.5s 重试，不区分 401 / DNS 失败 / 拒连，401 会无限循环（`ChatViewModel.swift:774-781`、`RemoteWebSocketClient.swift:208-214`）。
5. **P1 — HTTP server 没有读超时 + body 缓冲 64MB**：单连接 `Content-Length: 70MB` + 慢速发送即可让 server pin 一条 socket，且累计 buffer 上限为 `RemoteChatHTTPCodec.maxRequestBytes = 64MB`，对带 token 攻击者形成 DoS 窗口（`RemoteChatServer.swift:185-225`、`RemoteChatHTTP.swift:68`）。

## 场景覆盖矩阵

| # | 场景 | 静态分析结论 | 实测结果 | 严重度 | path:line 证据 |
|---|------|-------------|---------|------|---------------|
| 1 | 首次冷启动无 host/token | UserDefaults 缺省 host=127.0.0.1 port=18765 token 空；空 token 时自动弹设置 sheet | 未实测 UI | P2 | `ChatViewModel.swift:109-117` |
| 2 | host/port 错（连接超时） | 错误经 `URLSessionWebSocketTask` → `onDisconnect` → `scheduleReconnect` 1.5s 后重试，不退避 | 未实测网络层 | P1 | `RemoteWebSocketClient.swift:208-214`,`ChatViewModel.swift:774-781` |
| 3 | token 错 → 401 | 实测 401 含明确 message；iOS 走 `onDisconnect` 走 1.5s 循环重连，**永不停**，UI 只显示"未连接" | 实测：bad token 返回 `401 {"error":"unauthorized"}`，但 iOS 没有终止重连 | **P1** | server `RemoteChatServer.swift:232-234`；iOS 无 401 终止 `ChatViewModel.swift:752-762` |
| 4 | iOS 进入后台 → suspend | `ChatView.scenePhase == .background` → `suspendForBackground` → `disconnect(notify:false)`；OK | 静态 OK | P2 | `ChatView.swift:99-102`,`ChatViewModel.swift:153-160` |
| 5 | iOS 回前台 → 重连 | `scenePhase == .active` → `reconnectIfNeeded`；OK | 静态 OK | P2 | `ChatView.swift:90-98`,`ChatViewModel.swift:146-150` |
| 6 | WiFi 切换 / 抖动 | 与场景 2 同；固定 1.5s 重连，不区分原因，没有抖动节流 | 未实测 | P1 | `ChatViewModel.swift:774-781` |
| 7 | Mac server 重启（serverEpoch 换） | iOS 没有 `serverEpoch` 概念；reconnect 时带 stale `lastRevision` 给新 server，server `patchesSince` 用 `lastRevision > currentRevision` 落到 fall-through 发 fresh snapshot；iOS mirror 覆盖。**OK，但 pendingCommands 会全部 replay** → 重启场景下严重副作用见 P0-1 | 部分实测；replay 副作用见 #15 | P0（关联） | `PanelStateBroadcaster.swift:194-200`，`ChatViewModel.swift:696-708` |
| 8 | Mac 关机后 iOS 操作 | `sendCommand` 不会 throw；iOS `webSocketClient?.sendCommand` 静默失败，pendingCommands 累积；上限 200 条 | 静态 | P1 | `ChatViewModel.swift:653-672`，`pendingCommandLimit=200:98` |
| 9 | NWListener 端口被占 | `start()` throw → `RemoteChatServerController.lastError` 存字符串；UI 在 SettingsPageView 显示。OK 但简略 | 未实测 | P2 | `RemoteChatServerController.swift:45-55` |
| 10 | 同 token 多设备并发 | 5 个连接均独立收到 `panel_state`；广播按 `focusedSessionID` 过滤。**但 focus=nil 的连接会拿到所有 session 的 envelope，参见 #18** | 实测 OK，但有泄漏点 | P1 | `RemoteChatServer.swift:405-417` |
| 11 | 长时间空闲 ping/pong | iOS 每 20s 主动 sendPing；server `decodeFrames` 收到 `.ping` 回 pong；OK。**但 server 自身不发 ping 探活半死连接** | 静态 + ping 路径 OK | P2 | `RemoteWebSocketClient.swift:42-44,113-138`，server 无主动 ping `RemoteChatServer.swift:294-296` |
| 12 | 帧分段大（>1MB snapshot） | server `decodeFrames` 硬上限 1MB（throws `payloadTooLarge`）；客户端发 1.5MB 时 server 关连接但 **没有发 `assistant_error` 帧**，iOS 只看到 disconnect | 实测：发 1.5MB 后 server 关连接、iOS 看不到原因 | P1 | `RemoteChatWebSocket.swift:78-86`，`RemoteChatServer.swift:310-316` |
| 13 | iOS 收到 patch 但 baseRevision 不匹配 | `PanelStateMirror.apply(patch:)` 校验 `base.revision == patch.baseRevision`，不匹配 return nil；ChatViewModel `handleEnvelope` 收到 nil → `sendCommand(.requestSnapshot)`。**没有计数器/死循环防护** | 静态 | P2 | `PanelStateMirror.swift:62-94`，`ChatViewModel.swift:789-797` |
| 14 | baseRevision 在保留窗口外（128 patch） | server `patchesSince` 在 `oldestRetainedBaseRevision > lastRevision` 时 return nil → `replayPayload` 退化为 snapshot；OK 链路 | 静态 OK | P2 | `PanelStateBroadcaster.swift:194-200,348-363` |
| 15 | ack 不回 → pending 重发 / 重复执行 | **server 无 commandId dedup**。iOS 用同 commandId 重发同一命令，server 每次都执行：实测同 commandId `newDraftSession` × 3 → 创建 3 个 session、3 个独立 sessionId | 实测确认 | **P0** | `RemoteChatCommandRouter.swift:25-218`（无 dedup），`ChatViewModel.swift:696-708`（重发） |
| 16 | focusSession 不存在的 sessionId | `lookupController(for: target)` 返回 nil → reject 带 message `"session not found"`；iOS 把 message 写进 lastError | 实测：返回 `rejected` "session not found" | P2 | `RemoteChatCommandRouter.swift:32-34`，iOS `ChatViewModel.swift:684-688` |
| 17 | newDraftSession 后 focus 中间 controller 销毁 | runtime 拿到 controller，alloc UUID 返 ack；下一帧 client focus 时 `RuntimeStorePanelControllerLookup.controller(for: sid)` 重新查；若已销毁会 return nil → reject。**但同步竞态没有显式重试** | 静态 | P2 | `PanelStateBroadcasterAdapter.swift:385-390` |
| 18 | RemoteVNCWiring.install 未完成时收 VNC | 已修：`lookupResolver` 改为 closure 每次读 `RemoteVNCWiring.lookup`，避免 stale。修补到位 | 静态确认修好 | — | `RemoteChatServer.swift:62-71`，`PanelStateBroadcaster.swift:258-270` |
| 19 | resume `cursor != nil && lastRevision != nil` | 实测：server 走 legacy（cursor 非 nil → isVNC=false），iOS 永远不会发出这种帧，但容错语义需要文档 | 实测：返回 legacy event 流，无 panel_state | P2 | `RemoteChatServer.swift:506-527` |
| 20 | 旧 iOS legacy send_message | Bridge 把它翻译给 `ChatPanelController.sendFromComposer`。实测在 VNC-mode 连接发 `send_message` 也会被处理 → 服务器产出 VNC 帧 panel_state。**但 Bridge 不发 legacy `command_ack`，老 iOS 不知道结果** | 实测 | P2 | `RemoteChatBridge.swift:164-263` |
| 21 | Command.args 字段缺失/类型错 | Codable 严格 decode 失败 → server 发 `assistant_error` 事件并 close；**这是 legacy `RemoteChatStreamEvent` 帧，VNC iOS 客户端只看 type 标签会忽略** | 实测：`{"type":"command"}` → `assistant_error` 但 iOS 直接 drop | P1 | `RemoteChatServer.swift:451-455,636-646`，iOS `RemoteWebSocketClient.swift:202-205` |
| 22 | /projects/{id}/files 大目录 | `prefix(200)` 截顶 → 安全；但目录超过 200 没有翻页 | 静态 | P2 | `RemoteChatRouter.swift:291` |
| 23 | /files path 含 ../ 或绝对路径 | `sanitizedRelativePath` 过滤 `..` 和 `.`，并 `resolvingSymlinksInPath` 做 isURL check；实测 `path=../../../etc` 返 `directory_not_found`（`..` 已被剔），`%2e%2e/%2e%2e` 解码后同样剔。**没有目录穿越** | 实测安全 | — | `RemoteChatRouter.swift:352-357,443-449` |
| 24 | POST /attachments 超大文件 | 没有显式 per-file 限制；buffer 上限只受 `maxRequestBytes=64MB` 制约。每个 upload 落到 `tmp/CodevokeRemoteChatAttachments/<uuid>/`，**从不清理**；带 token 的人能慢慢把磁盘灌满 | 实测 5MB OK，70MB Content-Length 让 server 卡读 | P1 | `RemoteChatRouter.swift:157-177`，无清理 |
| 25 | legacy /events 等 endpoint 是否还被 iOS 调 | iOS `RemoteHTTPClient` 不再调 `/events` `/projects` `/sessions` `/models` 等；但 server 仍 serving。冗余代码面 | 实测：`/events` 仍 200 | P2 | `RemoteChatRouter.swift:108-141`；iOS 只调 `/health`,`/projects/<id>/files`,`/attachments`,`/config/*` (`RemoteHTTPClient.swift:24-57`) |
| 26 | HTTP token 变（外部改 settings） | iOS HTTP token 来自 `RemoteChatConfig`；server token 用启动时快照。**server 不监听 settings.json 变化**；用户在 Mac UI 改 token 必须手动 `restart()` | 静态 | P2 | `RemoteChatServerController.swift:38-43,80-87` |
| 27 | WS 连上后 token rotate | 已连 WS 不重新校验 token；下次重连用新 token。OK 设计 | 静态 OK | — | `RemoteChatServer.swift:232-238` |
| 28 | settings.json token 被清空 | `RemoteChatServerController.startIfNeeded` 在空 token 时调 `generateToken()` 写回；`savedToken()` 同样兜底。无 race（启动单线程） | 静态 OK | — | `RemoteChatServerController.swift:33-36,71-77` |

## P0 发现（必须修）

### P0-1 — Server 缺 commandId 幂等去重，重连重发会重复执行

**现象**：iOS 在 reconnect 后调 `replayPendingCommands`，把所有未 ack 的命令带原 commandId 重发。Server 没有任何 dedup 表，每次都把它当成新的 op 执行。

**实测**（`/tmp/smoke2.py`）：
```
ack: cid=D49F6593-... sessionId=19B448AA-...
ack: cid=D49F6593-... sessionId=173A8DE6-...
ack: cid=D49F6593-... sessionId=82FF52AF-...
```
同一个 commandId 收到 3 个 ok ack、3 个独立 sessionId。

**根因**：`Codevoke/Services/RemoteChat/RemoteChatCommandRouter.swift:25-218` 全程没有 commandId 缓存。`Codevoke/Services/RemoteChat/RemoteChatServer.swift:442-477` `handleVNCCommand` 也无 dedup。iOS replay 见 `CodevokeIOS/Codevoke/ViewModels/ChatViewModel.swift:696-708`。

**最严重的具体后果**：
- `composerSend`：用户消息可能被发送两次（ack 在飞行中丢包 → reconnect → replay → 服务端再次 sendFromComposer）。
- `newDraftSession`：每次 replay 都创建新的 draft；前面的 session 变孤儿，且 iOS 还以为只创建了一个。
- `cancelQueued` / `editQueued`：第一次成功后队列已变，第二次执行可能影响错误的 entry（虽然 requestId 帮一点忙）。

**建议**：server 端持一个 LRU `[UUID: CachedAck]`（512 容量、5 分钟 TTL）。`handleVNCCommand` 入口先查表；命中且 ack 已生成则直接 resend cached ack，跳过 route。spec §4.5 实际上要求"commandId 幂等"，目前是协议合规漏洞。

### P0-2 — `remoteComposerSend` 空 composer 兜底返回 false，但 iOS 把 reject 当真实错误展示

**现象**：server 收 `composerSend` 时若 `composerText` 为空（client `composerSet → composerSend` 拆两条命令且 server 还没消费第一条），会调度一个 500ms 后的重试 Task，但**同步立即** return `false` → router 走 `reject(command, reason: "send rejected (composer empty or capability check failed)")`。

iOS `handleAck` 把 `ack.message` 直接写进 `lastError`：
```swift
if ack.status == .error || ack.status == .rejected {
    if let msg = ack.message, !msg.isEmpty { lastError = msg }
}
```
UI（`shouldShowDebugLog`、`SettingsView` 等）依赖 `lastError != nil` 触发错误展示。

**用户感受**：每次"发送消息"按钮按下，约 0.5s 内成功显示消息，**同时**也会看到一行刺眼的红色"send rejected (composer empty or capability check failed)"。延迟重试的成功路径无后续 ack 通知客户端"现在好了"。

**根因**：`Codevoke/Services/RemoteChat/PanelStateBroadcasterAdapter.swift:246-256`、`CodevokeIOS/Codevoke/ViewModels/ChatViewModel.swift:684-688`。

**建议**：要么 (a) server 在重试 path 上等待 500ms 再发 ack（让 ack 反映最终结果），要么 (b) router 在已知 race-tolerant op 上区分"deferred"状态、不发同步 reject，要么 (c) iOS 区分技术性 reject 与可重试 reject 不弹给用户。任一即可，目前是最影响用户感受的体验 bug。

## P1 发现（应该修）

### P1-1 — focus=nil 的连接收所有 session 的 envelope（多 session 泄漏）

`Codevoke/Services/RemoteChat/RemoteChatServer.swift:411`：
```swift
if state.focusedSessionID != envelope.sessionId, state.focusedSessionID != nil { continue }
```
当 `focusedSessionID == nil`（iOS 在发 focusSession 之前的窗口，或主动 `resume` `sessionId: nil`），所有 session 的 envelope 都会被发到该连接。当前实测因为 broadcaster 只 attach 了一个 controller（iOS 没切 session 不会触发其它 controller 的 attach），所以暴露面有限；但 Mac 端只要在多 session 间切换 UI、`runtimeStore.controller(for:)` 把多个 controller attach 到 broadcaster，每个新 envelope 都会发给这个 iOS。

**建议**：把"未聚焦"语义改为"只发 draft sentinel"。spec 在 `PanelSessionRevisionLog.draftSessionKey` 暗示了这件事，但实际广播没区分。

### P1-2 — iOS 重连退避固定 1.5s，不区分错误类型，401 无限循环

`CodevokeIOS/Codevoke/ViewModels/ChatViewModel.swift:774-781`：
```swift
private func scheduleReconnect(generation: Int) {
    Task { [weak self] in
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard let self, self.webSocketGeneration == generation else { return }
        self.ensureWebSocketConnected(reason: "auto reconnect")
    }
}
```
- 没有 401/403/连接被拒绝/DNS 失败的分类。
- token 错了之后会以 1.5s 节奏永久重连，每次 server 都打 401 日志（实测 `/chat` 返 `HTTP/1.1 401 Unauthorized`），但 `RemoteWebSocketClient.fail` 只把 `Error` 透出，没有解析 HTTP 上行码（URLSessionWebSocketTask 在握手失败时通常透传 URLError，但 cancellation 标记是 `goingAway`，错误细节模糊）。
- 进入"飞机模式"等离线状态时同样 1.5s 节奏，反复 wakeup 网络层。

**建议**：(a) 取首次失败的 NSError → 区分 `cannotConnectToHost` / `notConnectedToInternet` / `timedOut` vs `userAuthenticationRequired`；(b) 401 后停止自动重连并把 token 错误展示给用户；(c) 退避用 1.5 → 3 → 6 → 12 → 30 上限。

### P1-3 — HTTP server 无读超时 + 64MB body buffer

`Codevoke/Services/RemoteChat/RemoteChatServer.swift:185-225`：`receiveRequest` 用 `connection.receive(minimumIncompleteLength: 1, maximumLength: 64MB)` 递归累计直到拿到 Content-Length 全量。**没有 deadline、没有空闲超时**。带合法 token 的客户端只要慢慢发即可让一条 socket 长期占用并让 server 累计最多 64MB buffer。

实测：`Content-Length: 70000000` 发了几十字节后，连接 hang 直到客户端 close。

**建议**：(a) HTTP-readtimeout 30s；(b) `maxRequestBytes` 降到 16MB；(c) 附件单独走 streaming endpoint，不 base64。

### P1-4 — 大附件 / 大文件树等无清理

`Codevoke/Services/RemoteChat/RemoteChatRouter.swift:167-173`：附件落到 `FileManager.default.temporaryDirectory + CodevokeRemoteChatAttachments/<uuid>/`，**没有任何 GC**。`tmp` 由 macOS 偶发清理但生命周期没有保证。`/projects/{id}/files` 一次最多 200 entries，没翻页；大目录的用户看不到 200 以外的文件且没提示。

**建议**：(a) 启动时清空 `CodevokeRemoteChatAttachments`；(b) 文件列表加 `truncated` 字段；(c) 每个 upload 写 sidecar 加上时间戳供 GC。

### P1-5 — Decode 失败用 legacy `assistant_error` 帧，VNC iOS 静默忽略

`Codevoke/Services/RemoteChat/RemoteChatServer.swift:451-455,636-646`：command frame decode 失败时发 `RemoteChatStreamEvent(type: "assistant_error", ...)`。iOS `RemoteWebSocketClient.handle` 见到非 `panel_state`/`command_ack`/`hello` 全部 drop（`RemoteWebSocketClient.swift:202-205`）。**用户/调试日志看不到"是哪个 command 解码失败"**。

**建议**：用 `CommandAck(commandId: ?, status: .error, message:...)` 表达，commandId 若拿不到就用 `UUID()`，iOS 至少能看到 status=error。

### P1-6 — 1MB frame 上限触发后 server 关连接但 iOS 看不到原因

`RemoteChatWebSocket.swift:78-86` throws `payloadTooLarge` → `decodeFrames` 调用方 catch → `sendWebSocketError("websocket_decode_failed", ...)` 之后 `sendWebSocketData(encodeClose)` → close。但 iOS `RemoteWebSocketClient` 的 close 处理只是 disconnect，没有显示具体 close code/reason。**用户只看到"未连接"**。

**建议**：发 close 时携带 RFC 6455 close code（1009 = message too big）；iOS 在 `onDisconnect` 显示 close reason。

### P1-7 — Server 不区分 401 vs 协议错误的关闭原因

`RemoteChatServer.swift:232-234` 在 token 错时返 HTTP 401 + body 后 `connection.cancel()`；iOS 的 URLSessionWebSocketTask 在握手失败收到 `URLError.userAuthenticationRequired`，但 iOS 没有解析这个，scheduleReconnect 会立刻再来一次。（与 P1-2 互补，应同步修。）

## P2 发现（可选）

### P2-1 — 不接收 unmasked client→server 帧的 RFC 6455 合规

RFC 6455 §5.1：client→server 帧 MUST 加 mask；否则 server MUST 关闭。实测 `RemoteChatWebSocket.decodeFrames`（`RemoteChatWebSocket.swift:62-95`）只读 mask bit 决定要不要 XOR，**不拒绝 unmasked**。实测连接成功 resume。**不是安全问题**（mask 只为防代理误解析），但代理/防火墙若严格按 RFC 校验可能掐连接。

### P2-2 — `composerSetCLI` 拒未知 CLI，但 `modelsResponse` 对未知 CLI 静默 fallback 到 claude

`RemoteChatCommandRouter.swift:66-74` vs `RemoteChatRouter.swift:148-155`。一边严格、一边宽松。统一一下。

### P2-3 — Bridge 的 legacy `send_message` 不回 legacy `command_ack`

`RemoteChatBridge.swift:214-263` 翻译完 send_message 后只在错误时发 `assistant_error`，正常情况下啥都不回。老的 iOS 客户端只能等 `command_ack` 才能 settle 队列。不是新 iOS 的问题但 Phase B 兼容性有缺口。

### P2-4 — Server 自己不主动 ping，半死连接靠 iOS 20s 主动 ping 探测

`RemoteChatServer.swift:294-296` 只回 pong，不主动发 ping。结合 `keep-alive` 中间盒（Wi-Fi NAT 30-60s timeout）和 iOS 后台暂停，server 端可能堆积已死连接到 `webSocketConnections`。**当前 5 个连接没问题但量大或外网 LAN 部署时会卡**。

### P2-5 — `replayCache` 上限 2048 帧、`PanelStatePatchRetention` 128 patches

Sane defaults. 但 retention 是按 patch 计，不是按时间。空闲会话保留 128 patches × 5/秒 ≈ 25s 的窗口 — 网络抖动 30s 必落 snapshot。可考虑 (a) 加时间维度；(b) 在 `attach` throttle 200ms 的同时把 retention 提到 256。

### P2-6 — iOS 收到 `patch base mismatch` 后无限循环防护

`ChatViewModel.swift:789-797`：mirror 应用 patch 失败 → 立即发 `requestSnapshot`。如果 server 立刻又发了另一个 baseRevision 也不匹配的 patch（理论上不应该，但 server 重启 + race 可能），会陷入"miss → request → miss"循环。需要计数器（10 次内只允许一次 requestSnapshot）。

## 不是 bug 但值得知道的（设计妥协）

1. **HTTP body buffer 是 raw `Data` 拼接**：`requestData.append(data)` 在循环里每次都 realloc，对超大请求性能差但不致命（已被 64MB cap 框住）。
2. **`broadcastVNCEnvelope` 在 `queue.async` 内串行**：每个 envelope 顺序广播到每个连接，慢连接会拖累快连接。当前 200ms throttle 已 cap 在 ~5 帧/秒，足以应付。
3. **iOS pendingCommands 上限 200 条**：超出后丢最早的，没 spill-to-disk。极端断网场景下用户会丢操作。  
4. **`broadcaster.attach` 在 `snapshot(for:)` 内调用**：让"任何路径拿了 controller"都自动订阅。但 detach 路径只在 controller 销毁时（map 是 `ObjectIdentifier` 键 + AnyCancellable），broadcaster 自己不会主动 detach。controller 重新 init 会在新 ObjectIdentifier 下重新 attach；旧的会留着直到 weak controller 死掉。**不算 leak 但稍微浪费 RAM**。
5. **Server 监听 `127.0.0.1` 默认时，`requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)`** 在不同 macOS 上效果不稳，所以又加了 `newConnectionHandler` 里的 `isLoopbackEndpoint` 二次校验（`RemoteChatServer.swift:118-138`）。设计妥协 OK。
6. **iOS `composerText` 是本地 state，不每键击发 `composerSet`** —— 与 spec §4.2 一致（`PanelComposerDTO.text` 注释明确说 read-only mirror）。**但用户在 iOS 编辑半天再发，Mac UI 期间看到的 composer 是空的**，遥控 Mac 看协作时会困惑。设计选择，不是 bug。

## 未覆盖

1. **iOS 真机后台/前台切换实测**：只读代码确认 `scenePhase` 接线，没在模拟器/真机上跑完整 background→foreground→reconnect 链。
2. **Wi-Fi 切换 + 断网恢复**：没法在 macOS 上模拟 iOS 网络中断。
3. **Mac server 重启时 iOS 客户端的 fresh-snapshot 路径**：静态分析认为 OK，但没真实 kill `Codevoke.app` 再观察 iOS WS 行为。
4. **真实 401 后 iOS 重连风暴**：脚本能用 bad token 触发 401，但没观察 iOS app 的实际重试节奏（需要 iOS 真机日志）。
5. **多 session 并发 attach 后 focus=nil 的 firehose**：观察到设计漏洞但没造出真实多 session 并发场景（需要 Mac UI 在多个 session 间切来切去，让 broadcaster attach 多个 controller）。
6. **`composerAttach` 大 base64 blob 走 WS**：协议允许 `ChatMessageAttachment.thumbnailData` 走命令帧；如果 iOS 直接走 WS 传 thumbnail 而不走 `/attachments`，单 command 可能就撞 1MB 上限。没实测，但 iOS 当前代码只走 `/attachments` HTTP（`ChatViewModel.swift:375-386`），所以暂时无忧。
7. **server `attach` 的 detach 时机**：broadcaster 持有 controller 的 ObjectIdentifier 键 + AnyCancellable，没主动 detach。controller 死掉后 weak 引用变 nil，sink 内的 guard 守住。但 subscriptions map 还是积着 dead entries 直到下次 attach 同 key（不会复用）。**理论上是缓慢 leak**，没量化。
