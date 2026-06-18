import Foundation
import ChatCore
import WebRTC

private final class RemoteWebRTCTransportDelegate: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate {
    weak var owner: RemoteWebRTCTransport?

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async { [weak owner] in
            owner?.handleICEConnectionState(newState)
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        DispatchQueue.main.async { [weak owner] in
            owner?.handleICEGatheringState(newState)
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        DispatchQueue.main.async { [weak owner, weak dataChannel] in
            owner?.adoptRemoteDataChannel(dataChannel)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        DispatchQueue.main.async { [weak owner] in
            owner?.handleGeneratedCandidate(candidate)
        }
    }

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        let state = dataChannel.readyState
        DispatchQueue.main.async { [weak owner] in
            owner?.handleDataChannelState(state)
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let copied = RTCDataBuffer(data: Data(buffer.data), isBinary: buffer.isBinary)
        DispatchQueue.main.async { [weak owner] in
            owner?.handleDataChannelBuffer(copied)
        }
    }
}

final class RemoteWebRTCTransport: RemoteTransport {
    enum Role {
        case offerer
        case answerer
    }

    private let connectionId: Int
    private let targetDeviceId: Int
    private let role: Role
    private let signalingClient: SignalingClient
    private let iceServers: [RemoteICEServer]
    private let icePolicySummary: RemoteICEPolicySummary
    private let codec: RemoteTransportFrameCodec
    private let factory: RTCPeerConnectionFactory
    private let delegate = RemoteWebRTCTransportDelegate()
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var pendingRemoteCandidates: [RTCIceCandidate] = []
    private var didSetRemoteDescription = false
    private var intentionallyClosed = false
    private var disconnectedFailTask: Task<Void, Never>?
    private var dataChannelOpenTask: Task<Void, Never>?
    private(set) var failureError: Error?

    private(set) var isConnected = false
    var canSendFrames: Bool {
        dataChannel?.readyState == .open
    }

    var onConnect: (() -> Void)?
    var onEnvelope: ((PanelStateEnvelope) -> Void)?
    var onAck: ((CommandAck) -> Void)?
    var onRecoveryResponse: ((RemoteRecoveryResponse) -> Void)?
    var onDecodeFailure: ((String) -> Void)?
    var onDisconnect: ((Error?) -> Void)?

    init(connectionId: Int, targetDeviceId: Int, role: Role, signalingClient: SignalingClient, iceServers: [RemoteICEServer], codec: RemoteTransportFrameCodec = RemoteTransportFrameCodec()) {
        self.connectionId = connectionId
        self.targetDeviceId = targetDeviceId
        self.role = role
        self.signalingClient = signalingClient
        self.iceServers = RemoteICEPolicy.relayCapableServers(from: iceServers)
        self.icePolicySummary = RemoteICEPolicy.summary(from: iceServers)
        self.codec = codec
        self.factory = RTCPeerConnectionFactory()
        self.delegate.owner = self
    }

    func connect() throws {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                try? self?.connect()
            }
            return
        }
        delegate.owner = self
        intentionallyClosed = false
        failureError = nil
        peerConnection = makePeerConnection()
        guard let peerConnection else { throw RemoteChatError.missingConfiguration }
        scheduleDataChannelOpenTimeout(reason: "connect")
        if role == .offerer {
            let config = RTCDataChannelConfiguration()
            config.isOrdered = true
            let channel = peerConnection.dataChannel(forLabel: "chat", configuration: config)
            adoptRemoteDataChannel(channel)
            offer()
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
        disconnectedFailTask?.cancel()
        disconnectedFailTask = nil
        dataChannelOpenTask?.cancel()
        dataChannelOpenTask = nil
        delegate.owner = nil
        dataChannel?.delegate = nil
        dataChannel?.close()
        peerConnection?.close()
        dataChannel = nil
        peerConnection = nil
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

    func receiveRelayPayload(_ payload: RemoteSignalingPayload) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.receiveRelayPayload(payload)
            }
            return
        }
        guard !intentionallyClosed else { return }
        switch payload.kind {
        case "offer":
            guard let sdp = payload.sdp else { return }
            setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp)) { [weak self] in
                self?.answer()
            }
        case "answer":
            guard let sdp = payload.sdp else { return }
#if DEBUG
            print("[RemoteWebRTC] received answer connectionId=\(connectionId) \(Self.sdpDebugDescription(sdp))")
#endif
            setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp))
        case "candidate":
            guard let candidate = payload.candidate else { return }
            if shouldIgnoreCandidate(candidate) {
#if DEBUG
                print("[RemoteWebRTC] remote candidate connectionId=\(connectionId) \(Self.candidateDebugDescription(candidate)) icePolicy=\(RemoteICEPolicy.relayCapableName) rejectedByPolicy=true")
#endif
                return
            }
            let rtcCandidate = RTCIceCandidate(
                sdp: candidate,
                sdpMLineIndex: payload.sdpMLineIndex ?? 0,
                sdpMid: payload.sdpMid
            )
            addRemoteCandidate(rtcCandidate)
        case "failed":
            onDisconnect?(RemoteChatError.remoteConnectionFailed)
        default:
            break
        }
    }

    fileprivate func adoptRemoteDataChannel(_ channel: RTCDataChannel?) {
        guard !intentionallyClosed else { return }
        guard let channel else { return }
        dataChannel = channel
        channel.delegate = delegate
        handleDataChannelState(channel.readyState)
    }

    fileprivate func handleGeneratedCandidate(_ candidate: RTCIceCandidate) {
        guard !intentionallyClosed else { return }
        let ignoredByPolicy = shouldIgnoreCandidate(candidate.sdp)
#if DEBUG
        print("[RemoteWebRTC] local candidate connectionId=\(connectionId) \(Self.candidateDebugDescription(candidate.sdp)) icePolicy=\(RemoteICEPolicy.relayCapableName) rejectedByPolicy=\(ignoredByPolicy)")
#endif
        guard !ignoredByPolicy else { return }
        sendCandidate(candidate)
    }

    private func sendCandidate(_ candidate: RTCIceCandidate) {
        relay(
            RemoteSignalingPayload(
                kind: "candidate",
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: candidate.sdpMLineIndex,
                candidate: candidate.sdp
            )
        )
    }

    fileprivate func handleICEGatheringState(_ state: RTCIceGatheringState) {
        guard !intentionallyClosed else { return }
#if DEBUG
        print("[RemoteWebRTC] ice gathering connectionId=\(connectionId) state=\(Self.iceGatheringStateDescription(state))")
#endif
    }

    fileprivate func handleDataChannelState(_ state: RTCDataChannelState) {
        guard !intentionallyClosed else { return }
#if DEBUG
        print("[RemoteWebRTC] data channel connectionId=\(connectionId) state=\(Self.dataChannelStateDescription(state))")
#endif
        switch state {
        case .open:
            dataChannelOpenTask?.cancel()
            dataChannelOpenTask = nil
            if !isConnected {
                isConnected = true
                onConnect?()
            }
        case .closed:
            isConnected = false
            if !intentionallyClosed {
                onDisconnect?(nil)
            }
        default:
            break
        }
    }

    fileprivate func handleICEConnectionState(_ state: RTCIceConnectionState) {
        guard !intentionallyClosed else { return }
#if DEBUG
        print("[RemoteWebRTC] ice connection connectionId=\(connectionId) state=\(Self.iceConnectionStateDescription(state))")
#endif
        switch state {
        case .connected, .completed:
            disconnectedFailTask?.cancel()
            disconnectedFailTask = nil
            scheduleDataChannelOpenTimeout(reason: Self.iceConnectionStateDescription(state))
#if DEBUG
            logSelectedCandidatePair(reason: Self.iceConnectionStateDescription(state))
#endif
            if !isConnected, dataChannel?.readyState == .open {
                isConnected = true
                onConnect?()
            }
        case .failed:
            fail(RemoteChatError.remoteConnectionFailed)
        case .disconnected:
            scheduleDisconnectedGraceFailure()
        default:
            break
        }
    }

    fileprivate func handleDataChannelBuffer(_ buffer: RTCDataBuffer) {
        guard !intentionallyClosed else { return }
        guard let text = String(data: buffer.data, encoding: .utf8) else {
            onDecodeFailure?("<binary frame>")
            return
        }
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

    private func makePeerConnection() -> RTCPeerConnection? {
        let config = RTCConfiguration()
        config.iceServers = iceServers.map { server in
            RTCIceServer(
                urlStrings: server.urls,
                username: server.username ?? "",
                credential: server.credential ?? ""
            )
        }
        config.iceCandidatePoolSize = 2
        config.sdpSemantics = .unifiedPlan
        config.iceTransportPolicy = .all
        config.candidateNetworkPolicy = .all
        config.continualGatheringPolicy = .gatherContinually
        config.tcpCandidatePolicy = .enabled
        config.disableIPV6OnWiFi = false
        config.maxIPv6Networks = Int32.max
        config.disableLinkLocalNetworks = true
#if DEBUG
        print("[RemoteWebRTC] ice servers connectionId=\(connectionId) \(icePolicySummary.logDescription) urls=\(Self.iceServersDebugDescription(iceServers))")
#endif
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        return factory.peerConnection(with: config, constraints: constraints, delegate: delegate)
    }

    private func offer() {
        guard !intentionallyClosed else { return }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection?.offer(for: constraints) { [weak self] description, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.intentionallyClosed, let description, error == nil else { return }
                self.peerConnection?.setLocalDescription(description) { [weak self] error in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.intentionallyClosed, error == nil else { return }
#if DEBUG
                        print("[RemoteWebRTC] local offer ready connectionId=\(self.connectionId) \(Self.sdpDebugDescription(description.sdp))")
#endif
                        self.relayLocalDescription(kind: "offer", description: description)
                    }
                }
            }
        }
    }

    private func answer() {
        guard !intentionallyClosed else { return }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection?.answer(for: constraints) { [weak self] description, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.intentionallyClosed, let description, error == nil else { return }
                self.peerConnection?.setLocalDescription(description) { [weak self] error in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.intentionallyClosed, error == nil else { return }
#if DEBUG
                        print("[RemoteWebRTC] local answer ready connectionId=\(self.connectionId) \(Self.sdpDebugDescription(description.sdp))")
#endif
                        self.relayLocalDescription(kind: "answer", description: description)
                    }
                }
            }
        }
    }

    private func setRemoteDescription(_ description: RTCSessionDescription, completion: (() -> Void)? = nil) {
        guard !intentionallyClosed else { return }
        let scrubbed = RemoteICEPolicy.scrubSDP(description.sdp)
#if DEBUG
        if scrubbed.removedCandidates {
            print("[RemoteWebRTC] scrubbed remote SDP connectionId=\(connectionId) type=\(description.type.rawValue) removedCandidates=\(scrubbed.removedCandidateCount)")
        }
#endif
        let safeDescription = RTCSessionDescription(type: description.type, sdp: scrubbed.sdp)
        peerConnection?.setRemoteDescription(safeDescription) { [weak self] error in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.intentionallyClosed else { return }
                if let error {
#if DEBUG
                    print("[RemoteWebRTC] setRemoteDescription failed: \(error.localizedDescription)")
#endif
                    self.fail(RemoteChatError.remoteConnectionFailed)
                    return
                }
#if DEBUG
                print("[RemoteWebRTC] setRemoteDescription ok connectionId=\(self.connectionId) type=\(safeDescription.type.rawValue) sdpBytes=\(safeDescription.sdp.utf8.count) \(Self.sdpDebugDescription(safeDescription.sdp))")
#endif
                self.didSetRemoteDescription = true
                let candidates = self.pendingRemoteCandidates
                self.pendingRemoteCandidates.removeAll()
                for candidate in candidates {
                    self.addCandidate(candidate)
                }
                completion?()
            }
        }
    }

    private func relayLocalDescription(kind: String, description: RTCSessionDescription) {
        let scrubbed = RemoteICEPolicy.scrubSDP(description.sdp)
#if DEBUG
        if scrubbed.removedCandidates {
            print("[RemoteWebRTC] scrubbed local SDP connectionId=\(connectionId) kind=\(kind) removedCandidates=\(scrubbed.removedCandidateCount)")
        }
#endif
        relay(RemoteSignalingPayload(kind: kind, sdp: scrubbed.sdp))
    }

    private func addRemoteCandidate(_ candidate: RTCIceCandidate) {
        guard !intentionallyClosed else { return }
        guard didSetRemoteDescription else {
            pendingRemoteCandidates.append(candidate)
            return
        }
        addCandidate(candidate)
    }

    private func addCandidate(_ candidate: RTCIceCandidate) {
        peerConnection?.add(candidate) { error in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.intentionallyClosed else { return }
                if let error {
                    print("[RemoteWebRTC] Failed to add ICE candidate: \(error.localizedDescription)")
                } else {
#if DEBUG
                    print("[RemoteWebRTC] add remote candidate ok connectionId=\(self.connectionId) \(Self.candidateDebugDescription(candidate.sdp))")
#endif
                }
            }
        }
    }

    private func relay(_ payload: RemoteSignalingPayload) {
#if DEBUG
        print("[RemoteWebRTC] signaling relay send connectionId=\(connectionId) kind=\(payload.kind) \(payload.sdp.map { Self.sdpDebugDescription($0) } ?? "")")
#endif
        Task { @MainActor [signalingClient, connectionId, targetDeviceId] in
            let sent = signalingClient.relay(connectionId: connectionId, toDeviceId: targetDeviceId, payload: payload)
            if !sent {
#if DEBUG
                print("[RemoteWebRTC] signaling relay send skipped connectionId=\(connectionId) kind=\(payload.kind)")
#endif
                self.fail(RemoteChatError.signalingUnavailable)
            }
        }
    }

    private func scheduleDataChannelOpenTimeout(reason: String) {
        guard dataChannel?.readyState != .open else { return }
        dataChannelOpenTask?.cancel()
        dataChannelOpenTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled, !self.intentionallyClosed, self.dataChannel?.readyState != .open else { return }
#if DEBUG
                print("[RemoteWebRTC] data channel open timeout connectionId=\(self.connectionId) reason=\(reason)")
#endif
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
        disconnectedFailTask?.cancel()
        disconnectedFailTask = nil
        dataChannelOpenTask?.cancel()
        dataChannelOpenTask = nil
        failureError = error
        isConnected = false
        onDisconnect?(error)
    }

    private func scheduleDisconnectedGraceFailure() {
        disconnectedFailTask?.cancel()
        disconnectedFailTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled, !self.intentionallyClosed else { return }
                self.fail(RemoteChatError.remoteConnectionFailed)
            }
        }
    }

    private func sendText(_ text: String) async throws {
        if !Thread.isMainThread {
            return try await MainActor.run {
                try self.sendTextOnCurrentThread(text)
            }
        }
        try sendTextOnCurrentThread(text)
    }

    private func sendTextOnCurrentThread(_ text: String) throws {
        guard !intentionallyClosed, let dataChannel, dataChannel.readyState == .open else { throw RemoteChatError.missingConfiguration }
        let data = Data(text.utf8)
        guard data.count <= RemoteRecoveryLimits.maximumTextFrameUTF8Bytes else {
            throw RemoteChatError.serverMessage(L10n.string("附件不能超过 10MB。"), statusCode: 413)
        }
        let buffer = RTCDataBuffer(data: data, isBinary: false)
        guard dataChannel.sendData(buffer) else {
            throw RemoteChatError.remoteConnectionFailed
        }
    }

    private func shouldIgnoreCandidate(_ sdp: String) -> Bool {
        RemoteICEPolicy.shouldRejectCandidate(sdp)
    }

#if DEBUG
    private func logSelectedCandidatePair(reason: String) {
        guard let peerConnection else { return }
        peerConnection.statistics { [weak self] report in
            guard let self else { return }
            if let description = Self.selectedCandidatePairDescription(from: report.statistics) {
                print("[RemoteWebRTC] selected candidate pair connectionId=\(self.connectionId) reason=\(reason) \(description)")
            } else {
                print("[RemoteWebRTC] selected candidate pair unavailable connectionId=\(self.connectionId) reason=\(reason)")
            }
        }
    }

    private static func selectedCandidatePairDescription(from statistics: [String: RTCStatistics]) -> String? {
        let pair = selectedCandidatePair(from: statistics)
        guard let pair else { return nil }
        let localID = stringValue(pair.values["localCandidateId"])
        let remoteID = stringValue(pair.values["remoteCandidateId"])
        let local = localID.flatMap { statistics[$0] }
        let remote = remoteID.flatMap { statistics[$0] }
        let localAddress = candidateAddress(from: local)
        let remoteAddress = candidateAddress(from: remote)
        let directUDP = candidateType(from: local) == "host" &&
            candidateType(from: remote) == "host" &&
            candidateProtocol(from: local) == "udp" &&
            candidateProtocol(from: remote) == "udp"
        let sameIPv6Prefix64 = sameIPv6Prefix64(localAddress, remoteAddress)
        let pairState = stringValue(pair.values["state"]) ?? "-"
        let nominated = boolValue(pair.values["nominated"]).map(String.init) ?? "-"
        let currentRTT = numberString(pair.values["currentRoundTripTime"]) ?? "-"
        return "pairId=\(pair.id) state=\(pairState) nominated=\(nominated) rtt=\(currentRTT) directUDP=\(directUDP) sameIPv6Prefix64=\(sameIPv6Prefix64) local=\(candidateDebugDescription(from: local)) remote=\(candidateDebugDescription(from: remote))"
    }

    private static func selectedCandidatePair(from statistics: [String: RTCStatistics]) -> RTCStatistics? {
        if let pairID = statistics.values
            .first(where: { $0.type == "transport" })
            .flatMap({ stringValue($0.values["selectedCandidatePairId"]) }),
           let pair = statistics[pairID] {
            return pair
        }
        if let selected = statistics.values.first(where: { $0.type == "candidate-pair" && boolValue($0.values["selected"]) == true }) {
            return selected
        }
        return statistics.values.first {
            $0.type == "candidate-pair" &&
                stringValue($0.values["state"]) == "succeeded" &&
                boolValue($0.values["nominated"]) == true
        }
    }

    private static func candidateDebugDescription(from stat: RTCStatistics?) -> String {
        guard let stat else { return "missing" }
        let type = candidateType(from: stat) ?? "-"
        let proto = candidateProtocol(from: stat) ?? "-"
        let address = candidateAddress(from: stat) ?? "-"
        let port = numberString(stat.values["port"]) ?? stringValue(stat.values["port"]) ?? "-"
        let networkType = stringValue(stat.values["networkType"]) ?? "-"
        return "type=\(type) proto=\(proto) addr=\(address):\(port) network=\(networkType)"
    }

    private static func candidateType(from stat: RTCStatistics?) -> String? {
        stat.flatMap { stringValue($0.values["candidateType"])?.lowercased() }
    }

    private static func candidateProtocol(from stat: RTCStatistics?) -> String? {
        stat.flatMap { stringValue($0.values["protocol"])?.lowercased() }
    }

    private static func candidateAddress(from stat: RTCStatistics?) -> String? {
        guard let stat else { return nil }
        return stringValue(stat.values["address"]) ?? stringValue(stat.values["ip"])
    }

    private static func sameIPv6Prefix64(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs, lhs.contains(":"), rhs.contains(":") else { return false }
        return lhs.split(separator: ":").prefix(4).map(String.init) == rhs.split(separator: ":").prefix(4).map(String.init)
    }

    private static func stringValue(_ value: NSObject?) -> String? {
        switch value {
        case let value as NSString:
            return value as String
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private static func boolValue(_ value: NSObject?) -> Bool? {
        switch value {
        case let value as NSNumber:
            return value.boolValue
        case let value as NSString:
            let normalized = (value as String).lowercased()
            if normalized == "true" || normalized == "1" { return true }
            if normalized == "false" || normalized == "0" { return false }
            return nil
        default:
            return nil
        }
    }

    private static func numberString(_ value: NSObject?) -> String? {
        guard let number = value as? NSNumber else { return nil }
        return number.stringValue
    }
#endif

    private static func iceServersDebugDescription(_ servers: [RemoteICEServer]) -> String {
        servers.flatMap(\.urls).joined(separator: ",")
    }

    private static func candidateDebugDescription(_ sdp: String) -> String {
        let parts = sdp.split(separator: " ").map(String.init)
        let type = RemoteICEPolicy.candidateType(in: sdp)
        let protocolValue = RemoteICEPolicy.candidateProtocol(in: sdp)
        let address = RemoteICEPolicy.candidateAddress(in: sdp)
        let port = parts.count > 5 ? parts[5] : "unknown"
        let relatedAddress = value(after: "raddr", in: parts) ?? "-"
        let relatedPort = value(after: "rport", in: parts) ?? "-"
        return "type=\(type) proto=\(protocolValue) addr=\(address):\(port) raddr=\(relatedAddress):\(relatedPort)"
    }

    private static func value(after key: String, in parts: [String]) -> String? {
        guard let index = parts.firstIndex(of: key), parts.indices.contains(index + 1) else { return nil }
        return parts[index + 1]
    }

    private static func iceConnectionStateDescription(_ state: RTCIceConnectionState) -> String {
        switch state {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        case .count: return "count"
        @unknown default: return "unknown"
        }
    }

    private static func iceGatheringStateDescription(_ state: RTCIceGatheringState) -> String {
        switch state {
        case .new: return "new"
        case .gathering: return "gathering"
        case .complete: return "complete"
        @unknown default: return "unknown"
        }
    }

    private static func dataChannelStateDescription(_ state: RTCDataChannelState) -> String {
        switch state {
        case .connecting: return "connecting"
        case .open: return "open"
        case .closing: return "closing"
        case .closed: return "closed"
        @unknown default: return "unknown"
        }
    }

    private static func sdpDebugDescription(_ sdp: String) -> String {
        let normalized = sdp
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let firstLine = lines.first ?? ""
        return "lines=\(lines.count) endsWithNewline=\(sdp.hasSuffix("\n")) first=\(firstLine) hasMApplication=\(normalized.contains("\nm=application ")) hasFingerprint=\(normalized.contains("\na=fingerprint:")) hasSCTPPort=\(normalized.contains("\na=sctp-port:")) hasSCTPMap=\(normalized.contains("\na=sctpmap:")) setup=\(sdpLineValue(prefix: "a=setup:", in: normalized) ?? "-") mid=\(sdpLineValue(prefix: "a=mid:", in: normalized) ?? "-") candidates=\(candidateLineCount(in: sdp))"
    }

    private static func sdpLineValue(prefix: String, in normalizedSDP: String) -> String? {
        normalizedSDP
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)) }
    }

    private static func candidateLineCount(in sdp: String) -> Int {
        sdp
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { String($0).hasPrefix("a=candidate:") || String($0).hasPrefix("candidate:") }
            .count
    }
}
