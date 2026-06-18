import Foundation

@MainActor
final class SignalingClient: ObservableObject {
    static let shared = SignalingClient()

    struct Event: Decodable {
        let type: String
        let deviceId: Int?
        let fromDeviceId: Int?
        let toDeviceId: Int?
        let connectionId: Int?
        let status: String?
        let reason: String?
        let payload: RemoteSignalingPayload?
        let frame: String?
        let seq: UInt64?
        let code: String?
        let connection: RemoteConnectionAttempt?
        let online: Bool?
        let message: String?
    }

    var onPresenceUpdate: ((Int, Bool) -> Void)?
    var onConnectDecision: ((RemoteConnectionAttempt) -> Void)?
    var onRelay: ((Event) -> Void)?
    @Published private(set) var isConnected = false
    var connectionGeneration: UInt64 { connectEpoch }

    private let baseURL: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var accessToken = ""
    private var deviceId: Int?
    private var reconnectDelay: UInt64 = 1
    private var shouldReconnect = false
    private var connectionFailure: Error?
    private var relayHandlers: [Int: (Event) -> Void] = [:]
    private var tunnelHandlers: [Int: (Event) -> Void] = [:]
    /// 每次 `connect()` 自增。`receiveLoop` 捕获自己注册时的 epoch，
    /// 老 loop 被 cancel 落到 catch 时若 epoch 已变就直接退出，
    /// 不再 `scheduleReconnect()` 把新连接拆掉。
    private var connectEpoch: UInt64 = 0
    private static let pingIntervalNanoseconds: UInt64 = 20_000_000_000

    init(baseURL: URL = RemoteAPIConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func start(accessToken: String, deviceId: Int) {
        stop()
        self.accessToken = accessToken
        self.deviceId = deviceId
        shouldReconnect = true
        reconnectDelay = 1
        connectionFailure = nil
        connect()
    }

    func stop() {
        shouldReconnect = false
        isConnected = false
        connectionFailure = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        stopPingLoop()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        relayHandlers.removeAll()
        tunnelHandlers.removeAll()
        connectEpoch &+= 1
    }

    private func connect() {
        guard shouldReconnect, let deviceId, let url = signalingURL(token: accessToken) else { return }
        isConnected = false
        connectEpoch &+= 1
        let epoch = connectEpoch
#if DEBUG
        print("[CodevokeSignaling] connect epoch=\(epoch) host=\(url.host ?? "nil")")
#endif
        let wsTask = session.webSocketTask(with: url)
        task = wsTask
        wsTask.resume()
        send(["type": "hello", "deviceId": deviceId])
        startPingLoop(epoch: epoch)
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(epoch: epoch, task: wsTask)
        }
    }

    private func receiveLoop(epoch: UInt64, task: URLSessionWebSocketTask) async {
        while shouldReconnect, connectEpoch == epoch {
            do {
                let message = try await task.receive()
                guard let data = data(from: message) else { continue }
                let event = try JSONDecoder().decode(Event.self, from: data)
                handle(event)
            } catch {
                if connectEpoch == epoch {
#if DEBUG
                    print("[CodevokeSignaling] receive failed epoch=\(epoch): \(error.localizedDescription)")
#endif
                    if Self.isAuthError(error) {
                        failAuthentication(message: nil)
                    } else {
                        markDisconnected()
                        scheduleReconnect()
                    }
                }
                return
            }
        }
    }

    private func handle(_ event: Event) {
        switch event.type {
        case "hello_ack":
            isConnected = true
            reconnectDelay = 1
        case "ping":
            send(["type": "pong"])
        case "pong":
            break
        case "presence_update":
            if let deviceId = event.deviceId, let online = event.online {
                onPresenceUpdate?(deviceId, online)
            }
        case "connect_decision":
            if let connection = event.connection {
                onConnectDecision?(connection)
            }
        case "relay":
            if let connectionId = event.connectionId, let handler = relayHandlers[connectionId] {
                handler(event)
            } else {
                onRelay?(event)
            }
        case "tunnel_open_ack", "tunnel_frame", "tunnel_close", "tunnel_error":
            if let connectionId = event.connectionId, let handler = tunnelHandlers[connectionId] {
                handler(event)
            }
        case "error":
            if Self.isAuthMessage(event.message) {
                failAuthentication(message: event.message)
            }
        default:
            break
        }
    }

    func waitUntilConnected(timeout: TimeInterval = 8) async throws {
        if isConnected { return }
        if let connectionFailure { throw connectionFailure }
        let deadline = Date().addingTimeInterval(timeout)
        while !isConnected {
            try Task.checkCancellation()
            if let connectionFailure { throw connectionFailure }
            if Date() >= deadline {
                throw SignalingConnectionTimeoutError()
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func setRelayHandler(connectionId: Int, handler: @escaping (Event) -> Void) {
        relayHandlers[connectionId] = handler
    }

    func removeRelayHandler(connectionId: Int) {
        relayHandlers.removeValue(forKey: connectionId)
    }

    func setTunnelHandler(connectionId: Int, handler: @escaping (Event) -> Void) {
        tunnelHandlers[connectionId] = handler
    }

    func removeTunnelHandler(connectionId: Int) {
        tunnelHandlers.removeValue(forKey: connectionId)
    }

    @discardableResult
    func relay(connectionId: Int, toDeviceId: Int, payload: RemoteSignalingPayload) -> Bool {
        guard let data = try? JSONEncoder().encode(payload),
              let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        return send([
            "type": "relay",
            "connectionId": connectionId,
            "toDeviceId": toDeviceId,
            "payload": object
        ])
    }

    @discardableResult
    func openTunnel(connectionId: Int, toDeviceId: Int) -> Bool {
        send([
            "type": "tunnel_open",
            "connectionId": connectionId,
            "toDeviceId": toDeviceId
        ])
    }

    @discardableResult
    func sendTunnelFrame(connectionId: Int, seq: UInt64, frame: String) -> Bool {
        send([
            "type": "tunnel_frame",
            "connectionId": connectionId,
            "seq": seq,
            "frame": frame
        ])
    }

    @discardableResult
    func sendTunnelClose(connectionId: Int, reason: String) -> Bool {
        send([
            "type": "tunnel_close",
            "connectionId": connectionId,
            "reason": reason
        ])
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        isConnected = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        receiveTask?.cancel()
        stopPingLoop()
        reconnectTask?.cancel()
        connectEpoch &+= 1
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)
#if DEBUG
        print("[CodevokeSignaling] reconnect scheduled delay=\(delay)s nextEpoch=\(connectEpoch + 1)")
#endif
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            await MainActor.run { self?.connect() }
        }
    }

    private func markDisconnected() {
        isConnected = false
    }

    private func failAuthentication(message: String?) {
        shouldReconnect = false
        isConnected = false
        connectionFailure = SignalingAuthenticationError(message: message)
        reconnectTask?.cancel()
        reconnectTask = nil
        stopPingLoop()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connectEpoch &+= 1
    }

    private func startPingLoop(epoch: UInt64) {
        stopPingLoop()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pingIntervalNanoseconds)
                await MainActor.run { self?.sendPing(epoch: epoch) }
            }
        }
    }

    private func stopPingLoop() {
        pingTask?.cancel()
        pingTask = nil
    }

    private func sendPing(epoch: UInt64) {
        guard shouldReconnect, connectEpoch == epoch, let task else { return }
        if isConnected {
            _ = send(["type": "ping"])
        }
        task.sendPing { [weak self, weak task] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                guard self?.task === task, self?.connectEpoch == epoch else { return }
#if DEBUG
                print("[CodevokeSignaling] ping failed epoch=\(epoch): \(error.localizedDescription)")
#endif
                self?.markDisconnected()
                self?.scheduleReconnect()
            }
        }
    }

    @discardableResult
    private func send(_ object: [String: Any]) -> Bool {
        let type = object["type"] as? String
        guard type == "hello" || isConnected else { return false }
        guard let task, let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return false }
        task.send(.string(text)) { [weak self, weak task] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                guard self?.task === task else { return }
#if DEBUG
                print("[CodevokeSignaling] send failed type=\(type ?? "nil"): \(error.localizedDescription)")
#endif
                if Self.isAuthError(error) {
                    self?.failAuthentication(message: nil)
                } else {
                    self?.markDisconnected()
                    self?.scheduleReconnect()
                }
            }
        }
        return true
    }

    private func data(from message: URLSessionWebSocketTask.Message) -> Data? {
        switch message {
        case .data(let data): data
        case .string(let string): string.data(using: .utf8)
        @unknown default: nil
        }
    }

    private func signalingURL(token: String) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "http" ? "ws" : "wss"
        if let host = UserDefaults.standard.string(forKey: "CodevokeRemoteSignalingHost")?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            components?.host = host
        }
        components?.path = "/remote/signaling/ws"
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url
    }

    private static func isAuthError(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
            return true
        }
        let nsError = error as NSError
        let description = nsError.localizedDescription.lowercased()
        if description.contains("401") || description.contains("unauthorized") {
            return true
        }
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorUserAuthenticationRequired
    }

    private static func isAuthMessage(_ message: String?) -> Bool {
        guard let message = message?.lowercased() else { return false }
        return message.contains("登录状态已失效") || message.contains("重新登录") || message.contains("unauthorized") || message.contains("401")
    }
}

private struct SignalingAuthenticationError: LocalizedError {
    let message: String?

    var errorDescription: String? {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.string("登录状态已失效，请重新登录。") : trimmed
    }
}

private struct SignalingConnectionTimeoutError: LocalizedError {
    var errorDescription: String? {
        L10n.string("信令通道连接超时，请确认网络或稍后重试。")
    }
}
