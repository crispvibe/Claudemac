import Foundation

@MainActor
final class SignalingClient {
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
        /// Error/control-frame text from signaling (for example `type=error`).
        /// Business chat data must flow only through WebRTC data channel frames.
        let message: String?
    }

    var onEvent: ((Event) -> Void)?
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
    private(set) var isConnected = false
    var connectionGeneration: UInt64 { connectEpoch }
    /// 每次 `connect()` 自增。`receiveLoop` 把自己注册时的 epoch 带到 catch 分支，
    /// 与当前 epoch 不一致直接退出 —— 避免老 receiveLoop 被 cancel 后落到 catch
    /// 又触发 `scheduleReconnect()`，把刚由新 `start()`/`connect()` 建好的连接拆掉。
    private var connectEpoch: UInt64 = 0
    private static let pingIntervalNanoseconds: UInt64 = 20_000_000_000

    init(baseURL: URL = AccountRemoteConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func start(accessToken: String, deviceId: Int) {
        stop()
        self.accessToken = accessToken
        self.deviceId = deviceId
        shouldReconnect = true
        reconnectDelay = 1
        connect()
    }

    func stop() {
        shouldReconnect = false
        isConnected = false
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        stopPingLoop()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connectEpoch &+= 1
    }

    func sendPong() {
        send(["type": "pong"])
    }

    @discardableResult
    func sendSignalingRelay(connectionId: Int, toDeviceId: Int, payload: RemoteSignalingPayload) -> Bool {
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

    private func connect() {
        guard shouldReconnect, let deviceId, let url = signalingURL(token: accessToken) else { return }
        isConnected = false
        connectEpoch &+= 1
        let epoch = connectEpoch
        print("[CodevokeSignalingMac] connect epoch=\(epoch) host=\(url.host ?? "nil")")
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
                if event.type == "ping" {
                    sendPong()
                } else if event.type == "pong" {
                    continue
                } else {
                    if event.type == "hello_ack" {
                        isConnected = true
                        reconnectDelay = 1
                    } else if event.type == "error" {
                        print("[CodevokeSignalingMac] error control frame message=\(event.message ?? "nil")")
                    }
                    onEvent?(event)
                }
            } catch {
                // 只有当前 epoch 的 receive 失败才安排重连；老 task 被新 connect()
                // 顶掉后落到这里的话，直接退出即可。
                if connectEpoch == epoch {
                    print("[CodevokeSignalingMac] receive failed epoch=\(epoch): \(error.localizedDescription)")
                    markDisconnected()
                    scheduleReconnect()
                }
                return
            }
        }
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
        print("[CodevokeSignalingMac] reconnect scheduled delay=\(delay)s nextEpoch=\(connectEpoch + 1)")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            await MainActor.run { self?.connect() }
        }
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
            guard error != nil else { return }
            Task { @MainActor [weak self] in
                guard self?.task === task, self?.connectEpoch == epoch else { return }
                print("[CodevokeSignalingMac] ping failed epoch=\(epoch)")
                self?.markDisconnected()
                self?.scheduleReconnect()
            }
        }
    }

    private func markDisconnected() {
        isConnected = false
    }

    @discardableResult
    private func send(_ object: [String: Any]) -> Bool {
        let type = object["type"] as? String
        guard type == "hello" || isConnected else { return false }
        guard let task, let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return false }
        task.send(.string(text)) { [weak self, weak task] error in
            guard error != nil else { return }
            Task { @MainActor [weak self] in
                guard self?.task === task else { return }
                let logType = type == "relay" ? "signaling relay" : (type ?? "nil")
                print("[CodevokeSignalingMac] send failed type=\(logType)")
                self?.markDisconnected()
                self?.scheduleReconnect()
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
}
