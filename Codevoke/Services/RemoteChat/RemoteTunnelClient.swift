import Foundation

@MainActor
final class RemoteTunnelClient {
    private let signalingClient: SignalingClient
    private var activeConnectionIds: Set<Int> = []
    private var nextSeq: UInt64 = 1

    init(signalingClient: SignalingClient) {
        self.signalingClient = signalingClient
    }

    func handle(_ event: SignalingClient.Event) {
        switch event.type {
        case "tunnel_open":
            guard let connectionId = event.connectionId else { return }
            open(connectionId: connectionId)
        case "tunnel_frame":
            guard let connectionId = event.connectionId, let frame = event.frame else { return }
            receive(frame: frame, connectionId: connectionId)
        case "tunnel_close", "tunnel_error":
            guard let connectionId = event.connectionId else { return }
            close(connectionId: connectionId, notifyRemote: false, reason: event.reason ?? event.code ?? "remote_closed")
        default:
            break
        }
    }

    func closeAll(reason: String = "client_shutdown") {
        for connectionId in Array(activeConnectionIds) {
            close(connectionId: connectionId, notifyRemote: true, reason: reason)
        }
    }

    private func open(connectionId: Int) {
        guard !activeConnectionIds.contains(connectionId) else { return }
        activeConnectionIds.insert(connectionId)
        sendLanOfferIfAvailable(connectionId: connectionId)
        RemoteChatServerController.shared.registerWebRTCSender(connectionId: connectionId) { [weak self] text in
            Task { @MainActor [weak self] in
                self?.send(frame: text, connectionId: connectionId)
            }
        }
        RemoteChatServerController.shared.pushWebRTCBootstrapSnapshot(connectionId: connectionId)
        print("[RemoteTunnelMac] opened connectionId=\(connectionId)")
    }

    private func receive(frame: String, connectionId: Int) {
        guard activeConnectionIds.contains(connectionId) else {
            open(connectionId: connectionId)
            return receive(frame: frame, connectionId: connectionId)
        }
        if handleLanProbe(frame: frame, connectionId: connectionId) { return }
        RemoteChatServerController.shared.handleWebRTCTextFrame(frame, connectionId: connectionId) { [weak self] response in
            Task { @MainActor [weak self] in
                self?.send(frame: response, connectionId: connectionId)
            }
        }
    }

    private func send(frame: String, connectionId: Int) {
        guard activeConnectionIds.contains(connectionId) else { return }
        let seq = nextSeq
        nextSeq &+= 1
        if !signalingClient.sendTunnelFrame(connectionId: connectionId, seq: seq, frame: frame) {
            close(connectionId: connectionId, notifyRemote: false, reason: "send_failed")
        }
    }

    private func close(connectionId: Int, notifyRemote: Bool, reason: String) {
        guard activeConnectionIds.remove(connectionId) != nil else { return }
        RemoteChatServerController.shared.unregisterWebRTCConnection(connectionId: connectionId)
        if notifyRemote {
            _ = signalingClient.sendTunnelClose(connectionId: connectionId, reason: reason)
        }
        print("[RemoteTunnelMac] closed connectionId=\(connectionId) reason=\(reason)")
    }

    private func handleLanProbe(frame: String, connectionId: Int) -> Bool {
        guard let data = frame.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String,
              type == "lan_request" else { return false }
        sendLanOfferIfAvailable(connectionId: connectionId)
        return true
    }

    private func sendLanOfferIfAvailable(connectionId: Int) {
        let settings = ProjectStore.loadSettings()
        guard settings.remoteChatServerEnabled else { return }
        guard RemoteChatServerController.shared.isRunning else { return }

        let configuredPort = settings.remoteChatServerPort
        let port = configuredPort > 0 ? configuredPort : Int(RemoteChatServerController.defaultPort)
        guard (1...65535).contains(port) else { return }

        let publicHost = settings.remoteChatPublicHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep in sync with RemoteChatServerController.startIfNeeded(): the local server may
        // accept LAN connections even when only a public host is configured.
        let acceptsLanConnections = settings.remoteChatServerBindLAN || !publicHost.isEmpty
        guard acceptsLanConnections,
              let publishHost = LanNetworkAddress.primaryIPv4(),
              !publishHost.isEmpty else { return }

        let publishPort = port
        let token = RemoteChatServerController.generateTransientToken()
        let expiresAt = Date().addingTimeInterval(120)
        RemoteChatServerController.shared.setTransientToken(token, expiresAt: expiresAt)

        let frame: [String: Any] = [
            "type": "lan_offer",
            "ip": publishHost,
            "port": publishPort,
            "token": token,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: frame),
              let text = String(data: data, encoding: .utf8) else { return }
        send(frame: text, connectionId: connectionId)
        print("[RemoteTunnelMac] sent lan_offer endpoint=\(publishHost):\(publishPort) connectionId=\(connectionId)")
        Task { @MainActor [weak self] in
            for delayMs in [400, 900] {
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                guard let self, self.activeConnectionIds.contains(connectionId) else { return }
                self.send(frame: text, connectionId: connectionId)
            }
        }
    }
}
