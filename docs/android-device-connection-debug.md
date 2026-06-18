# Android device connection debug notes

更新时间：2026-05-19

范围：只读排查 Mac 端 `ClaudeMac/Services/AccountRemote`、iOS 端 `AcodeIOS/Codevoke/Networking` / 相关 ViewModel、后端 `后端/server`、官网远程连接说明。本文只沉淀证据和建议，不修改 Android UI 或业务代码。

## 结论

当前协议层有三条硬约束：

1. 设备注册以 `deviceUid` 为唯一幂等键。后端同一个 `deviceUid` 会更新原设备，不会创建第二条设备记录。
2. 发起连接必须先把本机移动端注册成设备，并在 `remote/devices/:deviceId/connect` 请求里带 `fromDeviceId`。缺失时后端直接返回“发起设备不能为空”。
3. 已接受连接分两种返回：LAN 返回 `transport=lan + endpoint + transient_token`；跨网返回 `transport=p2p + reason=remote_transport_required`，客户端必须走 signaling + ICE + WebRTC relay。

所以：

- “一个设备被注册成两个 Mac”在后端语义上通常不是同一个 `deviceUid` 被重复创建，而是客户端发出了不同 `deviceUid`，或者非 Mac 端错误上报了 `deviceType=desktop` / `platform=macos`，被设备列表当成 Mac 过滤出来。
- “Android 无法连接”优先检查 Android 是否完成本机设备注册并持久化 `deviceId`、connect 是否带 `fromDeviceId`、是否正确解析 `transient_token`、是否在 `p2p/turn` 时等待 signaling 并处理 relay。

## 接口字段证据

### Mac 端注册字段

Mac 端注册请求结构只有 6 个字段：

- `deviceUid`
- `deviceType`
- `platform`
- `deviceName`
- `devicePublicKey`
- `appVersion`

证据：

- `ClaudeMac/Services/AccountRemote/RemoteAccountModels.swift:256-263`
- `ClaudeMac/ViewModels/DeviceProvisioningViewModel.swift:381-390`

Mac 当前固定发送：

- `deviceType = "desktop"`
- `platform = AccountRemoteConfig.platform`
- `AccountRemoteConfig.platform = "macos"`

证据：

- `ClaudeMac/ViewModels/DeviceProvisioningViewModel.swift:383-389`
- `ClaudeMac/Services/AccountRemote/RemoteAccountModels.swift:110-112`

Mac 的 `deviceUID` 来自 Keychain 内的 `DeviceIdentity`，首次不存在时生成 UUID；注册成功后保存后端返回的 `deviceID`。

证据：

- `ClaudeMac/Services/AccountRemote/DeviceIdentityStore.swift:67-80`
- `ClaudeMac/Services/AccountRemote/DeviceIdentityStore.swift:83-87`
- `ClaudeMac/ViewModels/DeviceProvisioningViewModel.swift:68-91`

### iOS 端注册字段

iOS 端使用同一套注册字段，但本机移动端固定发送：

- `deviceType = "ios"`
- `platform = RemoteAPIConfig.platform`
- `RemoteAPIConfig.platform = "ios"`

证据：

- `AcodeIOS/Codevoke/Models/RemoteAuthModels.swift:169-176`
- `AcodeIOS/Codevoke/ViewModels/AuthViewModel.swift:440-456`
- `AcodeIOS/Codevoke/Networking/RemoteAPIClient.swift:32-35`

### 后端注册语义

后端请求结构与 Mac/iOS 对齐：

- `RemoteDeviceRegisterRequest.DeviceUID json:"deviceUid"`
- `DeviceType json:"deviceType"`
- `Platform json:"platform"`
- `DeviceName json:"deviceName"`
- `DevicePublicKey json:"devicePublicKey"`
- `AppVersion json:"appVersion"`

证据：

- `后端/server/model/biz/request/remote.go:38-45`

后端表结构对 `device_uid` 建唯一索引：

- `RemoteDevice.DeviceUID gorm:"uniqueIndex"`
- migration 中 `UNIQUE KEY idx_remote_devices_device_uid (device_uid)`

证据：

- `后端/server/model/biz/remote_models.go:47-52`
- `后端/server/migrations/001_remote_core.sql:33-55`

后端注册逻辑：

- 先按 `device_uid` 查已有设备。
- 如果已有设备属于其他用户，返回“设备已绑定其他账号”。
- 如果属于当前用户，则更新 `device_type/platform/device_name/device_public_key/app_version/last_seen_at` 并返回原设备。
- 只有 `device_uid` 查不到时才创建新设备。

证据：

- `后端/server/service/biz/remote.go:267-313`

推论：同一账号下同一个 `deviceUid` 正常不会产生两条 Mac 设备。出现重复 Mac，重点看两条记录的 `deviceUid` 是否不同。

## 连接协议证据

### 设备列表只按客户端字段过滤 Mac

iOS 端设备列表从 `remote/devices` 拉全量设备，然后本地过滤：

```swift
.filter { $0.deviceType == "desktop" || $0.platform == "macos" }
```

证据：

- `AcodeIOS/Codevoke/ViewModels/DeviceListViewModel.swift:39-45`

风险：这里是 `OR`。只要某个客户端错误注册了 `deviceType=desktop` 或 `platform=macos`，就会被展示成可连接 Mac。Android 如果复用了 Mac 注册参数，就会在列表里表现为“又多了一台 Mac”。

### 连接请求必须带 fromDeviceId

iOS 连接前先从 Keychain 读取本机身份，要求存在已注册的 `deviceID`，然后请求：

- POST `remote/devices/{deviceId}/connect`
- body: `fromDeviceId`, `fromDeviceUid`, `fromDevicePublicKey`

证据：

- `AcodeIOS/Codevoke/Networking/RemoteDeviceClient.swift:37-50`
- `AcodeIOS/Codevoke/Models/RemoteAuthModels.swift:290-294`

后端实际只绑定 `fromDeviceId`：

- `RemoteConnectRequest.FromDeviceID json:"fromDeviceId"`

证据：

- `后端/server/model/biz/request/remote.go:60-62`

后端 `Connect` 明确要求 `FromDeviceID != 0`，并调用 `validFromDeviceID(userID, req.FromDeviceID)` 校验该设备属于当前用户。

证据：

- `后端/server/service/biz/remote.go:492-506`
- 测试覆盖缺失 `fromDeviceId` 不创建连接记录：`后端/server/service/biz/remote_test.go:80-91`

风险：Android 如果登录后没有像 iOS 一样先注册本机设备、保存返回的 `device.id`，或 connect body 没带 `fromDeviceId`，连接会在后端入口失败。

### LAN 成功返回字段

后端连接成功后，如果目标 Mac 发布了 LAN token，则返回：

- `status = accepted`
- `transport = lan`
- `endpoint`
- `transient_token`

证据：

- `后端/server/service/biz/remote.go:670-686`
- `后端/server/model/biz/response/remote.go:96-112`

注意：字段名是 snake case 的 `transient_token`，不是 `transientToken`。iOS 兼容解码两种字段：

- `transientToken`
- `transient_token`

证据：

- `AcodeIOS/Codevoke/Models/RemoteAuthModels.swift:340-379`

风险：Android 如果只按 camelCase 解析 `transientToken`，LAN 连接会表现为“已允许，但拿不到电脑连接地址/令牌”。

### P2P / TURN 成功返回语义

如果没有可用 LAN endpoint，后端会检查跨网权益和目标设备是否 signaling 在线：

- 没权限：返回 rejected + entitlement reason。
- 目标 signaling 离线：返回 rejected + `reason=device_offline`。
- 可跨网：返回 accepted + `reason=remote_transport_required` + `transport=p2p`。

证据：

- `后端/server/service/biz/remote.go:689-729`
- 常量定义：`后端/server/service/biz/remote.go:42-46`
- 测试覆盖 P2P 和离线拒绝：`后端/server/service/biz/remote_test.go:134-184`

iOS 对 `p2p/turn/remote_transport_required` 的处理：

- 等待 signaling connected。
- GET `remote/ice-config?connectionId=...`
- 创建 `RemoteWebRTCTransport`。
- 设置 `signalingClient.onRelay`。
- `transport.connect()` 后等待 DataChannel ready。

证据：

- `AcodeIOS/Codevoke/ViewModels/DeviceConnectViewModel.swift:106-180`
- `AcodeIOS/Codevoke/ViewModels/DeviceConnectViewModel.swift:286-299`
- `AcodeIOS/Codevoke/Networking/SignalingClient.swift:119-141`

风险：Android 如果只实现了 LAN WebSocket，或者 P2P 时没有等 signaling、没有拉 ICE、没有处理 relay，就会在跨网场景必然无法连接。

### Mac 端 signaling 和 LAN 发布

Mac 登录/启动远程后：

- 若本地已有 `deviceID`，先尝试拉设备码；失败才重新注册。
- 注册成功后启动 signaling。
- 周期性发布 LAN token。

证据：

- `ClaudeMac/ViewModels/DeviceProvisioningViewModel.swift:60-99`
- `ClaudeMac/ViewModels/DeviceProvisioningViewModel.swift:296-343`

Mac 收到 `pending_connect` 后弹出/处理授权；收到 `relay` 后为对应连接创建 `RemoteWebRTCBridge` 并接入本机 RemoteChatServer。

证据：

- `ClaudeMac/ViewModels/DeviceProvisioningViewModel.swift:216-268`

后端 signaling：

- WebSocket 地址：`/remote/signaling/ws?token=...`
- 客户端必须先发 `{type:"hello", deviceId}`。
- 后端校验 `deviceId` 属于当前用户且设备 active/remoteEnabled。
- 每个 deviceId 只保留一个 signaling 连接，新连接会踢旧连接。
- relay 要求 connectionId、toDeviceId、payload，且发送方必须是连接双方之一。

证据：

- `后端/server/router/biz/remote.go:25`
- `后端/server/service/biz/remote_signaling.go:133-164`
- `后端/server/service/biz/remote_signaling.go:206-233`
- `后端/server/service/biz/remote_signaling.go:235-243`

## 重复设备原因判断

### 已确认

后端同一个 `deviceUid` 是幂等更新，不应创建重复记录。

证据：

- `后端/server/service/biz/remote.go:278-295`
- `后端/server/migrations/001_remote_core.sql:51-52`

### 高概率原因 1：客户端产生了新的 deviceUid

Mac/iOS 的设备身份保存在 Keychain。首次无身份会生成新 UUID。若 Keychain 身份丢失、读不到、被清理、不同签名/entitlement 导致读取了不同 Keychain 域，就会生成新 `deviceUid`，后端会认为这是新设备。

证据：

- Mac 生成 UUID：`ClaudeMac/Services/AccountRemote/DeviceIdentityStore.swift:67-80`
- iOS 生成 UUID：`AcodeIOS/Codevoke/Networking/DeviceIdentityStore.swift:50-64`

建议：

- 在 Mac 端调试日志里打印脱敏后的 `deviceUID` 前后 8 位、`deviceID`、Keychain 读取来源，确认重复记录是不是不同 UID。
- 若发现 Keychain 双来源并存，Mac 端应优先选择带 `deviceID` 的 identity，并做一次迁移/合并。
- 后端后台可以增加“同用户同 platform/deviceName 多设备”诊断，不直接自动合并，避免误合并真实多台电脑。

### 高概率原因 2：Android 误注册成 desktop/macos

iOS 列表用 `deviceType == "desktop" || platform == "macos"` 过滤。后端只信客户端上报字段，注册时不会校验 `deviceType/platform` 枚举组合。

证据：

- iOS 列表过滤：`AcodeIOS/Codevoke/ViewModels/DeviceListViewModel.swift:43-44`
- 后端注册只 trim 并存储：`后端/server/service/biz/remote.go:267-313`

建议：

- Android 本机设备注册应使用 `deviceType="android"`、`platform="android"`，不要复用 Mac 的 `desktop/macos`。
- 后端建议补枚举校验：`desktop` 只允许 `macos/windows`，移动端只允许 `ios/android`。
- 设备列表建议改成严格过滤 `deviceType == "desktop"`，展示平台再用 `platform`，不要用 `OR` 放大错误上报影响。

## Android 连接必须满足的协议清单

Android 后续修复应逐项对齐：

1. 登录/刷新 session 成功后，先注册 Android 本机设备：
   - `deviceUid`：本机持久化稳定 UUID
   - `deviceType`：`android`
   - `platform`：`android`
   - `deviceName`：Android 设备名
   - `devicePublicKey`：本机公钥
   - `appVersion`：版本号
2. 保存后端返回的 `device.id`，作为后续 `fromDeviceId`。
3. 解析设备列表时只展示 Mac/桌面目标，不展示本机 Android。
4. POST `remote/devices/{targetDeviceId}/connect` 必须带 `fromDeviceId`。
5. 如果返回 `pending`，同时等 push `connect_decision` 和轮询 `GET remote/connections/{id}`。
6. 如果返回 `transport=lan`，必须读取：
   - `endpoint.ip`
   - `endpoint.port`
   - `transient_token`
7. 如果返回 `transport=p2p` / `turn` 或 `reason=remote_transport_required`：
   - 等待 signaling hello_ack
   - 拉 `remote/ice-config?connectionId=...`
   - 建 WebRTC DataChannel
   - 通过 signaling relay 交换 offer/answer/ICE
8. 如果返回 `reason=device_offline`，说明 Mac 端 signaling 不在线，不是 Android UI 问题。

## 静态验证记录

已执行的只读命令：

- `curl -fsS https://skills.anna.vin/api/v1/manifest`
- `rg --files ClaudeMac/Services/AccountRemote AcodeIOS/Codevoke/Networking`
- `rg -n "remote/devices|devices/register|devices/.*/connect|device-codes|turn/ice|signaling" ...`
- 多个 `nl -ba ... | sed -n ...` 读取 Mac/iOS/后端/官网证据行。

未执行：

- 未跑真机连接。
- 未跑后端测试。
- 未改 Android UI。
- 未改任何代码。

## 下一步建议

优先让 Android worker 按本文协议清单做静态自检，尤其是：

1. 当前 Android 注册请求里的 `deviceType/platform`。
2. 当前 Android 是否保存并复用后端返回的本机 `device.id`。
3. connect body 是否带 `fromDeviceId`。
4. LAN 分支是否解析 `transient_token`。
5. P2P 分支是否在 signaling ready 后再建 WebRTC relay。

如果要验证重复设备，建议从后端或管理台导出同账号下两条“Mac”的 `id/device_uid/device_type/platform/device_name/created_at/updated_at`。如果 `device_uid` 不同，优先查客户端身份持久化；如果 `device_uid` 相同，则说明数据库唯一索引或软删除/迁移状态存在异常，需要单独查 DB。
