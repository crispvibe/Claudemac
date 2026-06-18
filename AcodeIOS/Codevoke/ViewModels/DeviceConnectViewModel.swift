import Foundation

@MainActor
final class DeviceConnectViewModel: ObservableObject {
    @Published private(set) var isResolvingCode = false
    @Published private(set) var isConnecting = false
    @Published private(set) var resolvedDevice: RemoteDeviceResolveResponse?
    @Published private(set) var latestConnectionId: Int?
    @Published private(set) var latestTransport: String?
    @Published private(set) var latestReason: String?
    @Published var deviceCode = ""
    @Published var message: String?

    private let client: RemoteDeviceClient
    private let signalingClient: SignalingClient
    private var decisionContinuations: [Int: CheckedContinuation<RemoteConnectionAttempt, Error>] = [:]
    private var bufferedDecisions: [Int: RemoteConnectionAttempt] = [:]
    private var pendingConnectionId: Int?
    private let pendingApprovalTimeout: TimeInterval = 60
    private let remoteTransportReadyTimeout: TimeInterval = 20
    private let connectionPollDelays: [UInt64] = [2, 3, 5, 8, 10, 10, 10, 10]

    init(client: RemoteDeviceClient = RemoteDeviceClient(), signalingClient: SignalingClient? = nil) {
        self.client = client
        self.signalingClient = signalingClient ?? .shared
        self.signalingClient.onConnectDecision = { [weak self] connection in
            self?.handleDecision(connection)
        }
    }

    deinit {
        decisionContinuations.values.forEach { $0.resume(throwing: CancellationError()) }
        decisionContinuations.removeAll()
    }

    func resolveDeviceCode(session: RemoteAuthSession?) async {
        guard let session else { return }
        let code = deviceCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            message = L10n.string("请输入设备码。")
            return
        }
        isResolvingCode = true
        message = nil
        defer { isResolvingCode = false }

        do {
            resolvedDevice = try await client.resolveDeviceCode(code, accessToken: session.accessToken)
            message = L10n.format("已找到 %@。", resolvedDevice?.deviceName ?? L10n.string("目标设备"))
        } catch {
            resolvedDevice = nil
            message = authErrorMessage(error, fallback: "设备码解析失败。")
        }
    }

    func connect(deviceId: Int, session: RemoteAuthSession?, device: RemoteDevice? = nil) async -> RemoteChatConfig? {
        guard let session, !isConnecting else {
#if DEBUG
            print("[CodevokeConnect] connect skipped deviceId=\(deviceId) hasSession=\(session != nil) isConnecting=\(isConnecting)")
#endif
            return nil
        }
        isConnecting = true
        message = nil
        defer {
            clearPendingWait(throwing: CancellationError())
            isConnecting = false
        }

        do {
#if DEBUG
            print("[CodevokeConnect] connect start deviceId=\(deviceId)")
#endif
            var latestDevice = try? await client.device(deviceId: deviceId, accessToken: session.accessToken)
            if LanNetworkSelector.isOnWifi(),
               let preLAN = directChatConfig(from: latestDevice, transportLabel: "lan"),
               preLAN.isPrivateLANConfig {
                message = L10n.string("正在建立局域网直连。")
                if let ready = try? await establishDirectTransport(preLAN) {
                    return ready
                }
            }

            var connection = try await client.connect(deviceId: deviceId, accessToken: session.accessToken)
            updateLatestConnection(connection)
#if DEBUG
            print("[CodevokeConnect] initial status=\(connection.status) connectionId=\(connection.connectionId ?? connection.id) transport=\(connection.transport ?? "nil") reason=\(connection.reason ?? "nil") endpoint=\(connection.endpoint?.ip ?? "nil"):\(connection.endpoint?.port ?? -1)")
#endif
            if connection.status == "pending" {
                let connectionId = connection.connectionId ?? connection.id
                pendingConnectionId = connectionId
                message = L10n.string("连接请求已发送，请在电脑端允许。")
                connection = try await waitForDecision(connectionId: connectionId, accessToken: session.accessToken)
                updateLatestConnection(connection)
#if DEBUG
                print("[CodevokeConnect] resolved status=\(connection.status) connectionId=\(connection.connectionId ?? connection.id) transport=\(connection.transport ?? "nil") reason=\(connection.reason ?? "nil") endpoint=\(connection.endpoint?.ip ?? "nil"):\(connection.endpoint?.port ?? -1)")
#endif
            }
            guard connection.status == "accepted" else {
                message = message(for: connection)
#if DEBUG
                print("[CodevokeConnect] rejected status=\(connection.status) message=\(message ?? "nil")")
#endif
                return nil
            }
            if let reason = connection.reason,
               let mappedMessage = userFacingReasonMessage(reason),
               shouldBlockAcceptedConnection(reason) {
                message = mappedMessage
#if DEBUG
                print("[CodevokeConnect] blocked reason=\(reason) message=\(mappedMessage)")
#endif
                return nil
            }

            let connectionId = connection.connectionId ?? connection.id
            guard let toDeviceId = connection.toDeviceId else {
                message = L10n.string("连接信息不完整，请重新发起连接。")
                return nil
            }

            latestDevice = (try? await client.device(deviceId: deviceId, accessToken: session.accessToken)) ?? latestDevice ?? device

            var lanFailure: Error?
            var triedLANEndpoints = Set<String>()

            func tryLANCandidate(_ config: RemoteChatConfig) async -> RemoteChatConfig? {
                guard config.isPrivateLANConfig else { return nil }
                let key = "\(config.macHost):\(config.port):\(config.token)"
                guard !triedLANEndpoints.contains(key) else { return nil }
                triedLANEndpoints.insert(key)
                message = L10n.string("正在建立局域网直连。")
                do {
                    return try await establishDirectTransport(config)
                } catch {
                    if lanFailure == nil { lanFailure = error }
#if DEBUG
                    print("[CodevokeConnect] lan failed connectionId=\(connectionId): \(error.localizedDescription)")
#endif
                    return nil
                }
            }

            if LanNetworkSelector.isOnWifi(),
               let signalingLANConfig = await resolveSignalingLANConfig(
                connection: connection,
                connectionId: connectionId,
                toDeviceId: toDeviceId,
                session: session
               ) {
                if let ready = await tryLANCandidate(signalingLANConfig) { return ready }
            }

            if let attemptLAN = directChatConfig(
                from: connection,
                connectionId: connectionId,
                toDeviceId: toDeviceId,
                session: session,
                transportLabel: "lan"
            ) {
                if let ready = await tryLANCandidate(attemptLAN) { return ready }
            }

            if let deviceLAN = directChatConfig(from: latestDevice, transportLabel: "lan") {
                if let ready = await tryLANCandidate(deviceLAN) { return ready }
            }

            return try await establishRelayOrPublicFallback(
                connection: connection,
                deviceId: deviceId,
                device: device,
                session: session,
                connectionId: connectionId,
                toDeviceId: toDeviceId,
                lanFailure: lanFailure
            )
        } catch is PendingApprovalTimeoutError {
            message = L10n.string("等待电脑端确认超时，请确认设备在线后重试。")
#if DEBUG
            print("[CodevokeConnect] pending approval timeout")
#endif
            return nil
        } catch is CancellationError {
            message = L10n.string("连接请求已取消。")
#if DEBUG
            print("[CodevokeConnect] cancelled")
#endif
            return nil
        } catch {
            message = authErrorMessage(error, fallback: "连接请求失败。")
#if DEBUG
            print("[CodevokeConnect] failed: \(error.localizedDescription)")
#endif
            return nil
        }
    }

    private func establishRelayOrPublicFallback(
        connection: RemoteConnectionAttempt,
        deviceId: Int,
        device: RemoteDevice?,
        session: RemoteAuthSession,
        connectionId: Int,
        toDeviceId: Int,
        lanFailure: Error?
    ) async throws -> RemoteChatConfig? {
        var crossNetworkFailure: Error?

        message = L10n.string("正在建立远程通道。")
        do {
            let config = try await establishTunnelTransport(
                connectionId: connectionId,
                toDeviceId: toDeviceId,
                session: session,
                connection: connection
            )
            if let note = lanFallbackNote(lanFailure: lanFailure) {
                message = note
            }
            return config
        } catch {
            crossNetworkFailure = error
#if DEBUG
            print("[CodevokeConnect] tunnel failed connectionId=\(connectionId): \(error.localizedDescription)")
#endif
        }

        message = L10n.string("正在建立远程直连。")
        do {
            return try await establishP2PTransport(
                connectionId: connectionId,
                toDeviceId: toDeviceId,
                session: session,
                connection: connection
            )
        } catch {
            crossNetworkFailure = error
#if DEBUG
            print("[CodevokeConnect] p2p failed connectionId=\(connectionId): \(error.localizedDescription)")
#endif
        }

        if let publicConfig = try await publicDirectFallbackConfig(
            deviceId: deviceId,
            device: device,
            session: session,
            connectionId: connectionId,
            toDeviceId: toDeviceId,
            connection: connection
        ) {
            message = L10n.string("正在尝试公网端口直连。")
            do {
                return try await establishDirectTransport(publicConfig)
            } catch {
                let prefix = lanFailure == nil ? "直连未建立成功。" : "局域网和远程连接都未建立成功。"
                message = L10n.string("\(prefix)请确认电脑端在线，并检查是否在同一 Wi‑Fi、已配置路由器端口映射，或稍后重试。")
#if DEBUG
                print("[CodevokeConnect] public direct failed connectionId=\(connectionId): \(error.localizedDescription)")
#endif
                return nil
            }
        }

        if let crossNetworkFailure {
            message = authErrorMessage(crossNetworkFailure, fallback: "远程直连建立失败，请确认电脑端在线后重试。")
            return nil
        }

        message = L10n.string("连接已允许，但暂时拿不到电脑的连接地址，请稍后重试。")
        return nil
    }

    private func establishTunnelTransport(
        connectionId: Int,
        toDeviceId: Int,
        session: RemoteAuthSession,
        connection: RemoteConnectionAttempt
    ) async throws -> RemoteChatConfig {
        try await signalingClient.waitUntilConnected(timeout: 8)
        let transport = RemoteTunnelTransport(
            connectionId: connectionId,
            targetDeviceId: toDeviceId,
            signalingClient: signalingClient
        )
        let signalingGeneration = signalingClient.connectionGeneration
        try transport.connect()
        try await waitForTransportReady(transport, signalingGeneration: signalingGeneration)

        latestTransport = "tunnel"
        return RemoteChatConfig(
            macHost: "",
            port: 0,
            token: session.accessToken,
            connectionId: connectionId,
            targetDeviceId: toDeviceId,
            transport: "tunnel",
            reason: connection.reason,
            remoteAccessToken: session.accessToken,
            remoteAPIBaseURL: RemoteAPIConfig.baseURL,
            remoteTransport: transport,
            remoteRelayReady: true
        )
    }

    private func resolveSignalingLANConfig(
        connection: RemoteConnectionAttempt,
        connectionId: Int,
        toDeviceId: Int,
        session: RemoteAuthSession
    ) async -> RemoteChatConfig? {
        do {
            try await signalingClient.waitUntilConnected(timeout: 8)
        } catch {
            return nil
        }

        return await withCheckedContinuation { continuation in
            var completed = false

            func finish(_ config: RemoteChatConfig?) {
                guard !completed else { return }
                completed = true
                signalingClient.removeTunnelHandler(connectionId: connectionId)
                _ = signalingClient.sendTunnelClose(connectionId: connectionId, reason: "lan_probe_done")
                continuation.resume(returning: config)
            }

            signalingClient.setTunnelHandler(connectionId: connectionId) { [weak self] event in
                guard let self else { return }
                switch event.type {
                case "tunnel_open_ack":
                    _ = self.signalingClient.sendTunnelFrame(
                        connectionId: connectionId,
                        seq: 1,
                        frame: #"{"type":"lan_request"}"#
                    )
                case "tunnel_frame":
                    guard let config = self.lanConfig(
                        from: event.frame,
                        connection: connection,
                        connectionId: connectionId,
                        toDeviceId: toDeviceId,
                        session: session
                    ), config.isPrivateLANConfig else { return }
                    finish(config)
                case "tunnel_close", "tunnel_error":
                    finish(nil)
                default:
                    break
                }
            }

            guard signalingClient.openTunnel(connectionId: connectionId, toDeviceId: toDeviceId) else {
                finish(nil)
                return
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                finish(nil)
            }
        }
    }

    private func lanConfig(
        from frame: String?,
        connection: RemoteConnectionAttempt,
        connectionId: Int,
        toDeviceId: Int,
        session: RemoteAuthSession
    ) -> RemoteChatConfig? {
        guard let frame,
              let data = frame.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["type"] as? String) == "lan_offer",
              let ip = (object["ip"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let port = object["port"] as? Int,
              let token = (object["token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !ip.isEmpty,
              (1...65535).contains(port),
              !token.isEmpty else {
            return nil
        }
        return RemoteChatConfig(
            macHost: ip,
            port: port,
            token: token,
            connectionId: connectionId,
            targetDeviceId: toDeviceId,
            transport: "lan",
            reason: connection.reason,
            remoteAccessToken: session.accessToken,
            remoteAPIBaseURL: RemoteAPIConfig.baseURL
        )
    }

    private func directChatConfig(
        from device: RemoteDevice?,
        transportLabel: String
    ) -> RemoteChatConfig? {
        guard let endpoint = device?.lanEndpoint,
              let token = device?.transientToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }
        return RemoteChatConfig(
            macHost: endpoint.ip,
            port: endpoint.port,
            token: token,
            connectionId: nil,
            targetDeviceId: nil,
            transport: transportLabel,
            reason: nil,
            remoteAccessToken: nil,
            remoteAPIBaseURL: RemoteAPIConfig.baseURL
        )
    }

    private func directChatConfig(
        from connection: RemoteConnectionAttempt,
        connectionId: Int,
        toDeviceId: Int,
        session: RemoteAuthSession,
        transportLabel: String
    ) -> RemoteChatConfig? {
        guard let endpoint = connection.endpoint,
              let token = connection.transientToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }
        return RemoteChatConfig(
            macHost: endpoint.ip,
            port: endpoint.port,
            token: token,
            connectionId: connectionId,
            targetDeviceId: toDeviceId,
            transport: transportLabel,
            reason: connection.reason,
            remoteAccessToken: session.accessToken,
            remoteAPIBaseURL: RemoteAPIConfig.baseURL
        )
    }

    private func publicDirectFallbackConfig(
        deviceId: Int,
        device: RemoteDevice?,
        session: RemoteAuthSession,
        connectionId: Int,
        toDeviceId: Int,
        connection: RemoteConnectionAttempt
    ) async throws -> RemoteChatConfig? {
        if let connectionConfig = directChatConfig(
            from: connection,
            connectionId: connectionId,
            toDeviceId: toDeviceId,
            session: session,
            transportLabel: "public"
        ), connectionConfig.isPublicDirectConfig {
            return connectionConfig
        }

        let resolvedDevice = device ?? (try? await client.device(deviceId: deviceId, accessToken: session.accessToken))
        guard let endpoint = resolvedDevice?.lanEndpoint,
              let token = resolvedDevice?.transientToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }
        if let currentEndpoint = connection.endpoint,
           let currentToken = connection.transientToken,
           currentEndpoint.ip == endpoint.ip,
           currentEndpoint.port == endpoint.port,
           currentToken == token {
            return nil
        }
        let config = RemoteChatConfig(
            macHost: endpoint.ip,
            port: endpoint.port,
            token: token,
            connectionId: connectionId,
            targetDeviceId: toDeviceId,
            transport: "public",
            reason: connection.reason,
            remoteAccessToken: session.accessToken,
            remoteAPIBaseURL: RemoteAPIConfig.baseURL
        )
        return config.isPublicDirectConfig ? config : nil
    }

    private func establishDirectTransport(_ config: RemoteChatConfig) async throws -> RemoteChatConfig {
        var directConfig = config
        directConfig.connectionId = nil
        directConfig.transport = "lan"

        if let wifiSubnet = LanNetworkSelector.wifiSubnetPrefix() {
            let offeredSubnet = directConfig.macHost.split(separator: ".").prefix(3).joined(separator: ".")
            if directConfig.isPrivateLANConfig, offeredSubnet != wifiSubnet,
               let discovered = await LanSubnetProbe.discoverHealthHost(
                port: directConfig.port,
                preferredHost: LanNetworkSelector.localWifiIPv4()
               ) {
                directConfig.macHost = discovered
            }
        }

        let http = RemoteHTTPClient(config: directConfig)
        do {
            _ = try await http.fetchHealth()
        } catch {
            if directConfig.isPrivateLANConfig,
               let discovered = await LanSubnetProbe.discoverHealthHost(
                port: directConfig.port,
                preferredHost: directConfig.macHost
               ) {
                directConfig.macHost = discovered
                _ = try await RemoteHTTPClient(config: directConfig).fetchHealth()
            } else {
                throw error
            }
        }

        let transport = RemoteWebSocketClient(config: directConfig)
        try transport.connect()
        try await waitForTransportReady(transport)

        var readyConfig = directConfig
        readyConfig.remoteTransport = transport
        readyConfig.remoteRelayReady = true
        latestTransport = "lan"
        return readyConfig
    }

    private func lanFallbackNote(lanFailure: Error?) -> String? {
        guard let lanFailure else { return nil }
        let detail = lanFailure.localizedDescription
        if LanNetworkSelector.isOnWifi() {
            return L10n.string("已改用跨网通道（局域网不可用：\(detail)）。若在同一 Wi‑Fi 仍失败，请检查路由器是否开启「AP 隔离」。")
        }
        return L10n.string("已改用跨网通道（当前未连 Wi‑Fi，无法局域网直连：\(detail)）。")
    }

    private func establishP2PTransport(
        connectionId: Int,
        toDeviceId: Int,
        session: RemoteAuthSession,
        connection: RemoteConnectionAttempt
    ) async throws -> RemoteChatConfig {
        try await signalingClient.waitUntilConnected(timeout: 8)
        let ice = try await client.iceServers(connectionId: connectionId, accessToken: session.accessToken)
        let icePolicy = RemoteICEPolicy.summary(from: ice.iceServers)
        let iceServers = RemoteICEPolicy.relayCapableServers(from: ice.iceServers)
#if DEBUG
        print("[CodevokeConnect] p2p ice \(icePolicy.logDescription) connectionId=\(connectionId)")
#endif
        let transport = RemoteWebRTCTransport(
            connectionId: connectionId,
            targetDeviceId: toDeviceId,
            role: .offerer,
            signalingClient: signalingClient,
            iceServers: iceServers
        )
        signalingClient.setRelayHandler(connectionId: connectionId) { [weak transport] event in
            guard let payload = event.payload else { return }
            transport?.receiveRelayPayload(payload)
        }
        let signalingGeneration = signalingClient.connectionGeneration
        try transport.connect()
        try await waitForTransportReady(transport, signalingGeneration: signalingGeneration)

        latestTransport = "p2p"
        return RemoteChatConfig(
            macHost: "",
            port: 0,
            token: session.accessToken,
            connectionId: connectionId,
            targetDeviceId: toDeviceId,
            transport: "p2p",
            reason: connection.reason,
            remoteAccessToken: session.accessToken,
            remoteAPIBaseURL: RemoteAPIConfig.baseURL,
            remoteTransport: transport,
            remoteRelayReady: true
        )
    }

    private func waitForDecision(connectionId: Int, accessToken: String) async throws -> RemoteConnectionAttempt {
        if let buffered = bufferedDecisions.removeValue(forKey: connectionId) {
            pendingConnectionId = nil
            return buffered
        }

        return try await withThrowingTaskGroup(of: RemoteConnectionAttempt.self) { group in
            group.addTask { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.awaitPushDecision(connectionId: connectionId)
            }
            group.addTask { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.pollConnectionUntilResolved(connectionId: connectionId, accessToken: accessToken)
            }
            group.addTask { [pendingApprovalTimeout] in
                try await Task.sleep(nanoseconds: UInt64(pendingApprovalTimeout * 1_000_000_000))
                throw PendingApprovalTimeoutError()
            }

            guard let result = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            pendingConnectionId = nil
            return result
        }
    }

    private func awaitPushDecision(connectionId: Int) async throws -> RemoteConnectionAttempt {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let buffered = bufferedDecisions.removeValue(forKey: connectionId) {
                    pendingConnectionId = nil
                    continuation.resume(returning: buffered)
                    return
                }
                pendingConnectionId = connectionId
                decisionContinuations[connectionId] = continuation
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.resumeDecisionContinuation(connectionId: connectionId, throwing: CancellationError())
            }
        }
    }

    private func pollConnectionUntilResolved(connectionId: Int, accessToken: String) async throws -> RemoteConnectionAttempt {
        for delay in connectionPollDelays {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            try Task.checkCancellation()
            do {
                let connection = try await client.connection(connectionId: connectionId, accessToken: accessToken)
                updateLatestConnection(connection)
                if connection.status != "pending" {
                    return connection
                }
            } catch {
                continue
            }
        }
        throw PendingApprovalTimeoutError()
    }

    private func waitForTransportReady(_ transport: RemoteTransport, signalingGeneration: UInt64? = nil) async throws {
        if transport is RemoteWebRTCTransport, transport.canSendFrames { return }
        if transport.isConnected { return }

        let deadline = Date().addingTimeInterval(remoteTransportReadyTimeout)
        while true {
            try Task.checkCancellation()
            if let failure = (transport as? RemoteWebRTCTransport)?.failureError {
                throw failure
            }
            if transport is RemoteWebRTCTransport, transport.canSendFrames { return }
            if transport.isConnected { return }
            if let signalingGeneration {
                if !signalingClient.isConnected {
                    throw SignalingDisconnectedDuringTransportError()
                }
                if signalingClient.connectionGeneration != signalingGeneration {
                    throw SignalingDisconnectedDuringTransportError()
                }
            }
            if Date() >= deadline {
                throw RemoteTransportReadyTimeoutError()
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func shouldBlockAcceptedConnection(_ reason: String) -> Bool {
        switch normalizedTransport(reason) {
        case "", "remote_transport_required", "lan_unavailable":
            return false
        default:
            return userFacingReasonMessage(reason) != nil
        }
    }

    private func normalizedTransport(_ transport: String?) -> String {
        transport?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private func handleDecision(_ connection: RemoteConnectionAttempt) {
        let connectionId = connection.connectionId ?? connection.id
        if let continuation = decisionContinuations.removeValue(forKey: connectionId) {
            pendingConnectionId = nil
            continuation.resume(returning: connection)
            return
        }
        bufferedDecisions[connectionId] = connection
        if bufferedDecisions.count > 20 {
            bufferedDecisions.removeAll(keepingCapacity: true)
            bufferedDecisions[connectionId] = connection
        }
    }

    private func updateLatestConnection(_ connection: RemoteConnectionAttempt) {
        latestConnectionId = connection.connectionId ?? connection.id
        latestTransport = connection.transport
        latestReason = connection.reason
    }

    private func message(for connection: RemoteConnectionAttempt) -> String {
        if let reason = connection.reason, let mappedMessage = userFacingReasonMessage(reason) {
            return mappedMessage
        }
        return RemoteUserFacingText.status(connection.status)
    }

    private func userFacingReasonMessage(_ reason: String) -> String? {
        RemoteUserFacingText.reason(reason)
    }

    private func clearPendingWait(throwing error: Error) {
        pendingConnectionId = nil
        decisionContinuations.values.forEach { $0.resume(throwing: error) }
        decisionContinuations.removeAll()
    }

    private func resumeDecisionContinuation(connectionId: Int, throwing error: Error) {
        guard let continuation = decisionContinuations.removeValue(forKey: connectionId) else { return }
        if pendingConnectionId == connectionId {
            pendingConnectionId = nil
        }
        continuation.resume(throwing: error)
    }

    private func authErrorMessage(_ error: Error, fallback: String) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return L10n.string(fallback) }
        return RemoteUserFacingText.apiError(message, fallback: fallback)
    }
}

private extension RemoteChatConfig {
    var isPrivateLANConfig: Bool {
        supportsDirectHTTP && isPrivateIPv4Host(macHost)
    }

    var isPublicDirectConfig: Bool {
        supportsDirectHTTP && !isPrivateLANConfig
    }
}

private func isPrivateIPv4Host(_ host: String) -> Bool {
    let octets = host
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: ".")
        .compactMap { Int($0) }
    guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
    switch (octets[0], octets[1]) {
    case (10, _):
        return true
    case (172, let second) where (16...31).contains(second):
        return true
    case (192, 168):
        return true
    default:
        return false
    }
}

private struct PendingApprovalTimeoutError: Error {}
private struct RemoteTransportReadyTimeoutError: Error {}
private struct SignalingDisconnectedDuringTransportError: Error {}
