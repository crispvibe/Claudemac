import Foundation
import ChatCore

@MainActor
final class RemoteTunnelTransport: RemoteTransport {
    private let connectionId: Int
    private let targetDeviceId: Int
    private let signalingClient: SignalingClient
    private let codec: RemoteTransportFrameCodec
    private var openTimeoutTask: Task<Void, Never>?
    private var intentionallyClosed = false
    private var nextSeq: UInt64 = 1

    private(set) var isConnected = false
    private(set) var failureError: Error?

    var canSendFrames: Bool { isConnected }

    var onConnect: (() -> Void)?
    var onEnvelope: ((PanelStateEnvelope) -> Void)?
    var onAck: ((CommandAck) -> Void)?
    var onRecoveryResponse: ((RemoteRecoveryResponse) -> Void)?
    var onDecodeFailure: ((String) -> Void)?
    var onDisconnect: ((Error?) -> Void)?

    init(connectionId: Int, targetDeviceId: Int, signalingClient: SignalingClient, codec: RemoteTransportFrameCodec = RemoteTransportFrameCodec()) {
        self.connectionId = connectionId
        self.targetDeviceId = targetDeviceId
        self.signalingClient = signalingClient
        self.codec = codec
    }

    func connect() throws {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                try? self?.connect()
            }
            return
        }
        guard !isConnected else { return }
        guard signalingClient.isConnected else { throw RemoteChatError.signalingUnavailable }
        intentionallyClosed = false
        failureError = nil
        signalingClient.setTunnelHandler(connectionId: connectionId) { [weak self] event in
            self?.receiveTunnelEvent(event)
        }
        scheduleOpenTimeout()
        guard signalingClient.openTunnel(connectionId: connectionId, toDeviceId: targetDeviceId) else {
            fail(RemoteChatError.signalingUnavailable)
            throw RemoteChatError.signalingUnavailable
        }
    }

    func disconnect() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.disconnect()
            }
            return
        }
        intentionallyClosed = true
        openTimeoutTask?.cancel()
        openTimeoutTask = nil
        if isConnected {
            _ = signalingClient.sendTunnelClose(connectionId: connectionId, reason: "client_disconnect")
        }
        signalingClient.removeTunnelHandler(connectionId: connectionId)
        isConnected = false
    }

    func sendResume(sessionId: UUID?, lastRevision: Int?) async throws {
        try await sendText(codec.encodeResume(sessionId: sessionId, lastRevision: lastRevision))
    }

    func sendCommand(_ command: Command) async throws {
        try await sendText(codec.encodeCommand(command))
    }

    func sendRecoveryRequest(_ request: RemoteRecoveryRequest) async throws {
        try await sendText(codec.encodeRecoveryRequest(request))
    }

    private func receiveTunnelEvent(_ event: SignalingClient.Event) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.receiveTunnelEvent(event)
            }
            return
        }
        guard !intentionallyClosed else { return }
        switch event.type {
        case "tunnel_open_ack":
            openTimeoutTask?.cancel()
            openTimeoutTask = nil
            if !isConnected {
                isConnected = true
                onConnect?()
            }
        case "tunnel_frame":
            guard let frame = event.frame else { return }
            handleFrame(frame)
        case "tunnel_close":
            fail(RemoteChatError.remoteConnectionFailed)
        case "tunnel_error":
            fail(RemoteChatError.serverMessage(event.message ?? "远程通道连接失败。", statusCode: 502))
        default:
            break
        }
    }

    private func handleFrame(_ text: String) {
        do {
            switch try codec.decode(text: text) {
            case .panelState(let envelope):
                onEnvelope?(envelope)
            case .commandAck(let ack):
                onAck?(ack)
            case .recoveryResponse(let response):
                onRecoveryResponse?(response)
            case .hello:
                if !isConnected {
                    isConnected = true
                    onConnect?()
                }
            case .ignored:
                break
            }
        } catch {
            onDecodeFailure?(String(text.prefix(200)))
        }
    }

    private func sendText(_ text: String) async throws {
        try sendTextOnCurrentThread(text)
    }

    private func sendTextOnCurrentThread(_ text: String) throws {
        guard !intentionallyClosed, isConnected else { throw RemoteChatError.missingConfiguration }
        let data = Data(text.utf8)
        guard data.count <= RemoteRecoveryLimits.maximumTextFrameUTF8Bytes else {
            throw RemoteChatError.serverMessage(L10n.string("附件不能超过 10MB。"), statusCode: 413)
        }
        let seq = nextSeq
        nextSeq &+= 1
        guard signalingClient.sendTunnelFrame(connectionId: connectionId, seq: seq, frame: text) else {
            fail(RemoteChatError.signalingUnavailable)
            throw RemoteChatError.signalingUnavailable
        }
    }

    private func scheduleOpenTimeout() {
        openTimeoutTask?.cancel()
        openTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled, !self.intentionallyClosed, !self.isConnected else { return }
                self.fail(RemoteChatError.remoteConnectionFailed)
            }
        }
    }

    private func fail(_ error: Error) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.fail(error)
            }
            return
        }
        guard !intentionallyClosed else { return }
        openTimeoutTask?.cancel()
        openTimeoutTask = nil
        signalingClient.removeTunnelHandler(connectionId: connectionId)
        failureError = error
        isConnected = false
        onDisconnect?(error)
    }
}
