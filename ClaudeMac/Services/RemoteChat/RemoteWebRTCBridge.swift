import Foundation
import ChatCore
import WebRTC

private final class RemoteWebRTCBridgeDelegate: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate {
    weak var owner: RemoteWebRTCBridge?

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
            owner?.adopt(dataChannel: dataChannel)
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
            owner?.receive(buffer: copied)
        }
    }
}

final class RemoteWebRTCBridge {
    private let connectionId: Int
    private let peerDeviceId: Int
    private let signalingClient: SignalingClient
    private let onTextFrame: (String, @escaping (String) -> Void) -> Void
    var onClose: (() -> Void)?
    var onOpen: (() -> Void)?
    private let factory = RTCPeerConnectionFactory()
    private let delegate = RemoteWebRTCBridgeDelegate()
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var didSetRemoteDescription = false
    private var pendingRemoteCandidates: [RTCIceCandidate] = []
    private var isClosed = true
    private var didNotifyOpen = false
    private var disconnectedFailTask: Task<Void, Never>?
    private var dataChannelOpenTask: Task<Void, Never>?

    init(connectionId: Int, peerDeviceId: Int, signalingClient: SignalingClient, onTextFrame: @escaping (String, @escaping (String) -> Void) -> Void) {
        self.connectionId = connectionId
        self.peerDeviceId = peerDeviceId
        self.signalingClient = signalingClient
        self.onTextFrame = onTextFrame
        delegate.owner = self
    }

    func start(iceServers: [RemoteICEServer]) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.start(iceServers: iceServers)
            }
            return
        }
        isClosed = false
        let policyIceServers = Self.policyFilteredICEServers(iceServers)
        let config = RTCConfiguration()
        config.iceServers = policyIceServers.servers.map {
            RTCIceServer(urlStrings: $0.urls, username: $0.username ?? "", credential: $0.credential ?? "")
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
        print("[RemoteWebRTCBridge] ice servers connectionId=\(connectionId) active=\(Self.iceServersDebugDescription(policyIceServers.servers)) turnURLCount=\(policyIceServers.turnURLCount) ignoredURLCount=\(policyIceServers.ignoredURLCount)")
        peerConnection = factory.peerConnection(with: config, constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: delegate)
        scheduleDataChannelOpenTimeout(reason: "start")
    }

    func close() {
        close(notify: false)
    }

    func receiveRelayPayload(_ payload: RemoteSignalingPayload) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.receiveRelayPayload(payload)
            }
            return
        }
        guard !isClosed else { return }
        switch payload.kind {
        case "offer":
            guard let sdp = payload.sdp, !sdp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("[RemoteWebRTCBridge] offer ignored connectionId=\(connectionId): empty SDP")
                return
            }
            let scrubbed = Self.scrubDisallowedCandidateLines(from: sdp)
            logSDPScrubIfNeeded(original: sdp, scrubbed: scrubbed, direction: "remote", kind: payload.kind)
            setRemoteDescription(RTCSessionDescription(type: .offer, sdp: scrubbed)) { [weak self] in
                self?.answer()
            }
        case "candidate":
            guard let candidate = payload.candidate else { return }
            addRemoteCandidate(RTCIceCandidate(sdp: candidate, sdpMLineIndex: payload.sdpMLineIndex ?? 0, sdpMid: payload.sdpMid))
        case "answer":
            guard let sdp = payload.sdp, !sdp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("[RemoteWebRTCBridge] answer ignored connectionId=\(connectionId): empty SDP")
                return
            }
            let scrubbed = Self.scrubDisallowedCandidateLines(from: sdp)
            logSDPScrubIfNeeded(original: sdp, scrubbed: scrubbed, direction: "remote", kind: payload.kind)
            setRemoteDescription(RTCSessionDescription(type: .answer, sdp: scrubbed))
        default:
            break
        }
    }

    func sendText(_ text: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.sendText(text)
            }
            return
        }
        guard !isClosed else { return }
        guard let dataChannel, dataChannel.readyState == .open else { return }
        let didSend = dataChannel.sendData(RTCDataBuffer(data: Data(text.utf8), isBinary: false))
        if !didSend {
            print("[RemoteWebRTCBridge] send text failed connectionId=\(connectionId) bytes=\(text.utf8.count)")
        }
    }

    fileprivate func adopt(dataChannel: RTCDataChannel?) {
        guard !isClosed else { return }
        guard let dataChannel else { return }
        self.dataChannel = dataChannel
        dataChannel.delegate = delegate
        handleDataChannelState(dataChannel.readyState)
    }

    fileprivate func handleGeneratedCandidate(_ candidate: RTCIceCandidate) {
        guard !isClosed else { return }
        let ignoredByPolicy = !Self.isAllowedCandidate(candidate.sdp)
        print("[RemoteWebRTCBridge] local candidate connectionId=\(connectionId) \(Self.candidateDebugDescription(candidate.sdp, ignoredByPolicy: ignoredByPolicy))")
        guard !ignoredByPolicy else { return }
        sendCandidate(candidate)
    }

    fileprivate func sendCandidate(_ candidate: RTCIceCandidate) {
        relay(RemoteSignalingPayload(kind: "candidate", sdpMid: candidate.sdpMid, sdpMLineIndex: candidate.sdpMLineIndex, candidate: candidate.sdp))
    }

    fileprivate func handleICEGatheringState(_ state: RTCIceGatheringState) {
        guard !isClosed else { return }
        print("[RemoteWebRTCBridge] ice gathering connectionId=\(connectionId) state=\(Self.iceGatheringStateDescription(state))")
    }

    fileprivate func handleDataChannelState(_ state: RTCDataChannelState) {
        guard !isClosed else { return }
        print("[RemoteWebRTCBridge] data channel connectionId=\(connectionId) state=\(Self.dataChannelStateDescription(state))")
        if state == .open, !didNotifyOpen {
            didNotifyOpen = true
            dataChannelOpenTask?.cancel()
            dataChannelOpenTask = nil
            onOpen?()
        } else if state == .closed {
            close(notify: true)
        }
    }

    fileprivate func handleICEConnectionState(_ state: RTCIceConnectionState) {
        guard !isClosed else { return }
        print("[RemoteWebRTCBridge] ice connection connectionId=\(connectionId) state=\(Self.iceConnectionStateDescription(state))")
        switch state {
        case .connected, .completed:
            disconnectedFailTask?.cancel()
            disconnectedFailTask = nil
            scheduleDataChannelOpenTimeout(reason: Self.iceConnectionStateDescription(state))
            logSelectedCandidatePair(reason: Self.iceConnectionStateDescription(state))
        case .failed, .closed:
            close(notify: true)
        case .disconnected:
            scheduleDisconnectedGraceClose()
        default:
            break
        }
    }

    fileprivate func receive(buffer: RTCDataBuffer) {
        guard !isClosed else { return }
        guard buffer.data.count <= RemoteRecoveryLimits.maximumTextFrameUTF8Bytes else {
            if let data = try? RemoteChatHTTPCodec.jsonEncoder.encode(RemoteRecoveryResponse.error(requestId: Self.recoveryRequestId(from: buffer.data) ?? UUID(), message: "恢复请求过大，请压缩附件后重试。")),
               let text = String(data: data, encoding: .utf8) {
                sendText(text)
            }
            return
        }
        guard let text = String(data: buffer.data, encoding: .utf8) else { return }
        print("[RemoteWebRTCBridge] inbound text connectionId=\(connectionId) bytes=\(buffer.data.count)")
        onTextFrame(text) { [weak self] response in
            self?.sendText(response)
        }
    }

    private static func recoveryRequestId(from data: Data) -> UUID? {
        let prefix = data.prefix(4096)
        guard let text = String(data: prefix, encoding: .utf8) else { return nil }
        let pattern = #""requestId"\s*:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return UUID(uuidString: String(text[range]))
    }

    private func answer() {
        guard !isClosed else { return }
        peerConnection?.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { [weak self] description, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isClosed, let description, error == nil else { return }
                self.peerConnection?.setLocalDescription(description) { [weak self] error in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.isClosed, error == nil else { return }
                        let scrubbed = Self.scrubDisallowedCandidateLines(from: description.sdp)
                        self.logSDPScrubIfNeeded(original: description.sdp, scrubbed: scrubbed, direction: "local", kind: "answer")
                        self.relay(RemoteSignalingPayload(kind: "answer", sdp: scrubbed))
                    }
                }
            }
        }
    }

    private func setRemoteDescription(_ description: RTCSessionDescription, completion: (() -> Void)? = nil) {
        guard !isClosed else { return }
        print("[RemoteWebRTCBridge] setRemoteDescription start connectionId=\(connectionId) type=\(description.type.rawValue) sdpBytes=\(description.sdp.utf8.count) \(Self.sdpDebugDescription(description.sdp))")
        peerConnection?.setRemoteDescription(description) { [weak self] error in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isClosed else { return }
                if let error {
                    print("[RemoteWebRTCBridge] setRemoteDescription failed connectionId=\(self.connectionId) type=\(description.type.rawValue) sdpBytes=\(description.sdp.utf8.count) \(Self.sdpDebugDescription(description.sdp)): \(error.localizedDescription)")
                    self.close(notify: true)
                    return
                }
                print("[RemoteWebRTCBridge] setRemoteDescription ok connectionId=\(self.connectionId) type=\(description.type.rawValue) sdpBytes=\(description.sdp.utf8.count)")
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

    private func addRemoteCandidate(_ candidate: RTCIceCandidate) {
        guard !isClosed else { return }
        if !Self.isAllowedCandidate(candidate.sdp) {
            print("[RemoteWebRTCBridge] remote candidate ignored connectionId=\(connectionId) \(Self.candidateDebugDescription(candidate.sdp, ignoredByPolicy: true))")
            return
        }
        guard didSetRemoteDescription else {
            pendingRemoteCandidates.append(candidate)
            return
        }
        addCandidate(candidate)
    }

    private func addCandidate(_ candidate: RTCIceCandidate) {
        peerConnection?.add(candidate) { error in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isClosed else { return }
                if let error {
                    print("[RemoteWebRTCBridge] add remote candidate failed connectionId=\(self.connectionId): \(error.localizedDescription)")
                } else {
                    print("[RemoteWebRTCBridge] add remote candidate ok connectionId=\(self.connectionId) \(Self.candidateDebugDescription(candidate.sdp, ignoredByPolicy: false))")
                }
            }
        }
    }

    private func close(notify: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.close(notify: notify)
            }
            return
        }
        guard !isClosed else { return }
        isClosed = true
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
        pendingRemoteCandidates.removeAll()
        if notify {
            onClose?()
        }
    }

    private func relay(_ payload: RemoteSignalingPayload) {
        print("[RemoteWebRTCBridge] signaling relay send connectionId=\(connectionId) kind=\(payload.kind) \(payload.sdp.map { Self.sdpDebugDescription($0) } ?? "")")
        Task { @MainActor [signalingClient, connectionId, peerDeviceId] in
            let sent = signalingClient.sendSignalingRelay(connectionId: connectionId, toDeviceId: peerDeviceId, payload: payload)
            if !sent {
                print("[RemoteWebRTCBridge] signaling relay send skipped connectionId=\(connectionId) kind=\(payload.kind)")
                self.close(notify: true)
            }
        }
    }

    private func scheduleDataChannelOpenTimeout(reason: String) {
        guard dataChannel?.readyState != .open else { return }
        dataChannelOpenTask?.cancel()
        dataChannelOpenTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled, !self.isClosed, self.dataChannel?.readyState != .open else { return }
                print("[RemoteWebRTCBridge] data channel open timeout connectionId=\(self.connectionId) reason=\(reason)")
                self.close(notify: true)
            }
        }
    }

    private func scheduleDisconnectedGraceClose() {
        disconnectedFailTask?.cancel()
        disconnectedFailTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled, !self.isClosed else { return }
                self.close(notify: true)
            }
        }
    }

    private func logSDPScrubIfNeeded(original: String, scrubbed: String, direction: String, kind: String) {
        let removed = Self.candidateLineCount(in: original) - Self.candidateLineCount(in: scrubbed)
        guard removed > 0 else { return }
        print("[RemoteWebRTCBridge] \(direction) \(kind) SDP candidate scrubbed connectionId=\(connectionId) removed=\(removed)")
    }

    private func logSelectedCandidatePair(reason: String) {
        guard let peerConnection else { return }
        peerConnection.statistics { [weak self] report in
            guard let self else { return }
            if let description = Self.selectedCandidatePairDescription(from: report.statistics) {
                print("[RemoteWebRTCBridge] selected candidate pair connectionId=\(self.connectionId) reason=\(reason) \(description)")
            } else {
                print("[RemoteWebRTCBridge] selected candidate pair unavailable connectionId=\(self.connectionId) reason=\(reason)")
            }
        }
    }

    private static func iceServersDebugDescription(_ servers: [RemoteICEServer]) -> String {
        servers.flatMap(\.urls).joined(separator: ",")
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

    private static func candidateDebugDescription(_ sdp: String, ignoredByPolicy: Bool) -> String {
        let parts = sdp.split(separator: " ").map(String.init)
        let type = candidateType(from: sdp) ?? "unknown"
        let protocolValue = parts.count > 2 ? parts[2].lowercased() : "unknown"
        let address = parts.count > 4 ? parts[4] : "unknown"
        let port = parts.count > 5 ? parts[5] : "unknown"
        let relatedAddress = value(after: "raddr", in: parts) ?? "-"
        let relatedPort = value(after: "rport", in: parts) ?? "-"
        return "type=\(type) proto=\(protocolValue) addr=\(address):\(port) raddr=\(relatedAddress):\(relatedPort) ignoredByPolicy=\(ignoredByPolicy)"
    }

    static func isAllowedCandidate(_ sdp: String) -> Bool {
        let parts = candidateParts(from: sdp)
        switch parts.type {
        case "host", "srflx":
            guard parts.proto == "udp" else { return false }
            return isUsableCandidateAddress(parts.address)
        case "relay":
            guard parts.proto == "udp" || parts.proto == "tcp" else { return false }
            return isUsableCandidateAddress(parts.address)
        default:
            return false
        }
    }

    static func isAllowedDirectCandidate(_ sdp: String) -> Bool {
        isAllowedCandidate(sdp)
    }

    static func scrubDisallowedCandidateLines(from sdp: String) -> String {
        guard !sdp.isEmpty else { return sdp }
        let normalized = sdp
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let preservesTrailingNewline = normalized.hasSuffix("\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if preservesTrailingNewline, lines.last == "" {
            lines.removeLast()
        }
        let kept = lines.compactMap { line -> String? in
            guard isCandidateLine(line) else { return line }
            return isAllowedCandidate(line) ? line : nil
        }
        let body = kept.joined(separator: "\r\n")
        return body.isEmpty ? "" : body + "\r\n"
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
            .filter { isCandidateLine(String($0)) }
            .count
    }

    private static func isCandidateLine(_ line: String) -> Bool {
        line.hasPrefix("a=candidate:") || line.hasPrefix("candidate:")
    }

    private static func candidateType(from sdp: String) -> String? {
        let type = candidateParts(from: sdp).type
        return type == "missing" ? nil : type
    }

    private static func candidateParts(from sdp: String) -> (type: String, proto: String, address: String) {
        let parts = sdp.split(separator: " ").map(String.init)
        let type = value(after: "typ", in: parts)?.lowercased() ?? "missing"
        let proto = parts.count > 2 ? parts[2].lowercased() : "missing"
        let address = parts.count > 4 ? parts[4].lowercased() : "missing"
        return (type, proto, address)
    }

    private static func isUsableCandidateAddress(_ address: String) -> Bool {
        isUsableIPv4CandidateAddress(address) || isUsableIPv6CandidateAddress(address)
    }

    private static func isUsableIPv4CandidateAddress(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (octets[0], octets[1]) {
        case (0, _), (127, _), (169, 254), (198, 18), (198, 19):
            return false
        case (192, 0):
            return false
        default:
            return true
        }
    }

    private static func isUsableIPv6CandidateAddress(_ address: String) -> Bool {
        let lowercased = address.lowercased()
        guard lowercased.contains(":") else { return false }
        guard lowercased.hasPrefix("2") || lowercased.hasPrefix("3") else { return false }
        return true
    }

    private static func policyFilteredICEServers(_ servers: [RemoteICEServer]) -> (servers: [RemoteICEServer], turnURLCount: Int, ignoredURLCount: Int) {
        var turnURLCount = 0
        var ignoredURLCount = 0
        let filtered = servers.compactMap { server -> RemoteICEServer? in
            var keptURLs: [String] = []
            for url in server.urls {
                let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if isTurnURL(trimmed) {
                    turnURLCount += 1
                    keptURLs.append(trimmed)
                    continue
                }
                if isStunURL(trimmed) {
                    keptURLs.append(trimmed)
                    continue
                }
                ignoredURLCount += 1
            }
            guard !keptURLs.isEmpty else { return nil }
            return RemoteICEServer(urls: keptURLs, username: server.username, credential: server.credential, realm: server.realm)
        }
        return (filtered, turnURLCount, ignoredURLCount)
    }

    private static func isStunURL(_ url: String) -> Bool {
        let lowercased = url.lowercased()
        return lowercased.hasPrefix("stun:")
    }

    private static func isTurnURL(_ url: String) -> Bool {
        let lowercased = url.lowercased()
        return lowercased.hasPrefix("turn:") || lowercased.hasPrefix("turns:")
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
}
