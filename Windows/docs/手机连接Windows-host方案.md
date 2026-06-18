# 手机连接 Windows 电脑（Windows host 能力）实施方案

> 目标：让 iOS / Android 手机能够像连接 Mac 一样，连接到 **Windows 电脑**，
> 实现「发消息 + 实时流式输出到手机」。当前 Windows 只能当客户端去连 Mac，
> **没有 host（被连）能力**，本方案补齐这一能力。
>
> 本文档是「边做边更新」的活文档：每完成一块就更新对应的「进度」勾选与「变更记录」。

---

## 0. 背景与现状结论（调研已完成）

- **唯一的 host 目前是 macOS 端**（`Codevoke/Services/RemoteChat/RemoteChatServer.swift`，监听 18765）。
- iOS / Android / **Windows 都是客户端**，都是去连 Mac。
- Windows 设置页自己写明：「Host/Port 监听模式暂未接入」（`SettingsPage.tsx`）；
  整个 Windows 工程没有任何 server / listen / 端口绑定；`SignalingClient` 只会
  主动 `openTunnel`（发起方），不处理别人打进来的 `tunnel_open`。
- **后端（Go）不用改**：device 注册 / 信令 ws / 隧道中转 / connect 都是设备无关的。
  只要 Windows 注册成一个 device 且能被当作 `toDeviceId`，手机现有连接流程原样就能连。

### Mac host 的协议核心（Windows 要照抄）

「VNC 式面板镜像」协议，双向：

- **下行（电脑→手机）**：`PanelStateSnapshot`（全量）+ `PanelStatePatch`（增量 diff），
  含 messages、streamingTexts（流式正在打的字）、queue、status、composer、capabilities 等约 20 字段。
- **上行（手机→电脑）**：`Command` 帧（18 个 op），服务端回 `CommandAck`。

三种传输通道（LAN 直连 / 隧道中转 / WebRTC P2P）最后都汇入同一套 command/envelope 协议。

> ⚠️ 关于「跨网也行吗」：跨网依赖后端信令 + 隧道中转（和 TURN）。这一套后端对 Mac
> 已经验证可用，Windows 复用同一信令通道在原理上可行；但 **WebRTC 在 Node 侧实现是
> 最不确定的一环**，所以本方案把跨网拆成「隧道中转（二期，确定可行）」和
> 「WebRTC P2P（三期，可选优化）」，先用一期把同 Wi-Fi 直连打通。

---

## 1. Windows 端的架构设计

Windows 是 Electron：CLI 在 **主进程**（`ChatProcessRun`）跑，事件通过 IPC 流到
**渲染进程** `chatStore`（这是「活的面板状态」真相来源，并负责持久化会话）。

因此 host 必须桥接 **渲染进程（面板逻辑）↔ 主进程（WS 服务器）**。沿用 Mac 的
「服务器（传输+广播）/ 控制器（面板逻辑）」分层：

```
手机 <--WS/隧道/WebRTC--> [主进程 RemoteHostServer]
                              │  (IPC)
                              ▼
                        [渲染进程 RemoteHostBridge]  <-- 订阅/驱动 -->  chatStore（现有）
```

- **主进程**：绑定端口、token 鉴权、WS 帧解析、按连接 focus、revision/patch 广播、
  把命令转发给渲染进程、（二期）信令隧道应答、（一期）LAN 地址发布。
- **渲染进程**：把 `chatStore` 变成 `PanelStateSnapshot` 推给主进程；收到 `Command`
  时调用 `chatStore` 已有的方法（和本地 UI 按钮同一套），回 ack。

### 已有可复用 ✅

- `shared/remoteProtocol.ts`：command/ack/panelState 的 schema **已定义齐全**（客户端在用），host 直接复用。
- `processChatBackend.ts` / `ChatProcessRun`：本地跑 CLI 的后端已有。
- `AccountClient`（registerDevice / 设备码）、`chatStore`（面板状态源 + 全部 mutate 方法）。
- `SignalingClient`（一期不用；二期在它上面加「入站事件处理」）。

---

## 2. 分期计划

### 一期：同 Wi-Fi 局域网直连（先打通）

让手机在同一 Wi-Fi 下直连 Windows，能发消息 + 看到流式输出。

主进程新增：
- `src/main/remoteHost/PanelStateBroadcaster.ts`：revision 计数 + snapshot diff → patch + 128 环形缓冲（移植自 Swift）。
- `src/main/remoteHost/RemoteHostServer.ts`：`ws` + `http` 服务器，`/chat`(WS) + `/health` + `/events`，token 鉴权、按连接 focus、广播 fanout。
- `src/main/remoteHost/RemoteHostController.ts`：持有渲染进程推来的最新 snapshot，转发命令到渲染进程，管理 broadcaster。
- `src/main/remoteHost/index.ts` + 在 `main.ts` 注册启动。
- `shared/ipc.ts` 新增通道：`remote-host:push-snapshot`(渲染→主)、`remote-host:apply-command`(主→渲染 invoke)、`remote-host:status`、`remote-host:set-enabled`。

渲染进程新增：
- `src/renderer/src/remoteHost/RemoteHostBridge.ts`：订阅 `chatStore` → 构建 snapshot → 节流推主进程；处理 apply-command → 调 `chatStore` 方法。

设置/发布：
- 设置项 `remoteChatServerEnabled` / `remoteChatServerPort`(默认 18765) / `remoteChatServerToken`（首次生成持久化）。
- LAN 地址发布：周期把「内网 IP + 端口 + 临时 token」上报后端（对应 Mac 的 `LanTokenPublisher`），让手机「局域网优先」能发现 Windows。设置页显示设备码 + 局域网地址 + 在线状态。

验收：手机和 Windows 同一 Wi-Fi，输入设备码 → 连上 → 发消息 → 手机看到流式输出；电脑端能弹「允许连接」。

### 二期：跨网（隧道中转）

- `SignalingClient` 增加入站处理：`hello` 后接收别人打来的 `tunnel_open` / `tunnel_frame` / `tunnel_close`。
- 新增 `src/main/remoteHost/RemoteTunnelResponder.ts`（对应 Mac `RemoteTunnelClient`）：把隧道帧喂进与 WS 相同的 command/envelope 管道；并下发 `lan_offer` 让同网时自动升级到 LAN 直连。
- host 激活编排：注册设备 → `SignalingClient.start` → 路由入站 tunnel 事件到 responder。

验收：手机和 Windows 不在同一网络，也能连上并流式输出（走后端中转）。

### 三期（可选）：WebRTC P2P

- Node 侧 WebRTC 应答端（`wrtc`/`werift` 之类），对应 Mac `RemoteWebRTCBridge`，降低中转带宽。
- 风险最高，作为优化项，可后置。

---

## 3. 进度跟踪

> 状态：⬜ 未开始 / 🟦 进行中 / ✅ 完成

### 一期
- ✅ 安装 `ws` + `@types/ws` 依赖
- ✅ `PanelStateBroadcaster.ts`（revision + diff + 环形缓冲）—— 已移植，electron typecheck 通过
- ✅ `shared/ipc.ts` 新增通道 + 负载 schema（status / set-enabled / reset-token / push-snapshot / apply-command / command-result）
- ✅ `RemoteHostServer.ts`（ws+http、token 鉴权、`/chat`+`/health`、按连接 focus、envelope fanout、command/resume 解析、命令串行化）—— electron typecheck 通过
- ✅ `RemoteHostController.ts`（主进程：配置/ token 持久化、broadcaster ingest→broadcast、server 生命周期、命令 IPC 转发 + 超时、LAN 周期发布）
- ✅ `main.ts` 注册启动（实例化 controller、注入 LAN 依赖、注册 6 个 IPC handler、init/shutdown 接入生命周期）
- ✅ preload + `global.d.ts` 暴露 `window.acode.remoteHost`（getStatus / setEnabled / resetToken / pushSnapshot / sendCommandResult / onStatus / onApplyCommand）
- ✅ 渲染进程 `RemoteHostBridge.ts`（snapshot 构建 + 18 个 op 命令应用），并在 `App.tsx` 启动时 install
- ✅ 设置项 + 首启生成 token（controller `remote-host.json` + CredentialStore 持久化，首次自动生成）
- ✅ LAN 地址发布（controller `publishLanOnce` 周期上报内网 IP+端口+短期 token；main 注入 account/device 依赖）
- ✅ 设置页 UI（「设备连接」tab 新增 `WindowsHostPanel`：开关 / 服务状态 / 局域网地址 / 连接数 / 连接口令显示·复制·重置）
- ⬜ 真机联调（同 Wi-Fi 直连验收）—— 待用 iOS/Android 真机连本机验证

### 二期
- ✅ `SignalingClient` 入站事件处理（新增 `setInboundTunnelOpenHandler` / `clearInboundTunnelOpenHandler`，`handleMessage` 路由入站 `tunnel_open`；导出 `InboundTunnelOpenEvent` / `TunnelHandlerEvent`）
- ✅ `RemoteHostServer` 传输无关化重构（抽出 `HostConnectionSink` / `HostConnection`，新增 `attachVirtualConnection` / `detachVirtualConnection` / `deliverFrame`，WS 与隧道共用同一命令/广播/focus 管道）
- ✅ `RemoteTunnelResponder.ts`（入站 `tunnel_open`→虚拟连接，`tunnel_frame`→deliverFrame / `lan_request`→`lan_offer`，广播经 sink→`sendTunnelFrame`，close/error 清理，detach 全关；含两次 `lan_offer` 补发）
- ✅ host 激活编排：`RemoteHostController` 在 server 启停时 attach/detach responder，`buildLanOffer` 登记短期 token；`main.ts` 注入 `tunnel.signaling`(全局 SignalingClient) + `ensureStarted`（已登录时尽力拉起信令）
- ✅ 单元测试 `tests/main/remoteHost/RemoteTunnelResponder.test.ts`（7 例：hello+lan_offer、resume→panel_state、lan_request 探测、command→ack、broadcast fanout、close 拆除、detach 通知）—— typecheck + vitest（20 passed）通过
- ⬜ 跨网联调验收 —— 待手机与 Windows 不同网络真机验证（走后端中转）

### 三期（可选）
- ✅ Node 侧 WebRTC 应答端（`werift` 纯 TS WebRTC）：`SignalingClient` 入站 relay 处理 +
  `RemoteWebRTCResponder`（answerer：offer→answer、candidate 缓冲/补加、data channel↔虚拟连接）+
  `AccountClient.iceServers`（`remote/ice-config`）+ controller/main 编排
- ✅ werift 真机回环冒烟（offer/answer + ICE + data channel 收发往返成功）
- ✅ 单元测试 `tests/main/remoteHost/RemoteWebRTCResponder.test.ts`（8 例，假 peer/signaling）
- ⬜ P2P 真机联调验收 —— 待真机经 STUN/TURN 打洞验证

---

## 4. 变更记录

> 注：以下按时间倒序追加，最新在最前。

- 全量审计 + 修复（一/二/三期）。修复项：
  1. WebRTC 新增 data-channel-open 30s 超时（`RemoteWebRTCResponder`）：ICE 卡在 connecting 时
     释放 peer，杜绝泄漏；data channel 打开或连接关闭时清理定时器。
  2. `RemoteHostServer.handleFrameText` 增加 25MB 帧上限：隧道/WebRTC 通道无 ws maxPayload 兜底，
     统一拒收超大帧防 OOM。
  3. 放宽内部 IPC schema：`focusedSessionId` / `newFocusedSessionId` 由 `.uuid()` 改为非空字符串，
     避免非 UUID 会话 id 触发 parse 抛错导致命令超时。
  4. WebRTC 仅 `offer` 可开新连接：杜绝孤立 `answer`/`candidate` relay 空转 bridge；werift 动态
     import 结果 memoize，加载失败不再每条连接重试。
  5. `setEnabled`：先启停成功再持久化 `enabled`，避免端口占用等启动失败却把 enabled=true 落库。
  7. **修复首连黑屏（关键）**：`PanelStateBroadcaster` 的 `snapshotFor(null)` / `replayPayload(null)`
     原先只查 draft/null key 日志，而渲染进程总是以「当前会话 id」为 key 推送 →
     手机首连 `resume(null)` 取不到当前会话 snapshot（黑屏）。现按 Mac 语义把 null 解析为
     `currentKey`（最近一次 ingest 的会话），首连即返回当前会话全量。新增
     `tests/main/remoteHost/PanelStateBroadcaster.test.ts` 4 例回归。
  - 端到端代码级核验结论：连接（首连）/ 发消息 / 队列（含 flush/cancel）/ 实时流式输出 均可工作
    （chatStore `isStreaming` + 增量 patch）。**图片附件暂不支持**：Mac 经 `POST /attachments`
    （LAN）或 `uploadAttachment` recovery 帧（隧道/WebRTC）上传字节，Windows host 仅有
    `/health`+`/chat` 且只处理 `command`/`resume`，无上传通道——需后续补「附件上传端点 +
    recovery 帧处理 + 落临时目录回填真实 path」。
  6. **传输与端口解耦**：`RemoteHostServer` 拆出 `isRunning`（管道就绪）与 `isLanListening`（端口已绑），
     `start()` 把 LAN 监听降级为非致命——端口占用时管道（命令/广播/虚拟连接）照常就绪，隧道/WebRTC
     仍可用，仅 LAN 直连不可用并在状态里报错。controller 的 LAN 发布 / lan_offer 改判 `isLanListening`。
     新增 `tests/main/remoteHost/RemoteHostServer.test.ts` 回归（端口占用仍能 attach 虚拟连接 + 广播）。
  - 审计结论：无崩溃级缺陷；三条传输复用同一命令/广播管道；同账号「手机→Windows」后端自动
    accept（`remote.go:516`）无需审批 UI。遗留：werift 传递依赖 `ip` 的 SSRF 告警（3 high，
    上游无修复，仅用于 ICE 候选分类，非 SSRF 攻击面，列为接受风险）；LAN 端口绑定失败会一并
    拖垮隧道/WebRTC（传输与管道耦合，建议后续解耦）；多客户端共享单会话 focus 会互抢（设计取舍）。
    typecheck + vitest（29 passed）通过。

- 三期（可选）：WebRTC P2P 应答端打通（Node 侧）。
  - 选型 `werift`（纯 TS WebRTC，无原生编译，适配 electron-builder 跨平台打包）。已用回环
    冒烟验证：两端 offer/answer + ICE + data channel 文本往返成功。
  - `SignalingClient`：新增入站 relay 处理（`setInboundRelayHandler` / `clearInboundRelayHandler`），
    `handleMessage` 路由 `relay` 事件（含 payload/status/fromDeviceId）。
  - `AccountClient.iceServers(connectionId)`：拉取后端 `remote/ice-config`（STUN + 短期 TURN 凭据）。
  - `RemoteWebRTCResponder`（新）：host 作为 answerer。入站 relay `offer` → 经抽象 peer
    setRemoteDescription→createAnswer→setLocalDescription→relay `answer`；`candidate` 在 remote
    description 前缓冲、之后补加；本地 ICE candidate 经 relay 回送；data channel 打开 → 在
    `RemoteHostServer` 建虚拟连接（与 LAN/隧道同一命令/广播管道），消息→deliverFrame；连接
    failed/closed/disconnected → 拆除。peer 经 `WebRTCPeerLike` 抽象注入，werift 适配器走动态
    `import("werift")`，加载失败则该通路静默不可用，不影响 LAN/隧道。
  - 编排：`RemoteHostController` 在 server 启停时 attach/detach WebRTC responder；`main.ts` 注入
    `webrtc.signaling`（全局 SignalingClient）与 `iceServers`（accountClient 拉取）。
  - 测试：`tests/main/remoteHost/RemoteWebRTCResponder.test.ts`（8 例，假 peer/signaling，覆盖
    offer→answer、candidate 缓冲、本地 candidate relay、data channel hello/resume→panel_state、
    broadcast fanout、失败拆除、未 accepted 忽略、detach）。typecheck + vitest（28 passed）通过。

- 二期：跨网（隧道中转）链路打通。
  - `SignalingClient`：新增入站隧道处理 API（`setInboundTunnelOpenHandler` /
    `clearInboundTunnelOpenHandler`），`handleMessage` 在收到入站 `tunnel_open`（本机为
    `toDeviceId` 且无对应出站 handler）时回调；`index.ts` 导出新类型。出站路径与账号子系统不受影响。
  - `RemoteHostServer`：重构为传输无关。抽出 `HostConnectionSink`（send/isOpen/close）与
    `HostConnection`（focus + inboundChain + sink），连接集合改为 `Set<HostConnection>` +
    `Map<WebSocket,HostConnection>`；新增 `attachVirtualConnection` / `detachVirtualConnection` /
    `deliverFrame`，WS 与隧道共用同一命令解析、resume 重放、focus fanout、命令串行化与 hello 逻辑。
  - `RemoteTunnelResponder`（新）：对应 Mac `RemoteTunnelClient`。入站 `tunnel_open` → 在 server 上
    建虚拟连接并接管该 connectionId 的后续帧；`tunnel_frame` → `lan_request` 探测回 `lan_offer`，
    否则 `deliverFrame` 进同一管道；广播经虚拟连接 sink → `sendTunnelFrame` 回传；`tunnel_close`/
    `tunnel_error` 拆除；`detach` 关闭全部并通知。沿用 Mac 的 nextSeq 与两次 `lan_offer` 补发。
  - 编排：`RemoteHostController` 在 `startServer`/`stopServer` attach/detach responder，
    `buildLanOffer` 生成内网地址并登记 120s 短期 token；`main.ts` 注入 `tunnel.signaling`
    （复用全局 SignalingClient）与 `ensureStarted`（已登录则尽力启动信令）。
  - 测试：`tests/main/remoteHost/RemoteTunnelResponder.test.ts` 覆盖隧道全链路（不绑端口）。
    typecheck + vitest（20 passed）通过。


- 初版方案创建。
- 一期：安装 `ws`/`@types/ws`；新增 `src/main/remoteHost/PanelStateBroadcaster.ts`
  （从 Swift 移植 revision/diff/环形缓冲）；`shared/ipc.ts` 新增 remote-host 系列
  通道与 zod 负载 schema。electron typecheck 通过。
- 一期：新增 `src/main/remoteHost/RemoteHostServer.ts`（从 Swift `RemoteChatServer`
  移植传输+广播层，去掉 legacy/WebRTC）：`ws`+`http` 服务器，`/chat`(WS) +
  `/health`(HTTP)，`Authorization: Bearer` token 鉴权（timingSafeEqual，兼容 `?token=`
  兜底），按连接 focus（focusedSessionId / isResolvingDraftSession + draft 一次重映射），
  envelope 严格 fanout，`command`/`resume` 帧解析，命令按连接串行化，连上回 `hello`。
  面板逻辑通过 `RemoteHostServerDelegate`（applyCommand / replayPayload / snapshotFor）
  下沉给后续的 `RemoteHostController`。electron typecheck 通过。
- 一期收尾：打通主进程 ↔ 渲染进程 ↔ 设置页全链路。
  - `RemoteHostController.ts`：config(`remote-host.json`)/token(CredentialStore) 持久化与首启生成；
    实现 `RemoteHostServerDelegate`，命令经 `requestApplyCommand` IPC 下发渲染进程并按 requestId
    结算（15s 超时）；broadcaster ingest→server.broadcast；server 生命周期 enable/disable/resetToken；
    LAN 周期发布（15s）短期 token（120s TTL），先本机登记再上报后端。
  - `main.ts`：实例化 controller 并注入 LAN 依赖（accountSessionStore/deviceIdentityStore/accountClient），
    注册 6 个 IPC handler（get-status/set-enabled/reset-token/push-snapshot/command-result + apply-command/status 推送），
    `whenReady` 后 `init()`、`before-quit` 时 `shutdown()`。
  - preload `preload.cts` + `global.d.ts`：暴露 `window.acode.remoteHost` 全套方法与 status/apply-command 事件监听。
  - 渲染进程 `RemoteHostBridge.ts`：订阅 chat/project/settings store → 组装 `PanelStateSnapshot`（90ms 节流）
    推主进程；接收 apply-command 调 `chatStore` 已有方法执行 18 个 op，回 ack/focus 变更；`App.tsx` 启动 install。
  - 设置页 `SettingsPage.tsx`：「设备连接」tab 新增 `WindowsHostPanel`，开关启停 host、显示运行状态/局域网地址/
    连接数、连接口令显示·复制·重置。typecheck + vitest（13 passed）通过。
