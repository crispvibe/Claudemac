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
}
