import AppKit
import Foundation

@MainActor
final class DeviceProvisioningViewModel: ObservableObject {
    @Published private(set) var device: RemoteDevice?
    @Published private(set) var deviceCode: String?
    @Published private(set) var deviceCodeHint: String?
    @Published private(set) var isBootstrapping = false
    @Published private(set) var isResettingDeviceCode = false
    @Published private(set) var isSavingDevice = false
    @Published private(set) var signalingStatus: String?
    @Published private(set) var lanPublishStatus: String?
    @Published private(set) var remoteChatDiagnostics = RemoteChatServerDiagnostics()
    @Published var pendingApproval: RemoteConnectionAttempt?
    @Published var deviceNameDraft = ""
    @Published var approvalPolicy: RemoteDeviceApprovalPolicy = .alwaysAsk
    @Published var message: String?
    @Published var messageSeverity: AccountMessageSeverity = .error

    private let client: DeviceRegistrationClient
    private let identityStore: DeviceIdentityStore
    private let signalingClient: SignalingClient
    private let lanTokenPublisher: LanTokenPublisher
    private lazy var tunnelClient = RemoteTunnelClient(signalingClient: signalingClient)
    private var currentSession: RemoteAuthSession?
    private var diagnosticsObserver: NSObjectProtocol?
    private var rememberedApprovalKeys: Set<String> = []
    private var webRTCBridges: [Int: RemoteWebRTCBridge] = [:]
    private var webRTCBridgeStartTasks: [Int: Task<RemoteWebRTCBridge, Error>] = [:]

    init(
        client: DeviceRegistrationClient = DeviceRegistrationClient(),
        identityStore: DeviceIdentityStore = .shared,
        signalingClient: SignalingClient? = nil,
        lanTokenPublisher: LanTokenPublisher? = nil
    ) {
        self.client = client
        self.identityStore = identityStore
        self.signalingClient = signalingClient ?? SignalingClient()
        self.lanTokenPublisher = lanTokenPublisher ?? LanTokenPublisher()
        self.lanTokenPublisher.onSessionRefreshed = { [weak self] session in
            Task { @MainActor in self?.currentSession = session }
        }
        self.lanTokenPublisher.onPublishStatus = { [weak self] status in
            Task { @MainActor in self?.lanPublishStatus = status }
        }
        self.rememberedApprovalKeys = Self.loadRememberedApprovalKeys()
        self.signalingClient.onEvent = { [weak self] event in
            self?.handleSignalingEvent(event)
        }
        remoteChatDiagnostics = RemoteChatServerController.shared.currentDiagnostics()
        diagnosticsObserver = NotificationCenter.default.addObserver(forName: .remoteChatServerDiagnosticsDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.remoteChatDiagnostics = RemoteChatServerController.shared.currentDiagnostics()
        }
    }

    deinit {
        if let diagnosticsObserver {
            NotificationCenter.default.removeObserver(diagnosticsObserver)
        }
    }

    var displayedDeviceCode: String? {
        guard let deviceCode, !deviceCode.isEmpty else { return nil }
        return accountRemoteFormattedDeviceCode(deviceCode)
    }

    func bootstrap(session: RemoteAuthSession) async {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        message = nil
        defer { isBootstrapping = false }

        currentSession = session
        do {
            let identity = try await identityStore.loadOrCreateIdentity()
            let registeredDevice = try await register(identity: identity, accessToken: session.accessToken)
            if identity.deviceID != registeredDevice.id {
                try await identityStore.updateDeviceID(registeredDevice.id)
            }
            applyDevice(registeredDevice)
            try await loadDeviceCode(deviceId: registeredDevice.id, accessToken: session.accessToken)
            if let deviceID = device?.id {
                signalingClient.start(accessToken: session.accessToken, deviceId: deviceID)
                signalingStatus = "信令通道连接中。"
                lanTokenPublisher.start(session: session, deviceId: deviceID)
            }
        } catch {
            messageSeverity = .error
            message = error.localizedDescription
        }
    }

    func resetDeviceCode(session: RemoteAuthSession) async {
        guard let deviceID = device?.id else {
            messageSeverity = .error
            message = "请先登录并注册本机设备。"
            return
        }
        isResettingDeviceCode = true
        message = nil
        defer { isResettingDeviceCode = false }

        do {
            let response = try await client.resetDeviceCode(deviceId: deviceID, accessToken: session.accessToken)
            try await identityStore.saveDeviceCode(response.deviceCode)
            deviceCode = response.deviceCode
            deviceCodeHint = response.hint
            messageSeverity = .success
            message = "设备码已重置。"
        } catch {
            messageSeverity = .error
            message = error.localizedDescription
        }
    }

    func saveDeviceSettings(session: RemoteAuthSession) async {
        guard let deviceID = device?.id else {
            messageSeverity = .error
            message = "请先登录并注册本机设备。"
            return
        }
        let name = deviceNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            messageSeverity = .error
            message = "设备名不能为空。"
            return
        }
        isSavingDevice = true
        message = nil
        defer { isSavingDevice = false }

        do {
            let updated = try await client.updateDevice(
                deviceId: deviceID,
                request: RemoteDeviceUpdateRequest(
                    deviceName: name,
                    approvalPolicy: approvalPolicy.rawValue,
                    remoteEnabled: nil,
                    status: nil,
                    appVersion: accountRemoteAppVersion()
                ),
                accessToken: session.accessToken
            )
            try await identityStore.updateDeviceName(updated.deviceName)
            applyDevice(updated)
            messageSeverity = .success
            message = "设备设置已保存。"
        } catch {
            messageSeverity = .error
            message = error.localizedDescription
        }
    }

    func restartLanTokenPublisher() {
        guard let session = currentSession, let deviceID = device?.id else { return }
        lanTokenPublisher.start(session: session, deviceId: deviceID)
        Task { await lanTokenPublisher.publishNow(session: session, deviceId: deviceID) }
    }

    func clearForLogout(resetProvisionedDevice: Bool = false) async {
        lanTokenPublisher.stop()
        tunnelClient.closeAll(reason: "logout")
        signalingClient.stop()
        for connectionId in webRTCBridges.keys {
            RemoteChatServerController.shared.unregisterWebRTCConnection(connectionId: connectionId)
        }
        webRTCBridges.values.forEach { $0.close() }
        webRTCBridges.removeAll()
        webRTCBridgeStartTasks.values.forEach { $0.cancel() }
        webRTCBridgeStartTasks.removeAll()
        currentSession = nil
        RemoteChatServerController.shared.clearTransientToken()
        device = nil
        deviceCode = nil
        deviceCodeHint = nil
        signalingStatus = nil
        lanPublishStatus = nil
        pendingApproval = nil
        remoteChatDiagnostics = RemoteChatServerController.shared.currentDiagnostics()
        deviceNameDraft = ""
        approvalPolicy = .alwaysAsk
        message = nil
        if resetProvisionedDevice {
            try? await identityStore.clearProvisionedDevice()
        }
    }

    func approvePendingConnection(remember: Bool) async {
        guard let pendingApproval, currentSession != nil else { return }
        await decide(connection: pendingApproval, accepted: true, remember: remember, reason: remember ? "remembered_on_mac" : "approved_once")
        if remember, let fromDeviceID = pendingApproval.fromDeviceId {
            rememberedApprovalKeys.insert(Self.rememberedKey(fromDeviceID: fromDeviceID))
            Self.saveRememberedApprovalKeys(rememberedApprovalKeys)
        }
    }

    func rejectPendingConnection() async {
        guard let pendingApproval else { return }
        await decide(connection: pendingApproval, accepted: false, remember: false, reason: "rejected_on_mac")
    }

    private func decide(connection: RemoteConnectionAttempt, accepted: Bool, remember: Bool, reason: String) async {
        guard let session = currentSession else { return }
        do {
            _ = try await client.decideConnection(connectionId: connection.connectionId ?? connection.id, accepted: accepted, remember: remember, reason: reason, accessToken: session.accessToken)
            pendingApproval = nil
            messageSeverity = accepted ? .success : .info
            message = accepted ? "已允许连接。" : "已拒绝连接。"
        } catch {
            messageSeverity = .error
            message = error.localizedDescription
        }
    }

    private func handleSignalingEvent(_ event: SignalingClient.Event) {
        switch event.type {
        case "hello_ack":
            signalingStatus = "信令通道已连接。"
        case "pending_connect":
            guard let connection = event.connection else { return }
            if let fromDeviceID = connection.fromDeviceId, rememberedApprovalKeys.contains(Self.rememberedKey(fromDeviceID: fromDeviceID)) {
                Task { await decide(connection: connection, accepted: true, remember: false, reason: "local_remembered_auto_approved") }
            } else {
                pendingApproval = connection
                messageSeverity = .info
                message = "收到 iOS 连接请求。"
            }
        case "error":
            signalingStatus = event.message ?? "信令通道异常。"
        case "relay":
            handleRelayEvent(event)
        case "tunnel_open", "tunnel_frame", "tunnel_close", "tunnel_error":
            tunnelClient.handle(event)
        default:
            break
        }
    }

    private func handleRelayEvent(_ event: SignalingClient.Event) {
        if let status = event.status, status != "accepted" { return }
        guard let session = currentSession,
              let payload = event.payload,
              let connectionId = event.connectionId,
              let fromDeviceId = event.fromDeviceId else { return }
        Task {
            do {
                let bridge = try await bridgeForConnection(connectionId: connectionId, peerDeviceId: fromDeviceId, accessToken: session.accessToken)
                bridge.receiveRelayPayload(payload)
            } catch {
                messageSeverity = .error
                message = "远程连接启动失败，请稍后重试。"
            }
        }
    }

    private func bridgeForConnection(connectionId: Int, peerDeviceId: Int, accessToken: String) async throws -> RemoteWebRTCBridge {
        if let existing = webRTCBridges[connectionId] {
            return existing
        }
        if let startTask = webRTCBridgeStartTasks[connectionId] {
            return try await startTask.value
        }

        let startTask = Task { @MainActor [client, signalingClient] () throws -> RemoteWebRTCBridge in
            let bridge = RemoteWebRTCBridge(
                connectionId: connectionId,
                peerDeviceId: peerDeviceId,
                signalingClient: signalingClient
            ) { text, reply in
                RemoteChatServerController.shared.handleWebRTCTextFrame(text, connectionId: connectionId, reply: reply)
            }
            RemoteChatServerController.shared.registerWebRTCSender(connectionId: connectionId) { [weak bridge] text in
                bridge?.sendText(text)
            }
            bridge.onOpen = {
                RemoteChatServerController.shared.pushWebRTCBootstrapSnapshot(connectionId: connectionId)
            }
            bridge.onClose = { [weak self, weak bridge] in
                Task { @MainActor [weak self, weak bridge] in
                    guard let self, let bridge, self.webRTCBridges[connectionId] === bridge else { return }
                    RemoteChatServerController.shared.unregisterWebRTCConnection(connectionId: connectionId)
                    self.webRTCBridges.removeValue(forKey: connectionId)
                    self.webRTCBridgeStartTasks.removeValue(forKey: connectionId)
                }
            }
            let ice = try await client.iceServers(connectionId: connectionId, accessToken: accessToken)
            bridge.start(iceServers: usableICEServers(from: ice.iceServers))
            webRTCBridges[connectionId] = bridge
            return bridge
        }

        webRTCBridgeStartTasks[connectionId] = startTask
        do {
            let bridge = try await startTask.value
            webRTCBridgeStartTasks.removeValue(forKey: connectionId)
            return bridge
        } catch {
            webRTCBridgeStartTasks.removeValue(forKey: connectionId)
            throw error
        }
    }

    private func usableICEServers(from servers: [RemoteICEServer]) -> [RemoteICEServer] {
        servers.compactMap { server in
            let urls = server.urls.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !urls.isEmpty else { return nil }
            return RemoteICEServer(urls: urls, username: server.username, credential: server.credential, realm: server.realm)
        }
    }

    private static func rememberedKey(fromDeviceID: Int) -> String {
        "remote.approval.fromDevice.\(fromDeviceID)"
    }

    private static func loadRememberedApprovalKeys() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "RemoteRememberedApprovalKeys") ?? [])
    }

    private static func saveRememberedApprovalKeys(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys), forKey: "RemoteRememberedApprovalKeys")
    }

    private func applyDevice(_ updatedDevice: RemoteDevice) {
        device = updatedDevice
        deviceNameDraft = updatedDevice.deviceName
        approvalPolicy = RemoteDeviceApprovalPolicy(rawValue: updatedDevice.approvalPolicy) ?? .alwaysAsk
    }

    private func register(identity: DeviceIdentity, accessToken: String) async throws -> RemoteDevice {
        try await client.register(
            request: RemoteDeviceRegisterRequest(
                deviceUid: identity.deviceUID,
                deviceType: "desktop",
                platform: AccountRemoteConfig.platform,
                deviceName: identity.deviceName,
                devicePublicKey: identity.devicePublicKey,
                appVersion: accountRemoteAppVersion()
            ),
            accessToken: accessToken
        )
    }

    private func loadDeviceCode(deviceId: Int, accessToken: String) async throws {
        let response = try await client.deviceCode(deviceId: deviceId, accessToken: accessToken)
        deviceCodeHint = response.hint
        if !response.deviceCode.isEmpty {
            try await identityStore.saveDeviceCode(response.deviceCode)
            deviceCode = response.deviceCode
        } else {
            deviceCode = try await identityStore.loadDeviceCode()
        }
    }
}

enum RemoteDeviceApprovalPolicy: String, CaseIterable, Identifiable {
    case alwaysAsk = "always_ask"
    case allowAnyone = "allow_anyone"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alwaysAsk: "每次询问"
        case .allowAnyone: "允许任意连接"
        }
    }
}
