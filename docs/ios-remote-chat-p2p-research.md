# iOS 远程聊天 P2P 方案调研

日期：2026-05-13

## 目标

实现一个 iOS App，让用户可以在手机上远程和 Mac 上的 Codevoke/Claude Code 会话对话。iOS 不做文件管理，只提供：

- 项目列表
- 历史会话
- 实时聊天
- 流式输出

性能目标是不牺牲实时性：正常情况下聊天内容必须走端到端低延迟通道，服务器只做认证、设备发现、在线状态和连接协商。

## 结论

推荐方案：

```text
iOS App  <==== WebRTC DataChannel P2P ====>  Mac App
   |                                             |
   +----------- Signaling/Auth Server -----------+
                         |
                    STUN/TURN
```

核心原则：

1. 聊天正文优先走 iOS 和 Mac 之间的 P2P DataChannel。
2. 服务器只负责登录、设备绑定、在线状态、信令转发和权限校验。
3. STUN 用于 NAT 探测和打洞。
4. TURN 只在 P2P 失败时兜底。
5. 所有聊天内容在传输层加密，服务端默认不存储、不解析正文。

这类方案可以实现实时流式输出，但不能保证所有网络都能纯 P2P 成功。商业级稳定性必须保留 TURN/Relay 兜底。

## 为什么不用纯 WebSocket 中继

纯 WebSocket 中继架构简单：

```text
iOS App <-> Server <-> Mac App
```

但它有明显问题：

- 所有聊天 token 和输出都经过服务器。
- 服务端带宽成本随用户量线性增加。
- 延迟依赖服务器地区和链路质量。
- 服务器故障会影响所有会话。

本项目更适合 P2P 优先架构：

```text
iOS App <-> Mac App
```

服务器只参与连接建立，不参与稳定态数据传输。

## 为什么选 WebRTC DataChannel

WebRTC DataChannel 适合本项目，因为它提供：

- NAT 穿透能力
- STUN/TURN 标准生态
- DTLS 加密
- 双向实时消息
- 可靠/不可靠、有序/无序通道配置
- iOS/macOS 可用的原生库

本项目不是视频通话，不需要音视频轨道，只需要 DataChannel。

## 推荐通道设计

建立多个 DataChannel，不同类型的数据隔离，避免互相阻塞。

```text
control     可靠、有序：认证后控制事件、心跳、会话状态
chat        可靠、有序：用户消息、assistant delta、done/error
telemetry   不可靠、无序：延迟采样、typing 状态、临时在线状态
```

### control channel

用于：

- hello
- authenticated
- ping/pong
- reconnect_resume
- session_lock
- cancel_generation

配置：

```text
ordered: true
reliable: true
```

### chat channel

用于：

- user_message
- assistant_delta
- assistant_done
- assistant_error
- session_snapshot

配置：

```text
ordered: true
reliable: true
```

聊天正文必须可靠有序，否则流式文本会乱序或丢片。

### telemetry channel

用于：

- network_rtt
- typing_indicator
- transient_presence

配置：

```text
ordered: false
maxRetransmits: 0
```

这些消息过期就没价值，不能阻塞聊天正文。

## 连接流程

```text
1. Mac App 登录服务器
2. Mac App 上报 deviceId、deviceName、capabilities
3. Mac App 和服务器保持 WebSocket signaling 连接
4. iOS App 登录服务器
5. iOS App 拉取已绑定 Mac 设备列表
6. 用户选择一台 Mac
7. iOS 通过服务器向 Mac 发起 connect_request
8. Mac 返回 accept_connect
9. iOS 创建 WebRTC offer
10. 服务器转发 offer 给 Mac
11. Mac 创建 answer
12. 服务器转发 answer 给 iOS
13. 双方交换 ICE candidates
14. P2P DataChannel 建立
15. iOS 和 Mac 在 DataChannel 内完成会话级认证
16. 聊天数据开始直连传输
```

服务器只转发 signaling 消息，不参与 chat channel 内容。

## 设备绑定和多用户区分

每台 Mac 有一个长期 deviceId：

```json
{
  "deviceId": "mac_8F3A92",
  "deviceName": "Anna's MacBook Pro"
}
```

每台 iPhone 有一个 clientId：

```json
{
  "clientId": "iphone_D12E45",
  "clientName": "Anna's iPhone"
}
```

服务器保存绑定关系：

```json
{
  "userId": "user_123",
  "deviceId": "mac_8F3A92",
  "clientId": "iphone_D12E45",
  "permission": "chat_only"
}
```

Mac 端也保存允许连接的 clientId 列表，不能只相信服务器。

## 设备码连接流程

第一版使用桌面端固定设备码：

```text
1. Mac 显示固定设备码
2. iOS 登录账号后输入设备码
3. 服务器验证设备码属于哪台 Mac
4. 服务器校验目标设备在线和连接策略
5. 默认情况下 Mac 收到连接请求并本地确认
6. 如果 Mac 开启允许任意连接，则可跳过本地确认
7. 允许后进入 signaling 和 P2P 连接流程
```

后续可加二维码：

```json
{
  "deviceCode": "ACD482913",
  "deviceId": "mac_8F3A92",
  "resettable": true
}
```

设备码不是登录 token。后端只保存 hash，明文码由客户端展示，用户可主动重置。

## 消息协议

### 用户消息

```json
{
  "type": "user_message",
  "requestId": "req_123",
  "projectId": "proj_abc",
  "sessionId": "sess_001",
  "content": "继续",
  "createdAt": "2026-05-13T10:00:00Z"
}
```

### 流式输出

```json
{
  "type": "assistant_delta",
  "requestId": "req_123",
  "sessionId": "sess_001",
  "seq": 42,
  "delta": "这是一小段输出"
}
```

### 完成事件

```json
{
  "type": "assistant_done",
  "requestId": "req_123",
  "sessionId": "sess_001",
  "messageId": "msg_999",
  "finalSeq": 87
}
```

### 错误事件

```json
{
  "type": "assistant_error",
  "requestId": "req_123",
  "sessionId": "sess_001",
  "message": "Chat process exited unexpectedly"
}
```

## 实时输出策略

Mac 端从本地聊天后端读取流式输出后，立即转成 `assistant_delta` 发给 iOS：

```text
Claude process output
  -> JSONLStreamReader
  -> Chat event normalization
  -> assistant_delta
  -> WebRTC DataChannel
  -> iOS ChatView append
```

性能要求：

- 不等完整 assistant 消息完成。
- 不按句子聚合。
- 允许极小批量合并，目标是降低 UI 抖动而不是增加延迟。
- 建议 20-50ms 或 1-2KB 做一次 flush，谁先到用谁。
- 每个 delta 带递增 `seq`，便于 iOS 检测缺片和重连补齐。

## 重连和恢复

P2P 断开后不要丢会话。

```text
1. iOS 检测 DataChannel closed
2. 通过 signaling server 请求 reconnect
3. 重新 ICE 协商
4. DataChannel 建立后发送 reconnect_resume
5. Mac 根据 sessionId + lastSeq 返回缺失 delta 或完整消息快照
```

恢复请求：

```json
{
  "type": "reconnect_resume",
  "sessionId": "sess_001",
  "requestId": "req_123",
  "lastSeq": 42
}
```

Mac 响应：

```json
{
  "type": "session_snapshot",
  "sessionId": "sess_001",
  "messages": []
}
```

## 性能设计

### 延迟预算

目标体验：

```text
Mac 产生 delta -> iOS UI 可见：50-200ms 常态
```

分解：

```text
本地进程读取：1-10ms
事件编码：<1ms
DataChannel 发送：1-50ms
公网 P2P 传输：20-150ms
主线程 UI append：1-16ms
```

TURN 兜底时延迟会升高，但仍可满足聊天流式输出。

### 背压控制

iOS 渲染慢或网络抖动时，Mac 不能无限堆积内存。

策略：

- DataChannel 发送前检查 bufferedAmount。
- bufferedAmount 超过阈值时暂停读取/发送非关键事件。
- chat channel 不丢消息，telemetry channel 可丢。
- assistant_delta 可在发送队列中合并相邻 delta。
- 服务端/Mac 端保留完整最终消息，重连后可补齐。

建议阈值：

```text
chat bufferedAmount warning: 256KB
chat bufferedAmount hard limit: 1MB
telemetry drop threshold: 64KB
```

### 分片策略

不要发送超大 JSON 包。

建议：

- delta 单包尽量 < 8KB。
- 大 snapshot 分页传输。
- 图片/附件不在第一版范围内。

### UI 渲染策略

iOS 不要每个字符都触发布局。

建议：

- 网络层按 delta 接收。
- ViewModel 以 30-60fps 节奏合并刷新 UI。
- 当前 streaming bubble 单独更新。
- 历史消息使用 lazy list。
- 超长会话按分页加载。

## 安全设计

### 服务端

服务端职责：

- 用户登录
- 设备注册
- 设备绑定
- 在线状态
- signaling relay
- TURN 临时凭证签发

服务端不做：

- 不保存聊天正文
- 不执行项目命令
- 不读取 Mac 文件
- 不保存 Claude 输出

### Mac 端

Mac 端必须本地校验：

- clientId 是否被允许
- userId 是否匹配
- 会话权限是否为 chat_only
- 当前项目是否允许远程聊天

不要因为 signaling server 说允许就直接接受连接。

### 端到端认证

WebRTC 自带 DTLS 加密，但仍建议在 DataChannel 建立后做应用层握手：

```text
iOS -> Mac: client_hello + signed nonce
Mac -> iOS: server_hello + signed nonce
```

这样可以防止 signaling server 被错误配置时误连设备。

## TURN 兜底

必须接受一个事实：不是所有网络都能 P2P。

常见失败场景：

- 对称 NAT
- 运营商 CGNAT
- 公司/校园防火墙
- 酒店 Wi-Fi
- UDP 被封
- 非标准端口被封

因此生产版应提供：

```text
STUN: udp/3478
TURN: udp/3478
TURN TCP: tcp/3478
TURNS: tcp/443
```

TURN 只作为兜底，正常 P2P 成功后不产生中继流量。

## 技术选型

### iOS/macOS P2P 库

优先调研：

1. libdatachannel
2. Google WebRTC native SDK
3. WKWebView RTCDataChannel 方案，仅作为实验或备选

推荐第一优先级：`libdatachannel`。

理由：

- 专注 DataChannel，不需要完整音视频栈。
- 支持 iOS/macOS。
- 更轻，适合聊天和控制通道。

风险：

- Swift 封装和构建链需要验证。
- App Store 打包、bitcode/架构、动态库签名需要实测。
- 后续如果要加音视频，Google WebRTC 生态更完整。

### Signaling server

建议：

- WebSocket
- Redis 存在线状态
- PostgreSQL 存用户/设备绑定
- 短期内不要把聊天正文进服务端数据库

### TURN server

建议：

- coturn
- REST API 临时用户名/密码
- 按用户/设备限速
- 单独监控 TURN 带宽和连接数

## 服务端 API 草案

### 登录后获取设备

```http
GET /api/devices
```

返回：

```json
[
  {
    "deviceId": "mac_8F3A92",
    "deviceName": "Anna's MacBook Pro",
    "online": true,
    "lastSeenAt": "2026-05-13T10:00:00Z"
  }
]
```

### 发起连接

```http
POST /api/devices/mac_8F3A92/connect
```

返回：

```json
{
  "connectionId": "conn_123",
  "signalingUrl": "wss://signal.example.com/ws/conn_123",
  "iceServers": []
}
```

### signaling 消息

```json
{
  "connectionId": "conn_123",
  "from": "iphone_D12E45",
  "to": "mac_8F3A92",
  "type": "offer",
  "payload": {}
}
```

类型：

- offer
- answer
- ice_candidate
- connect_request
- connect_accept
- connect_reject
- disconnect

## Mac 端模块建议

```text
Codevoke/Services/Remote/
  RemoteDeviceIdentityStore.swift
  RemoteDeviceCodeStore.swift
  RemoteSignalingClient.swift
  RemotePeerConnection.swift
  RemoteDataChannelRouter.swift
  RemoteChatBridge.swift
  RemoteAuthVerifier.swift
```

职责：

- `RemoteSignalingClient`：连接服务器，收发 offer/answer/candidate。
- `RemotePeerConnection`：封装 WebRTC/libdatachannel。
- `RemoteDataChannelRouter`：按 channel 和 event type 分发消息。
- `RemoteChatBridge`：连接现有 ChatRuntime/ChatSessionStore。
- `RemoteAuthVerifier`：校验 clientId/token/nonce。

## iOS 端模块建议

```text
ClaudeMobile/
  Models/
    RemoteProject.swift
    RemoteSession.swift
    RemoteMessage.swift
  Networking/
    AuthClient.swift
    DeviceClient.swift
    SignalingClient.swift
    PeerConnectionClient.swift
    RemoteChatClient.swift
  Views/
    DeviceListView.swift
    ProjectListView.swift
    SessionListView.swift
    ChatView.swift
```

iOS 只做聊天壳，不做文件树、不做终端、不做本地代码执行。

## 里程碑

### M1：局域网验证

当前已完成 Mac 本地只读 HTTP API 和本地 WebSocket streaming。

已实现：

- `GET /health`
- `GET /projects`
- `GET /sessions`
- `GET /sessions/{sessionId}`
- `GET /sessions/{sessionId}/messages`
- 设置页远程聊天开关、端口、LAN 监听、token 展示/重置
- `WS /chat`
- 复用现有 `ChatProcessBackend.start(...)`
- 将 `ChatBackendEvent.appendDelta` 映射为 `assistant_delta`
- 将 `ChatBackendEvent.finished` 映射为 `assistant_done`
- 将 `ChatBackendEvent.failed` 映射为 `assistant_error`
- 加入 requestId、sessionId、seq，给 iOS 做流式拼接和重连补齐

下一片：iOS 直连 MVP。

目的：验证聊天桥接和 UI，而不是先解决 NAT。

### M2：信令服务器 + WebRTC P2P

- 设备登录
- 设备列表
- signaling WebSocket
- WebRTC DataChannel
- STUN 打洞
- 流式输出走 P2P

目的：验证核心产品架构。

### M3：TURN 兜底

- 部署 coturn
- 签发临时 TURN 凭证
- 自动 fallback
- 指标区分 p2p/relay

目的：把可用性从“多数网络可用”提升到“商业可用”。

### M4：安全和稳定性

- 设备码/二维码配对
- Mac 本地授权列表
- 重连恢复
- seq 补齐
- 限流和背压
- 端到端握手

### M5：生产监控

- 连接成功率
- P2P 成功率
- TURN fallback 比例
- 首包延迟
- delta 端到端延迟
- bufferedAmount 峰值
- 崩溃率

## 必须监控的指标

```text
connection_attempt_total
connection_success_total
p2p_success_total
turn_fallback_total
ice_gathering_duration_ms
ice_connect_duration_ms
datachannel_open_duration_ms
first_delta_latency_ms
delta_delivery_latency_ms
chat_buffered_amount_bytes
reconnect_total
resume_success_total
```

核心看板：

```text
P2P 成功率
TURN 兜底比例
端到端首字延迟
流式 delta 延迟 P50/P95/P99
断线重连成功率
```

## 风险

1. P2P 不是 100% 成功，必须有 TURN。
2. iOS 后台运行受系统限制，长时间后台保持连接不现实。
3. Mac 睡眠会断开连接，需要唤醒策略或明确提示。
4. TURN 带宽成本可能成为主要成本。
5. WebRTC 原生库集成需要实际打包验证。
6. 严格网络下 TURNS/443 仍可能被代理或防火墙影响。

## 不做范围

第一阶段不做：

- 文件管理
- 文件编辑
- 终端
- Git 操作
- 云端历史同步
- 多 Mac 并发同一会话编辑
- 图片/附件传输
- 推送通知唤醒 Mac

## 最终建议

按这个顺序推进：

```text
局域网聊天 MVP
  -> WebRTC P2P
  -> TURN 兜底
  -> 设备码/二维码配对
  -> 重连和性能监控
```

不要一开始就做完整服务器中继，否则后续很难把成本和延迟降下来。当前目标是“服务器负责找人，聊天内容能直连就直连”。

## 参考资料

- [libdatachannel 官方站点](https://libdatachannel.org/)
- [libdatachannel native wrapper](https://github.com/swarm-cloud/datachannel-native)
- [MDN RTCDataChannel](https://developer.mozilla.org/en-US/docs/Web/API/RTCDataChannel)
- [MDN Using WebRTC data channels](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Using_data_channels)
- [web.dev WebRTC data channels](https://web.dev/articles/webrtc-datachannels)
- [IETF RFC 8831 WebRTC Data Channels](https://www.ietf.org/ietf-ftp/rfc/rfc8831.pdf)
- [coturn turnserver 文档](https://github.com/coturn/coturn/wiki/turnserver)
- [rtcStats: No TURN TLS/443](https://www.rtcstats.com/kb/observation-notlsturn443)
- [coturn TLS 443 discussion](https://github.com/coturn/coturn/issues/1626)
- [webrtcHacks coturn article](https://webrtchacks.com/coturn/)
