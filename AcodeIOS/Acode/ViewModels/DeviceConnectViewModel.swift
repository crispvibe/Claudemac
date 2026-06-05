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
    private var pendingTunnelTransport: RemoteTunnelTransport?
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

    func connect(deviceId: Int, session: RemoteAuthSession?) async -> RemoteChatConfig? {
        guard let session, !isConnecting else {
#if DEBUG
            print("[AnnaCodeConnect] connect skipped deviceId=\(deviceId) hasSession=\(session != nil) isConnecting=\(isConnecting)")
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
            print("[AnnaCodeConnect] connect start deviceId=\(deviceId)")
#endif
            var connection = try await client.connect(deviceId: deviceId, accessToken: session.accessToken)
            updateLatestConnection(connection)
#if DEBUG
            print("[AnnaCodeConnect] initial status=\(connection.status) connectionId=\(connection.connectionId ?? connection.id) transport=\(connection.transport ?? "nil") reason=\(connection.reason ?? "nil") endpoint=\(connection.endpoint?.ip ?? "nil"):\(connection.endpoint?.port ?? -1)")
#endif
            if connection.status == "pending" {
                let connectionId = connection.connectionId ?? connection.id
                pendingConnectionId = connectionId
                message = L10n.string("连接请求已发送，请在电脑端允许。")
                connection = try await waitForDecision(connectionId: connectionId, accessToken: session.accessToken)
                updateLatestConnection(connection)
#if DEBUG
                print("[AnnaCodeConnect] resolved status=\(connection.status) connectionId=\(connection.connectionId ?? connection.id) transport=\(connection.transport ?? "nil") reason=\(connection.reason ?? "nil") endpoint=\(connection.endpoint?.ip ?? "nil"):\(connection.endpoint?.port ?? -1)")
#endif
            }
            guard connection.status == "accepted" else {
                message = message(for: connection)
#if DEBUG
                print("[AnnaCodeConnect] rejected status=\(connection.status) message=\(message ?? "nil")")
#endif
                return nil
            }
            if let reason = connection.reason, let mappedMessage = userFacingReasonMessage(reason) {
                if reason != "remote_transport_required" {
                    message = mappedMessage
#if DEBUG
                    print("[AnnaCodeConnect] blocked reason=\(reason) message=\(mappedMessage)")
#endif
                    return nil
                }
            }
            let transportName = normalizedTransport(connection.transport)
            guard transportName == "tunnel" else {
                message = L10n.format("当前连接方式暂不可用：%@。", RemoteUserFacingText.transport(connection.transport))
#if DEBUG
                print("[AnnaCodeConnect] unsupported transport=\(connection.transport ?? "nil")")
#endif
                return nil
            }
            let connectionId = connection.connectionId ?? connection.id
            guard let toDeviceId = connection.toDeviceId else {
                message = L10n.string("连接信息不完整，请重新发起连接。")
                return nil
            }
            do {
                try await signalingClient.waitUntilConnected(timeout: 8)
            } catch {
                message = error.localizedDescription
#if DEBUG
                print("[AnnaCodeConnect] signaling not ready connectionId=\(connectionId): \(error.localizedDescription)")
#endif
                return nil
            }
            let transport = RemoteTunnelTransport(
                connectionId: connectionId,
                targetDeviceId: toDeviceId,
                signalingClient: signalingClient
            )
            pendingTunnelTransport = transport
            let signalingGeneration = signalingClient.connectionGeneration
            message = L10n.string("正在建立远程通道。")
            do {
                try transport.connect()
                try await waitForRemoteTransportReady(transport, signalingGeneration: signalingGeneration)
            } catch is RemoteTransportReadyTimeoutError {
                pendingTunnelTransport = nil
                transport.disconnect()
                message = L10n.string("远程通道建立超时，请确认电脑端在线后重试。")
#if DEBUG
                print("[AnnaCodeConnect] tunnel ready timeout connectionId=\(connectionId)")
#endif
                return nil
            } catch is SignalingDisconnectedDuringTransportError {
                pendingTunnelTransport = nil
                transport.disconnect()
                message = L10n.string("信令通道已断开，请确认网络后重试。")
#if DEBUG
                print("[AnnaCodeConnect] signaling disconnected while waiting for remote transport connectionId=\(connectionId)")
#endif
                return nil
            } catch {
                pendingTunnelTransport = nil
                transport.disconnect()
                message = authErrorMessage(error, fallback: "远程通道建立失败，请确认电脑端在线后重试。")
#if DEBUG
                print("[AnnaCodeConnect] tunnel connect failed connectionId=\(connectionId): \(error.localizedDescription)")
#endif
                return nil
            }
            return RemoteChatConfig(
                macHost: "tunnel",
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
        } catch is PendingApprovalTimeoutError {
            message = L10n.string("等待电脑端确认超时，请确认设备在线后重试。")
#if DEBUG
            print("[AnnaCodeConnect] pending approval timeout")
#endif
            return nil
        } catch is CancellationError {
            message = L10n.string("连接请求已取消。")
#if DEBUG
            print("[AnnaCodeConnect] cancelled")
#endif
            return nil
        } catch {
            message = authErrorMessage(error, fallback: "连接请求失败。")
#if DEBUG
            print("[AnnaCodeConnect] failed: \(error.localizedDescription)")
#endif
            return nil
        }
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

    private func waitForRemoteTransportReady(_ transport: RemoteTunnelTransport, signalingGeneration: UInt64) async throws {
        if transport.canSendFrames { return }
        let deadline = Date().addingTimeInterval(remoteTransportReadyTimeout)
        while !transport.canSendFrames {
            try Task.checkCancellation()
            if let failure = transport.failureError {
                throw failure
            }
            if !signalingClient.isConnected {
                throw SignalingDisconnectedDuringTransportError()
            }
            if signalingClient.connectionGeneration != signalingGeneration {
                throw SignalingDisconnectedDuringTransportError()
            }
            if Date() >= deadline {
                throw RemoteTransportReadyTimeoutError()
            }
            try await Task.sleep(nanoseconds: 100_000_000)
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

private struct PendingApprovalTimeoutError: Error {}
private struct RemoteTransportReadyTimeoutError: Error {}
private struct SignalingDisconnectedDuringTransportError: Error {}
