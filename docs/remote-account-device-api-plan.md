# 远程连接账号体系与 Go API 方案调研

日期：2026-05-14

## 目标

把当前 iOS 手动输入 `Mac 主机 + 端口 + Token` 的局域网连接方式，演进为：

- 用户登录/注册后自动发现同账号设备。
- 同账号下 iPhone 可直接看到已登录的桌面设备，不再手动输入 IP、端口、Token。
- 不同账号可通过桌面端固定设备码识别目标电脑并发起连接。
- 同账号设备连接不需要电脑端确认。
- 跨账号设备码连接默认每次都需要电脑端确认；开启“允许任意连接/免确认”后可直接通过。
- 订阅、支付和权益仍要做，但作为后续权益层，不阻塞第一版账号和设备链路。
- Go 后端只做账号、订阅、设备、授权、在线状态和信令验证。
- 聊天正文和远程流量默认不经过 Go 业务服务器。

已有底层方向参考：`docs/ios-remote-chat-p2p-research.md`。

## 当前代码证据

### 当前 Mac 端远程服务

相关文件：

- `ClaudeMac/Services/RemoteChat/RemoteChatServer.swift`
- `ClaudeMac/Services/RemoteChat/RemoteChatRouter.swift`
- `ClaudeMac/Services/RemoteChat/RemoteChatBridge.swift`
- `ClaudeMac/Services/RemoteChat/RemoteChatServerController.swift`
- `ClaudeMac/Views/SettingsPageView.swift`

当前能力：

- Mac 内置 HTTP/WebSocket 服务。
- 默认端口 `18765`。
- 支持 `GET /health`。
- 除 `/health` 外使用 `Authorization: Bearer <token>`。
- 支持项目、模型、文件、会话、消息、附件和远程聊天 WebSocket。
- 设置页已有：启用远程聊天 API、端口、是否允许局域网设备连接、Bearer Token 展示/复制/重置。

当前安全边界：

- 如果 `remoteChatServerBindLAN == false`，Mac 端拒绝非 loopback 连接。
- 如果允许局域网连接，则依赖 Bearer Token。

### 当前 iOS 端连接方式

相关文件：

- `AcodeIOS/Codevoke/Networking/RemoteChatConfig.swift`
- `AcodeIOS/Codevoke/Networking/RemoteHTTPClient.swift`
- `AcodeIOS/Codevoke/Networking/RemoteWebSocketClient.swift`
- `AcodeIOS/Codevoke/Views/SettingsView.swift`

当前能力：

- iOS 设置页手动填写 Mac 主机、端口、Token。
- HTTP 使用 `http://<macHost>:<port>`。
- WebSocket 使用 `ws://<macHost>:<port>/chat`。
- HTTP/WebSocket 都使用同一个 Bearer Token。

当前问题：

- 用户需要知道 Mac IP。
- 用户需要复制 Token。
- 只适合局域网或手动网络配置。
- 不能表达账号、设备归属、授权关系和付费状态。
- 不适合做商业化远程能力。

### Go/admin 框架证据

已将桌面 `禾屿后端框架` 复制到本项目，并重命名为 `后端`：

- `后端/server/go.mod`
- `后端/server/main.go`
- `后端/server/initialize/router.go`
- `后端/server/api/v1/{admin,biz}`
- `后端/server/router/{admin,biz}`
- `后端/server/service/{admin,biz}`
- `后端/server/model/{admin,biz,shared}`

框架现状：

- Go module：`heyu/server`
- HTTP 框架：Gin
- ORM：GORM
- DB：MySQL
- Auth：JWT，支持 `Authorization: Bearer` 和 HttpOnly Cookie
- 权限：Casbin
- 缓存/在线状态基础：Redis 客户端已存在，但默认配置 `system.use-redis: false`
- 响应结构：统一 `{code, data, msg}`
- 当前业务路由入口：`initialize/router_biz.go`
- 当前业务域样板：`dashboard`
- 复制品已清理嵌套 `.git` 和 `.DS_Store`，后续可由 ClaudeMac 主仓库直接纳管

当前后端适合承接账号、设备、授权、订阅、审计、信令校验这类业务能力；但框架本身还没有 WebSocket/signaling 实现，也没有远程设备相关模型。

## 产品形态

### 登录注册

用户需要账号体系：

- 只允许手机号注册。
- 第一版不发短信验证码。
- 注册字段只需要手机号和密码。
- 登录字段只需要手机号和密码。
- 不强制昵称、头像、邮箱、第三方登录。
- 登录后获得 access token 和 refresh token。
- Mac、Windows 桌面端和 iOS App 都使用同一套账号体系。
- Windows 端后续再做，但后端模型不能写死只有 Mac。

### 付费授权

远程连接能力后续作为订阅权益：

- 免费用户：可先允许账号注册、登录、基础设备绑定；跨网络能力可限制或试用。
- 付费用户：开启跨网络远程、更多设备数、固定设备码连接、TURN 兜底等权益。
- 示例价格：`99 元/年`。

后端判断：

- 用户是否存在有效订阅。
- 订阅是否过期。
- 是否允许新增设备。
- 是否允许发起远程连接。

### 同账号免配置连接

用户体验：

1. Mac 登录账号。
2. Mac 注册为一台设备。
3. iOS 登录同一账号。
4. iOS 自动看到该账号下在线桌面设备。
5. 用户点击连接。
6. Go 后端校验同账号、设备在线和订阅权益。
7. 同账号连接直接进入连接流程，不弹电脑确认。
8. 连接建立后，iOS 不再需要 IP、端口、Token。

### 不同账号固定设备码连接

适用场景：

- 授权别人连接自己的电脑。
- 客服/协助场景。
- 家人账号连接。

用户体验：

1. 桌面端显示固定设备码，例如 8-12 位数字/字母。
2. iOS 输入设备码。
3. Go 后端根据设备码识别目标电脑，并校验目标设备在线状态。
4. 桌面端默认弹出连接确认。
5. 桌面用户选择：允许本次、拒绝、或开启免确认策略。
6. 若桌面端已开启免确认策略，则 iOS 输入设备码后可直接进入连接流程。
7. 后续可在桌面端设置里关闭免确认、重置设备码、撤销已记住设备。

固定设备码要求：

- 设备码默认固定，不按时间自动轮换。
- 设备码不等于登录 token，不包含长期凭证。
- 后端只保存 `device_code_hash`，不保存明文设备码。
- 支持用户主动重置设备码；重置后旧码立即失效。
- 输入设备码必须限流，防撞库和暴力猜测。

### Mac 设置项

后续 Mac 设置页建议增加：

- 登录状态。
- 订阅状态。
- 本机设备名。
- 本机设备码展示/复制/重置。
- 远程连接总开关。
- 跨账号连接确认策略：每次询问 / 允许任意连接。
- 已授权设备列表。
- 每个授权设备：允许、拒绝、撤销、最后连接时间。
- 当前在线连接列表。

### 统一隐私政策

iOS 和桌面端都从云端拉取统一协议：

- 隐私政策。
- 用户协议。
- 订阅/会员协议。
- 版本号、生效时间、发布状态。
- 用户同意记录。

第一版至少要支持隐私政策云端读取，客户端启动、注册页、设置页都能显示同一份内容。

## 总体架构

推荐架构：

```text
        +--------------------+
        |      Go API        |
        | Auth/Billing/Device|
        | Signaling Verify   |
        +---------+----------+
                  |
        Signaling WebSocket
                  |
+-----------------+-----------------+
|                                   |
|                                   |
Mac App  <==== P2P/DataChannel ====> iOS App
         或 LAN/TURN fallback
```

核心原则：

- Go API 不承载聊天正文。
- Go API 不读取用户项目文件。
- Go API 不保存 Claude 输出。
- Go API 只负责“谁是谁、有没有付费、设备是否允许、连接如何协商”。
- 真正聊天数据优先走 P2P DataChannel。
- P2P 失败时可使用 TURN 兜底；TURN 是网络层 relay，不是业务服务器解析聊天内容。

## Go API 职责边界

### Go API 负责

- 用户注册/登录。
- token 签发和刷新。
- 订阅权益判断。
- 设备注册。
- 设备在线状态。
- 同账号设备列表。
- 固定设备码重置和解析。
- 授权关系管理。
- 连接请求状态机。
- WebRTC signaling 消息转发。
- STUN/TURN 配置下发。
- 风控、限流、审计日志。

### Go API 不负责

- 不代理 Claude 聊天正文。
- 不代理项目文件内容。
- 不执行命令。
- 不保存远程聊天历史。
- 不保存用户 Claude API Key。
- 不作为长期数据通道。

## 核心数据模型草案

### users

- `id`
- `phone`：唯一，第一版唯一登录标识
- `password_hash`
- `status`
- `created_at`
- `updated_at`

### subscriptions

- `id`
- `user_id`
- `plan_code`
- `status`
- `started_at`
- `expires_at`
- `provider`
- `provider_order_id`

### devices

- `id`
- `user_id`
- `device_type`：`desktop` / `ios`
- `platform`：`macos` / `windows` / `ios`
- `device_name`
- `device_public_key`
- `device_code_hash`：桌面端固定设备码 hash
- `approval_policy`：`always_ask` / `allow_anyone`
- `status`
- `last_seen_at`
- `created_at`

### device_sessions

- `id`
- `device_id`
- `connection_id`
- `online_status`
- `ip_hash`
- `app_version`
- `last_ping_at`

### device_grants

- `id`
- `owner_user_id`
- `target_device_id`
- `grantee_user_id`
- `grantee_device_id`
- `scope`：`chat_only`
- `grant_type`：`same_account` / `device_code`
- `remembered`
- `status`
- `expires_at`
- `created_at`

### device_code_attempts

- `id`
- `target_device_id`
- `from_user_id`
- `from_device_id`
- `code_hash_prefix`
- `status`
- `ip_hash`
- `created_at`

### connection_attempts

- `id`
- `from_device_id`
- `to_device_id`
- `status`
- `reason`
- `created_at`
- `completed_at`

### legal_documents

- `id`
- `type`：`privacy_policy` / `user_agreement` / `subscription_agreement`
- `platform`：`all` / `ios` / `macos` / `windows`
- `version`
- `title`
- `content_format`：`markdown` / `html`
- `content`
- `published`
- `effective_at`
- `created_at`
- `updated_at`

### legal_consents

- `id`
- `user_id`
- `document_id`
- `document_type`
- `document_version`
- `platform`
- `device_id`
- `consented_at`

## API 草案

### Auth

```http
POST /api/v1/remote/auth/register
POST /api/v1/remote/auth/login
POST /api/v1/remote/auth/refresh
POST /api/v1/remote/auth/logout
GET  /api/v1/remote/me
```

注册请求第一版只接收：

```json
{
  "phone": "13800138000",
  "password": "password"
}
```

不接收邮箱、昵称、第三方登录字段；验证码字段预留但第一版不启用。

### Subscription

```http
GET  /api/v1/remote/subscription
POST /api/v1/remote/subscription/checkout
POST /api/v1/remote/subscription/webhook
```

说明：

- 支付可先抽象 provider。
- 国内支付和 App Store 内购需要后续单独设计。
- 后端只根据支付回调更新订阅状态。

### Devices

```http
POST   /api/v1/remote/devices/register
GET    /api/v1/remote/devices
GET    /api/v1/remote/devices/{deviceId}
PATCH  /api/v1/remote/devices/{deviceId}
DELETE /api/v1/remote/devices/{deviceId}
```

桌面设备更新接口需要支持：

- 设备名。
- 平台。
- 远程连接总开关。
- `approval_policy`：每次询问或允许任意连接。

### Device Code / Grant

```http
GET  /api/v1/remote/devices/{deviceId}/device-code
POST /api/v1/remote/devices/{deviceId}/device-code/reset
POST /api/v1/remote/device-codes/resolve
POST /api/v1/remote/grants/{grantId}/approve
POST /api/v1/remote/grants/{grantId}/reject
DELETE /api/v1/remote/grants/{grantId}
```

说明：

- `GET device-code` 只允许设备所有者读取，返回明文展示用设备码。
- 后端持久化只保存 hash；如果不能反查明文，客户端本地保存明文展示，后端只负责 reset。
- `resolve` 输入设备码，返回目标设备基础信息和是否需要桌面端确认，不返回敏感凭证。

### Connection

```http
POST /api/v1/remote/devices/{deviceId}/connect
GET  /api/v1/remote/connections/{connectionId}
POST /api/v1/remote/connections/{connectionId}/cancel
```

### Legal Documents

```http
GET  /api/v1/remote/legal-documents?type=privacy_policy&platform=ios
POST /api/v1/remote/legal-consents
```

第一版管理端可以先手工写入协议内容；客户端只读和提交同意记录。

### Signaling WebSocket

```text
wss://api.example.com/api/v1/signaling/ws
```

消息类型：

```text
hello
presence_update
connect_request
connect_accept
connect_reject
offer
answer
ice_candidate
disconnect
```

## 连接流程

### 同账号连接

```text
1. Mac 登录 Go API。
2. Mac 注册 device，建立 signaling WebSocket。
3. iOS 登录 Go API。
4. iOS 获取同账号设备列表。
5. 用户选择 Mac。
6. iOS 请求 /connect。
7. Go API 校验订阅、同账号、设备在线和远程开关。
8. Go API 直接创建 accepted connection。
9. 双方通过 signaling 交换 offer/answer/ice_candidate。
10. P2P DataChannel 建立。
11. DataChannel 内再做应用层握手。
12. iOS 进入聊天。
```

### 固定设备码连接

```text
1. 桌面端展示固定设备码。
2. iOS 登录后输入设备码。
3. Go API 根据 device_code_hash 解析目标设备。
4. Go API 校验目标设备在线、远程开关和订阅权益。
5. 如果目标设备 approval_policy=allow_anyone，直接创建 accepted connection。
6. 如果目标设备 approval_policy=always_ask，创建 pending connection 并推送给桌面端。
7. 桌面端允许或拒绝。
8. 允许后进入 signaling 和 P2P 连接流程。
```

## 本地授权优先原则

Mac 端必须保存本地授权列表，不能只信任服务器。

原因：

- 服务器账号被盗时，Mac 仍应有本地确认边界。
- 用户可以在 Mac 上一键撤销设备。
- Mac 是执行项目和命令的最终安全边界。

本地授权建议包含：

- `granteeUserId`
- `granteeDeviceId`
- `clientName`
- `scope`
- `remembered`
- `createdAt`
- `lastUsedAt`
- `revokedAt`

## 与当前局域网 Token 的关系

当前模式不要立刻删除，应保留为 fallback/debug：

- `Local Manual Mode`：手动 IP + Token。
- `Account Remote Mode`：账号登录 + 设备发现 + P2P。

迁移策略：

1. 当前 iOS 设置页保留手动连接。
2. 新增登录入口和设备列表。
3. 默认推荐账号连接。
4. 高级设置里保留手动 IP/Token。
5. 后续稳定后弱化手动输入。

## 付费策略

建议第一版权益：

| 能力 | 免费 | 付费 |
| --- | --- | --- |
| 本机/局域网手动连接 | 可用 | 可用 |
| 同账号云端设备发现 | 限制或试用 | 可用 |
| 跨网络 P2P/TURN | 不可用或试用 | 可用 |
| 固定设备码连接 | 不可用或限制 | 可用 |
| 多设备绑定 | 1 台 | 多台 |
| TURN 兜底 | 不可用或限额 | 可用 |

订阅校验点：

- 登录后拉取权益。
- 设备注册时校验数量。
- 发起连接时校验远程权益。
- TURN 凭证签发时校验订阅。

## 安全设计

### Token

- 登录 access token 短有效期。
- refresh token 长有效期，需要可撤销。
- Mac/iOS 设备各自有 device key pair。
- 不复用当前 `acm_local_...` 作为云端长期凭证。

### 固定设备码

- 后端只保存 hash。
- 默认长期固定。
- 用户主动重置后旧码立即失效。
- 限制错误次数。
- 限制同 IP/账号尝试频率。
- 设备码解析成功不等于授权成功，默认仍要桌面端确认。

### 信令

- signaling 消息必须校验 connectionId、fromDeviceId、toDeviceId。
- 只有授权连接双方可以收发该 connection 的 signaling。
- signaling payload 不应包含聊天正文。

### DataChannel 应用层握手

P2P 建立后仍需要应用层认证：

```text
iOS -> Mac: client_hello + nonce + signed payload
Mac -> iOS: server_hello + nonce + signed payload
```

Mac 端校验：

- userId 是否允许。
- client device 是否允许。
- grant 是否有效。
- scope 是否足够。
- 本地远程开关是否开启。

### 审计日志

Go API 保存：

- 登录时间。
- 设备注册。
- 固定设备码重置/解析。
- 授权允许/拒绝/撤销。
- 连接尝试成功/失败。
- TURN 凭证签发。

不保存：

- 聊天正文。
- 文件内容。
- Claude 输出。
- 用户项目路径明文，必要时可 hash 或只存设备侧展示。

## 禾屿后端落地方案

当前项目已经有可用后端框架，后续不再按空白 `AdminGo/` 设计，而是映射到 `后端/server` 的既有分层。

### 推荐目录映射

```text
后端/server/
  api/v1/biz/remote_auth.go
  api/v1/biz/remote_device.go
  api/v1/biz/remote_device_code.go
  api/v1/biz/remote_connection.go
  api/v1/biz/remote_signaling.go
  api/v1/biz/remote_subscription.go
  api/v1/biz/remote_legal.go

  router/biz/remote_auth.go
  router/biz/remote_device.go
  router/biz/remote_device_code.go
  router/biz/remote_connection.go
  router/biz/remote_signaling.go
  router/biz/remote_subscription.go
  router/biz/remote_legal.go

  service/biz/remote_auth.go
  service/biz/remote_device.go
  service/biz/remote_device_code.go
  service/biz/remote_connection.go
  service/biz/remote_signaling.go
  service/biz/remote_turn.go
  service/biz/remote_subscription.go
  service/biz/remote_legal.go
  service/biz/remote_audit.go

  model/biz/remote_user_device.go
  model/biz/remote_device_session.go
  model/biz/remote_device_grant.go
  model/biz/remote_device_code_attempt.go
  model/biz/remote_connection_attempt.go
  model/biz/remote_subscription.go
  model/biz/remote_legal_document.go
  model/biz/remote_legal_consent.go
  model/biz/remote_audit_log.go

  model/biz/request/remote_*.go
  model/biz/response/remote_*.go
```

原因：

- `admin` 域更像控制台管理能力，远程连接是业务能力，应放 `biz`。
- `api -> service -> model` 已是既有约定，新增远程模块应保持这个分层。
- `initialize/router_biz.go` 已经集中注册业务路由，适合加入远程模块。
- `initialize/gorm_biz.go` 当前为空，适合集中追加远程业务表 AutoMigrate；生产仍建议用迁移 SQL，不依赖 AutoMigrate。

### 路由分组建议

公共接口：

```text
POST /remote/auth/login
POST /remote/auth/refresh
POST /remote/device-codes/resolve
GET  /remote/ice-config
```

登录后接口：

```text
POST   /remote/devices/register
GET    /remote/devices
PATCH  /remote/devices/:deviceId
DELETE /remote/devices/:deviceId

GET    /remote/devices/:deviceId/device-code
POST   /remote/devices/:deviceId/device-code/reset
POST   /remote/device-codes/resolve
POST   /remote/grants/:grantId/approve
POST   /remote/grants/:grantId/reject
DELETE /remote/grants/:grantId

POST   /remote/devices/:deviceId/connect
GET    /remote/connections/:connectionId
POST   /remote/connections/:connectionId/cancel
```

信令长连接：

```text
GET /remote/signaling/ws
```

`/remote/signaling/ws` 必须走登录态和设备态校验，但不能直接套普通 Casbin 逻辑结束后就丢上下文。建议先在普通 JWT 后做 WebSocket upgrade，然后在连接内持续校验 `deviceId`、`connectionId`、`fromDeviceId`、`toDeviceId`。

### 与现有账号体系的关系

第一版可以复用 `accounts` 作为用户表，不新增独立 `users` 表。

映射：

| 方案字段 | 禾屿后端现状 |
| --- | --- |
| `user_id` | `accounts.id` |
| `email` | `accounts.email` |
| `phone` | `accounts.phone` |
| `password_hash` | `accounts.password` |
| `status` | `accounts.enable` |

注意：

- 现有登录是控制台账号登录，不一定等同 C 端用户体系。
- 如果远程能力面向普通用户，建议新增 `remote_users` 或拆出用户中心，避免把普通用户混入后台账号和 Casbin 角色体系。
- 如果先做内部 MVP，可复用 `accounts`，但必须创建最小角色和最小 Casbin 权限，不给控制台菜单权限。

### 表模型调整

建议在文档草案的表名上加 `remote_` 前缀，避免和框架内既有表或未来业务表冲突：

| 原草案 | 建议表名 |
| --- | --- |
| `devices` | `remote_devices` |
| `device_sessions` | `remote_device_sessions` |
| `device_grants` | `remote_device_grants` |
| `device_code_attempts` | `remote_device_code_attempts` |
| `connection_attempts` | `remote_connection_attempts` |
| `subscriptions` | `remote_subscriptions` |
| 审计日志 | `remote_audit_logs` |

关键约束：

- `remote_devices.device_public_key` 必填，后续 DataChannel 应用层握手依赖它。
- `remote_devices.device_code_hash` 必须保存 hash，不保存明文码。
- `remote_device_code_attempts` 记录解析尝试和失败原因，用于限流与审计。
- `remote_device_sessions.connection_id` 应唯一，断线后按状态关闭。
- `remote_connection_attempts` 记录连接状态机，不能只靠内存状态。
- `remote_audit_logs` 只存动作和脱敏 ID，不存聊天正文、文件路径、SDP 明文。

### Redis 使用要求

远程功能需要 Redis，不能沿用当前默认 `system.use-redis: false`：

- 设备在线状态：`remote:device:{deviceId}:online`
- signaling 连接映射：`remote:signal:{deviceId}`
- 设备码解析限流：`remote:device_code:rate:{accountOrIpHash}`
- 连接状态短缓存：`remote:conn:{connectionId}`
- 限流计数：`remote:rate:{scope}:{key}`

如果第一版只跑单实例，可以把在线连接存在进程内 map；但文档和代码必须标注“仅单实例 MVP”。一旦多实例部署，signaling fanout 必须走 Redis pub/sub 或独立消息通道。

### WebSocket/signaling 缺口

后端当前没有 WebSocket 依赖和实现。需要新增：

- WebSocket upgrader 依赖，建议 `github.com/gorilla/websocket` 或 `nhooyr.io/websocket` 二选一。
- `SignalingHub`：维护 `deviceId -> connection`。
- `ConnectionStateMachine`：校验 `pending/accepted/rejected/connected/closed/failed` 状态转换。
- 心跳：服务端 ping/pong，超时清理在线状态。
- 背压：单连接发送队列有上限，慢连接断开。
- graceful shutdown：停止接新连接，关闭已有 signaling 连接并写入离线状态。

### 订阅和 TURN

第一版不建议直接做真实支付，可以先做订阅 mock：

- `remote_subscriptions.status = active/trial/expired`
- `/remote/subscription` 返回当前权益
- `/remote/ice-config` 根据权益返回 STUN/TURN 列表，`/remote/turn/ice-servers` 仅作为兼容 alias

正式版再接支付渠道：

- App Store IAP
- 支付宝/微信
- 后台手工开通

TURN 凭证建议使用 coturn REST API 临时用户名/密码，按用户、设备和连接设置短 TTL。

### 不建议做的事

- 不要把现有 Mac 局域网 HTTP 服务直接暴露公网。
- 不要让 Go API 代理聊天正文作为第一优先方案。
- 不要把 `acm_local_...` 当云端长期 token。
- 不要把设备码明文落库。
- 不要默认给远程登录用户控制台权限。
- 不要在数据库事务里等待 Mac 用户授权或 WebRTC 协商。

## Mac 端改造模块

建议新增：

```text
ClaudeMac/Services/AccountRemote/
  AccountAuthClient.swift
  DeviceIdentityStore.swift
  DeviceRegistrationClient.swift
  DeviceCodeClient.swift
  RemoteGrantStore.swift
  SignalingClient.swift
  PeerConnectionClient.swift
  RemoteConnectionPolicy.swift
```

需要复用：

- `RemoteChatBridge.swift`
- `RemoteChatRouter.swift` 中的数据 DTO 思路
- `RemoteChatServerController.swift` 的本地开关思路
- `SettingsPageView.swift` 远程设置 UI 区域

Mac 端 UI 改造：

- 新增账号登录状态。
- 新增订阅状态。
- 新增设备码展示/复制/重置。
- 新增授权设备列表。
- 新增远程连接策略：关闭、同账号自动允许、跨账号每次询问、跨账号允许任意连接。

## iOS 端改造模块

建议新增：

```text
AcodeIOS/Codevoke/Networking/
  AccountAPIClient.swift
  DeviceAPIClient.swift
  SignalingClient.swift
  PeerConnectionClient.swift

AcodeIOS/Codevoke/Models/
  AccountModels.swift
  DeviceModels.swift
  SubscriptionModels.swift

AcodeIOS/Codevoke/Views/
  LoginView.swift
  DeviceListView.swift
  DeviceCodeView.swift
```

现有设置页迁移：

- 当前 `连接 Mac` 卡片改为高级手动连接。
- 默认入口变为账号登录和设备选择。
- 登录后显示同账号 Mac 列表。
- 设备连接成功后复用现有 ChatViewModel 数据流。

## 里程碑

### M0：方案确认

- Go/admin 框架位置已确认：`后端/server`。
- DB 类型已确认：当前框架默认 MySQL。
- 确认支付渠道。
- 确认第一版是否必须 WebRTC，还是先做账号登录 + 设备发现 + signaling mock。
- 确认远程用户是否复用 `accounts`，还是新增独立 C 端用户表。
- `后端/.git` 已删除，ClaudeMac 主仓库可直接纳管后端源码。

### M1：Go API 骨架

- 复用或改造现有登录/JWT。
- 设备注册。
- 设备列表。
- 订阅状态 mock。
- 远程业务模型和迁移 SQL。
- `biz` 路由注册和 Casbin 权限种子。

### M2：Mac/iOS 登录与设备列表

- Mac 登录。
- iOS 登录。
- Mac 上报在线。
- iOS 看到同账号 Mac。
- 暂不替换聊天通道。

### M3：固定设备码连接

- 桌面端展示固定设备码。
- iOS 输入设备码。
- Mac 允许/拒绝。
- 桌面端支持 `always_ask` / `allow_anyone` 策略。
- 本地授权列表。

### M4：Signaling + P2P

- Go signaling WebSocket。
- Redis 在线状态和连接映射。
- Mac/iOS WebRTC/libdatachannel 集成。
- offer/answer/candidate。
- DataChannel 内复用远程聊天协议。

### M5：付费接入

- 支付下单。
- 支付回调。
- 订阅状态。
- 权益校验。
- TURN 凭证按权益签发。

### M5.5：远程观测与后台管理（2026-05-16）

- 状态：生产 API、后台 API、Dashboard 和远程管理页面已部署验证；本地仍未创建 git commit。
- Git commit：TBD（等待真实提交后补充，不能伪造哈希）。
- 范围：统一后端 `remote_connection_attempts.id` / JSON `connectionId`、连接指标上报、管理端远程用户/设备/连接/协议页面、菜单/API/Casbin 种子、Dashboard SLI、iOS/Mac `connection_id` 调试展示。
- 生产验证摘要：`/remote` 公共与私有 API、`/admin/remote-admin` 管理 API、`/admin/dashboard/panel`、后台 Dashboard 与远程用户/设备/连接/协议页面均已通过验证。
- 菜单修复：生产 `remoteAdmin` 父菜单组件已修正为 router holder component `cmp_59af108da78062d9`，子页面路由可正常展开。
- 验证数据清理：临时管理员、远程用户、设备、连接、token、设备码、同意记录、订阅和临时协议验证数据已清理，未触碰真实 Codevoke 数据。

### M5.6：远程管理体验与状态修正（2026-05-16）

- 状态：工作区改进中，尚未创建 git commit。
- Git commit：TBD（等待真实提交后补充，不能伪造哈希）。
- 范围：iOS Settings 连接路径复用 `DeviceConnectViewModel`，Chat 调试日志展示与运行态判断修正，后台远程设备在线状态与策略编辑，Dashboard 空样本不再显示为 `0.0`。
- 注册约束：手机号注册继续保持 phone + password，不新增必填验证码，也不强制短信校验。
- Deferred：暂不把 `/debug/vars` 直接公开到生产公网；如需运行时 counters，后续单独做带访问控制的 ops endpoint。

### M6：生产化

- 限流。
- 审计。
- 监控。
- 告警。
- 连接成功率统计。
- TURN 成本统计。

## 关键验收指标

- 同账号 iOS 登录后可看到 Mac。
- 不输入 IP/Token 即可发起连接。
- Mac 可拒绝连接。
- Mac 可开启允许任意连接免确认。
- Mac 可撤销授权。
- 未付费用户不能使用跨网络远程能力。
- 付费用户可获取远程连接权益。
- Go API 不保存聊天正文。
- P2P 成功时聊天流量不经过业务服务器。
- P2P 失败时有明确 TURN fallback 或失败提示。

## 观测与 SRE 指标

Go API、Mac App 和 iOS App 都需要带 `request_id`、`connection_id`、`device_id`、`user_id_hash`、`app_version`、`network_type` 等脱敏字段，方便串联登录、设备发现、授权、信令和连接建立过程。

### 核心 SLI

| SLI | 说明 |
| --- | --- |
| 登录成功率 | 登录请求成功数 / 登录请求总数 |
| 设备在线上报成功率 | Mac/iOS 成功注册并保持 signaling 在线的比例 |
| 设备发现成功率 | iOS 登录后能拉到同账号 Mac 的比例 |
| 设备码解析成功率 | 有效设备码成功解析目标设备的比例 |
| 连接建立成功率 | `/connect` 到 DataChannel open 成功的比例 |
| P2P 成功率 | 未走 TURN 即建立 DataChannel 的比例 |
| TURN fallback 比例 | 使用 TURN 才成功连接的比例 |
| 首包延迟 | 用户发起连接到第一个 chat/control 消息可用的耗时 |
| 授权确认耗时 | connect_request 到 Mac allow/reject 的耗时 |

### 推荐指标

- `auth_login_total`
- `auth_login_failed_total`
- `device_register_total`
- `device_online_gauge`
- `device_heartbeat_lag_seconds`
- `device_code_reset_total`
- `device_code_resolved_total`
- `device_code_failed_total`
- `connection_attempt_total`
- `connection_success_total`
- `connection_rejected_total`
- `connection_failed_total`
- `signaling_ws_connected_gauge`
- `signaling_message_total`
- `p2p_success_total`
- `turn_fallback_total`
- `ice_connect_duration_ms`
- `datachannel_open_duration_ms`
- `first_chat_message_latency_ms`

### 告警建议

- 登录错误率连续 5 分钟异常升高。
- signaling WebSocket 在线设备数突降。
- 连接成功率低于目标阈值。
- P2P 成功率突降且 TURN fallback 暴涨。
- TURN 带宽或连接数接近预算上限。
- 设备码失败率异常升高，可能存在撞码或攻击。
- 设备心跳延迟大面积升高。

### 日志与隐私

- 日志不得输出完整 token、设备码、设备私钥、手机号明文。
- `user_id`、`device_id` 对外部观测平台建议 hash 或脱敏。
- signaling payload 不记录完整 SDP 内容，必要时只记录长度、类型和错误码。
- 聊天正文、文件路径和 Claude 输出默认不进 Go API 日志。

### Dashboard

第一版至少准备：

- Auth 看板：登录、注册、token refresh 成功率。
- Device 看板：在线设备、心跳延迟、设备注册失败。
- Device Code 看板：设备码重置、解析、失败原因。
- Connection 看板：连接尝试、成功率、拒绝率、失败原因、耗时分布。
- Network 看板：P2P 成功率、TURN fallback、ICE 耗时、DataChannel open 耗时。
- Billing 看板：订阅状态、付费权益校验失败、支付回调失败。

## 风险与待确认

1. 当前 Go 框架没有 WebSocket/signaling，需要新增长连接管理、心跳、背压、断线清理和优雅停机。
2. 当前 Redis 默认关闭；远程在线状态、设备码解析限流、连接映射和多实例 signaling fanout 都需要 Redis。
3. 现有 `accounts` 是控制台账号体系，不一定适合作为普通远程用户体系；是否复用需要产品确认。
4. Casbin 私有路由默认会拦截所有登录后接口，新增远程接口必须同步 API catalog 和权限种子，否则登录后也可能无权限。
5. P2P 不是 100% 成功，商业版必须考虑 TURN 成本。
6. iOS 后台长连接受系统限制，不能承诺后台长期在线。
7. Mac 睡眠后无法连接，需要明确提示或后续做唤醒策略。
8. 支付渠道未确定，`99 元/年` 只是产品价格目标。
9. 如果走 App Store，数字服务支付可能涉及 Apple IAP 规则，需要单独确认合规。
10. 本地项目权限极高，Mac 端必须保留本地确认和撤销机制。

## 最终建议

不要直接把现有局域网 HTTP 服务改成公网服务。

推荐路径：

```text
保留现有 LAN/IP+Token 模式
  -> 增加账号登录和设备注册
  -> 增加同账号设备发现
  -> 增加固定设备码连接
  -> 增加 signaling
  -> 接入 P2P DataChannel
  -> 接入付费权益和 TURN 兜底
```

这样可以逐步迁移，不会破坏当前 iOS 直连 Mac 的能力，也能为后续商业化远程功能打基础。
