# Android 静态/构建验证线

验证时间：2026-05-19  
范围：只读检查 Android 当前导航、返回、设备连接状态入口，并跑静态/构建命令。  
写入边界：本文件；未改 Kotlin、Gradle、Manifest 或 iOS 源码。

## 结论

当前 Android 工程可以编译并打出 Debug 包。用户反馈的“侧滑触发系统返回退出”在当前静态代码里已经有两层拦截：应用级 `BackHandler` 和侧栏级 `BackHandler`；但仍必须在真机/模拟器手势导航下复测。设备重复注册的旧风险也已被当前代码收敛为“稳定 deviceUid + 注册前查重”，但服务端既有重复设备不会被客户端自动清理。设备无法连接仍有一个静态高风险点：P2P/TURN 分支启动 WebRTC 后立即回到聊天页，没有像 iOS 一样等待 DataChannel 可发送后再判定连接成功。

## 命中技能

must：
- `project-learning`：需要先读项目入口、导航、连接链路；本步骤实际只读项目证据；无 anti trigger；用户未否定。
- `android-development`：目标是 Android Compose 页面、BackHandler、Gradle 构建；本步骤实际读 `.kt`、跑 Gradle；无 anti trigger；用户未否定。
- `kotlin-development`：目标包含 Kotlin 调用链和构建验证；本步骤实际检查 Kotlin 状态/数据结构；无 anti trigger；用户未否定。
- `test-engineering`：用户明确要求静态/构建验证线和测试矩阵；本步骤实际产出矩阵；无 anti trigger；用户未否定。
- `code-audit`：用户要求记录可复现问题和风险；本步骤实际做静态审计；无 anti trigger；用户未否定。
- `ui-architecture`：目标包含页面导航、返回路径、侧滑抽屉；本步骤实际检查信息架构和返回路径；无 anti trigger；用户未否定。

conditional：
- `api-engineering`：后续若要改连接接口、设备去重协议、错误码时再启用。
- `mobile-security`：后续若要处理 token、设备指纹、信令 URL 安全时再启用。
- `perf-engineering`：后续若要压测连接耗时、P2P/TURN 首包延迟时再启用。
- `design-audit`：后续若要逐截图验证抽屉/页面视觉时再启用。

## 证据摘要

### Manifest / raw

- `GET https://skills.anna.vin/api/v1/manifest` 成功，`meta.total=140`。
- raw 状态：`project-learning 200`、`android-development 200`、`kotlin-development 200`、`test-engineering 200`、`code-audit 200`、`ui-architecture 200`。

### 构建命令

```bash
./gradlew :android:compileDebugKotlin --no-daemon
```

结果：`BUILD SUCCESSFUL in 10s`，`14 actionable tasks: 14 up-to-date`。

```bash
./gradlew :android:assembleDebug --no-daemon
```

结果：`BUILD SUCCESSFUL in 10s`，`35 actionable tasks: 4 executed, 31 up-to-date`。

```bash
./gradlew :android:testDebugUnitTest --no-daemon
```

结果：`BUILD SUCCESSFUL in 6s`，但 `compileDebugUnitTestKotlin NO-SOURCE`、`testDebugUnitTest NO-SOURCE`，当前没有单元测试覆盖。

## 导航 / 返回静态检查

### 当前代码状态

- `AcodeApp.kt` 已引入 `BackHandler`，并在 `screen != AcodeScreen.Login` 时接管系统返回：`Android/app/src/main/java/com/acode/android/ui/screens/AcodeApp.kt:3`、`:76`。
- `AcodeApp.kt` 当前有本地 `backStack`、`navigateTo`、`navigateBack`、`replaceScreen`：`AcodeApp.kt:32-52`。
- `handleBack()` 对各页面有明确 fallback：注册/忘记密码回登录，设备/设置回聊天，设备码回设备页，账号/协议回设置，修改密码/注销回账号：`AcodeApp.kt:54-67`。
- Chat 页在侧栏打开时有单独 `BackHandler` 关闭侧栏：`Android/app/src/main/java/com/acode/android/ui/screens/ChatScreen.kt:116-119`。
- Chat 页左侧 32dp 热区与遮罩都加了 `systemGestureExclusion()`，并使用横向拖动打开/关闭侧栏：`ChatScreen.kt:148-170`、`:211-235`。

### 静态判断

- 用户反馈的“系统侧滑返回导致退到桌面”在当前代码里不应再由普通系统 Back 触发：Chat 页 `BackHandler` enabled，`handleBack()` 对 Chat 是 `Unit`，不会退出 Activity。
- 仍需真机确认：Android 手势导航对边缘排除区有系统限制，`systemGestureExclusion()` 不等于所有设备/系统版本都完全接管左边缘。
- 当前 `screen` 和 `backStack` 使用 `remember`，不是 `rememberSaveable`。Manifest 锁定竖屏，但进程重建后页面栈仍会丢失；这不是用户当前主诉，但属于导航恢复风险。

## 设备注册静态检查

### 当前代码状态

- 本机身份持久化在 `LocalDeviceIdentityStore`，使用 SharedPreferences：`Android/app/src/main/java/com/acode/android/data/AcodeStores.kt:38-66`。
- `deviceUid` 当前优先从 SharedPreferences 读取；没有时用 `ANDROID_ID` + packageName 做 SHA-256，生成稳定 `android-...`：`AcodeStores.kt:83-90`。
- `devicePublicKey` 仍为首次生成 UUID 并持久化：`AcodeStores.kt:50-53`。
- 注册前会先查缓存的 `deviceId`，再查 `remote/devices` 里是否已有相同 `deviceUid` 的 Android 设备，最后才调用 `api.registerDevice`：`Android/app/src/main/java/com/acode/android/ui/state/AcodeViewModel.kt:787-801`。
- 本地匹配条件是 `deviceUid == identity.deviceUid` 且 `deviceType == android` 或 `platform == android`：`AcodeViewModel.kt:804-808`。
- register 请求体包含 `deviceUid`、`deviceType=android`、`platform=android`、`deviceName`、`devicePublicKey`、`appVersion=1.0`：`Android/app/src/main/java/com/acode/android/data/RemoteApiClient.kt:80-91`。

### 静态判断

- 当前代码已经避免“每次启动都随机 deviceUid”这个客户端侧重复注册原因。
- 客户端不会清理服务端已有重复设备；如果 Mac 端已经显示两个 Android 设备，需要后端或后台按 `userId + deviceUid + platform/deviceType` 合并/禁用旧记录。
- 注册幂等最终仍依赖服务端：如果服务端 `remote/devices/register` 不按 `deviceUid` 幂等，客户端查重和注册之间仍存在并发窗口。

## 设备连接静态检查

### 当前代码状态

- 设备码解析前会确保本机设备已注册，并启动 signaling：`AcodeViewModel.kt:425-437`。
- 设备连接前也会确保本机设备已注册：`AcodeViewModel.kt:443-450`。
- pending 授权会等待 push decision 或轮询 connection：`AcodeViewModel.kt:451-452`、`:845-855`。
- LAN 分支需要 endpoint + transient token，随后设置 `RemoteChatConfig` 并 `connectRemoteChat(config)`：`AcodeViewModel.kt:459-473`。
- P2P/TURN 分支会等待 signaling、拉 ICE、创建 WebRTC transport、设置 relay，再 `transport.connect(...)`：`AcodeViewModel.kt:600-633`。
- Android `RemoteChatConfig.isComplete` 对 relay 只要求 `transport` 非空：`Android/app/src/main/java/com/acode/android/data/RemoteModels.kt:109-128`。

### 剩余验证风险

1. **连接 ready 等待已在静态代码中补齐，仍需真机验证**
   - Android LAN 分支会在 `connectRemoteChat(config)` 后等待 `waitForDirectRemoteChatReady()`；超时会断开并留在设备页提示。
   - Android P2P/TURN 分支会在 `transport.connect(...)` 后等待 `waitForRemoteTransportReady(transport)`；信令断开或超时会断开并留在设备页提示。
   - 风险：仍需真机覆盖 LAN 失败、P2P relay 超时、电脑端拒绝等端到端状态。

2. **自动化回归覆盖仍不完整**
   - Compose instrumentation 已覆盖设备行在线/离线连接入口的基本真值展示。
   - 返回栈、设备去重、连接状态转移仍缺本地单测或 UI 测试。

## 建议测试矩阵

| 编号 | 类型 | 前置 | 操作 | 预期 | 当前验证状态 |
|---|---|---|---|---|---|
| NAV-01 | 手势返回 | 已登录在 Chat | Android 系统返回手势/返回键 | 不退桌面，停留 Chat | 静态有 BackHandler，未真机 |
| NAV-02 | 侧栏打开 | Chat 侧栏已打开 | 系统返回手势/返回键 | 只关闭侧栏，不退出应用 | 静态有侧栏 BackHandler，未真机 |
| NAV-03 | 左边缘侧滑 | Chat 侧栏关闭 | 从左侧 0-32dp 向右拖动 | 打开侧栏，不触发系统返回 | 静态有热区和排除，未真机 |
| NAV-04 | 子页返回 | 设置/设备/账号/协议页 | 系统返回 | 回到设计 fallback 页 | 静态路径明确，未真机 |
| NAV-05 | 进程重建 | 任一子页 | 杀进程或系统回收后恢复 | 页面栈不应误跳 | 当前风险：remember 非 saveable |
| DEV-01 | 首次登录注册 | 清 app 数据后登录 | 观察 register 请求和设备列表 | 只产生一个 Android 设备 | 静态已稳定 UID，未联网实测 |
| DEV-02 | 重复启动 | 已登录，杀进程重启 app | bootstrap 注册设备 | 不新增设备，复用 deviceId/deviceUid | 静态有查重，未联网实测 |
| DEV-03 | 卸载重装 | 同一签名同一设备重装后登录 | 观察 Mac 端设备数 | 理想仍复用同一 deviceUid；旧重复需服务端清理 | 静态依赖 ANDROID_ID，未联网实测 |
| DEV-04 | 设备码连接 | Mac 显示设备码 | Android 输入设备码并连接 | 能解析并发起连接；失败原地提示 | 静态入口存在，未联网实测 |
| CONN-01 | LAN 成功 | 同局域网 Mac 在线 | 点“连接” | 连接成功后进入 Chat 且状态已连接 | 构建通过，需真机 |
| CONN-02 | LAN 失败 | Mac 离线或 token 无效 | 点“连接” | 不应假成功进入 Chat；应明确错误 | 当前静态有先切页风险 |
| CONN-03 | P2P/TURN 成功 | 非同局域网或直连不可用 | 点“连接”并电脑端允许 | DataChannel ready 后进入 Chat | 当前缺 ready 等待 |
| CONN-04 | P2P/TURN 超时 | 阻断 relay/ICE | 点“连接” | 20s 左右超时并留在设备页提示 | 静态已补等待，需真机 |
| CONN-05 | 电脑端拒绝 | 连接请求被拒绝 | 点“连接” | Android 显示拒绝原因，不进入 Chat | 需后端/真机 |

## 下一步建议

1. 修复连接体验：Android 对 LAN WebSocket 和 P2P/TURN DataChannel 都应“成功 ready 后再切 Chat”，失败留在设备页展示错误。
2. 服务端核对重复设备：按同账号下 `deviceUid/platform/deviceType` 查已有重复记录，确定是否需要合并、软删或注册接口幂等修复。
3. 真机验证手势：至少覆盖 Android 13/14/15 手势导航；重点测左边缘 0-32dp、侧栏打开时返回、Chat 根页返回。
4. 补自动化：为 `AcodeApp` 返回栈和 `LocalDeviceIdentityStore` 稳定 UID/查重逻辑补最小单测；为连接状态转移补 ViewModel 测试。
