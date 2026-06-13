import Foundation

struct RemoteChatConfig: Equatable {
    var macHost: String
    var port: Int
    var token: String
    var connectionId: Int? = nil
    var targetDeviceId: Int? = nil
    var transport: String? = nil
    var reason: String? = nil
    var remoteAccessToken: String? = nil
    var remoteAPIBaseURL: URL? = nil
    var remoteTransport: RemoteTransport? = nil
    var remoteRelayReady: Bool = true

    var isComplete: Bool {
        remoteTransport != nil || (
            connectionId != nil &&
            targetDeviceId != nil &&
            !(remoteAccessToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    var supportsDirectHTTP: Bool {
        let host = macHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host.lowercased() != "tunnel", port > 0 else { return false }
        let authToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return !authToken.isEmpty
    }

    var baseURL: URL? {
        guard supportsDirectHTTP else { return nil }
        return URL(string: "http://\(macHost):\(port)")
    }

    var webSocketURL: URL? {
        guard supportsDirectHTTP else { return nil }
        return URL(string: "ws://\(macHost):\(port)/chat")
    }
}

struct RemoteICEPolicySummary: Hashable {
    let policy: String
    let relayCapable: Bool
    let stunURLCount: Int
    let turnURLCount: Int
    let usableServerCount: Int

    var logDescription: String {
        "icePolicy=\(policy) relayCapable=\(relayCapable) stun=\(stunURLCount) turn=\(turnURLCount) servers=\(usableServerCount)"
    }
}

struct RemoteSDPScrubResult: Hashable {
    let sdp: String
    let removedCandidateCount: Int

    var removedCandidates: Bool {
        removedCandidateCount > 0
    }
}

enum RemoteICEPolicy {
    static let relayCapableName = "relayCapable"

    static func relayCapableServers(from servers: [RemoteICEServer]) -> [RemoteICEServer] {
        normalizedServers(from: servers, allowingTURN: true)
    }

    static func normalizedServers(from servers: [RemoteICEServer], allowingTURN: Bool) -> [RemoteICEServer] {
        servers.compactMap { server in
            let urls = server.urls
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { isSTUNURL($0) || (allowingTURN && isTURNURL($0)) }
            guard !urls.isEmpty else { return nil }
            return RemoteICEServer(urls: urls, username: server.username, credential: server.credential, realm: server.realm)
        }
    }

    static func summary(from servers: [RemoteICEServer]) -> RemoteICEPolicySummary {
        let trimmedURLs = servers.flatMap(\.urls).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let stunCount = trimmedURLs.filter(isSTUNURL).count
        let turnCount = trimmedURLs.filter(isTURNURL).count
        let usableServers = relayCapableServers(from: servers).count
        return RemoteICEPolicySummary(
            policy: relayCapableName,
            relayCapable: turnCount > 0,
            stunURLCount: stunCount,
            turnURLCount: turnCount,
            usableServerCount: usableServers
        )
    }

    static func isAllowedCandidate(_ sdp: String) -> Bool {
        let parsed = candidateParts(in: sdp)
        switch parsed.type {
        case "host", "srflx":
            guard parsed.proto == "udp" else { return false }
            return isUsableCandidateAddress(parsed.address)
        case "relay":
            guard parsed.proto == "udp" || parsed.proto == "tcp" else { return false }
            return isUsableCandidateAddress(parsed.address)
        default:
            return false
        }
    }

    static func shouldRejectCandidate(_ sdp: String) -> Bool {
        !isAllowedCandidate(sdp)
    }

    static func candidateType(in sdp: String) -> String {
        candidateParts(in: sdp).type
    }

    static func candidateProtocol(in sdp: String) -> String {
        candidateParts(in: sdp).proto
    }

    static func candidateAddress(in sdp: String) -> String {
        candidateParts(in: sdp).address
    }

    private static func candidateParts(in sdp: String) -> (type: String, proto: String, address: String) {
        let parts = sdp.split(separator: " ").map(String.init)
        let type: String
        if let index = parts.firstIndex(of: "typ"), parts.indices.contains(index + 1) {
            type = parts[index + 1].lowercased()
        } else {
            type = "missing"
        }
        let proto = parts.count > 2 ? parts[2].lowercased() : "missing"
        let address = parts.count > 4 ? parts[4].lowercased() : "missing"
        return (type, proto, address)
    }

    static func scrubSDP(_ sdp: String) -> RemoteSDPScrubResult {
        let lineSeparator = sdp.contains("\r\n") ? "\r\n" : "\n"
        let hadTrailingNewline = sdp.hasSuffix("\n")
        var removed = 0
        let keptLines = sdp
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { line in
                let normalizedLine = line.hasSuffix("\r") ? String(line.dropLast()) : line
                guard isCandidateLine(normalizedLine) else { return true }
                let candidate = normalizedLine.hasPrefix("a=") ? String(normalizedLine.dropFirst(2)) : normalizedLine
                let allowed = isAllowedCandidate(candidate)
                if !allowed { removed += 1 }
                return allowed
            }
        var scrubbed = keptLines.joined(separator: lineSeparator)
        if !scrubbed.isEmpty, !hadTrailingNewline {
            scrubbed += lineSeparator
        } else if hadTrailingNewline {
            scrubbed += lineSeparator
        }
        return RemoteSDPScrubResult(sdp: scrubbed, removedCandidateCount: removed)
    }

    private static func isCandidateLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("a=candidate:") || trimmed.hasPrefix("candidate:")
    }

    private static func isSTUNURL(_ url: String) -> Bool {
        url.lowercased().hasPrefix("stun:")
    }

    private static func isTURNURL(_ url: String) -> Bool {
        let lowercased = url.lowercased()
        return lowercased.hasPrefix("turn:") || lowercased.hasPrefix("turns:")
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
}

extension RemoteChatConfig {
    static func == (lhs: RemoteChatConfig, rhs: RemoteChatConfig) -> Bool {
        lhs.macHost == rhs.macHost &&
        lhs.port == rhs.port &&
        lhs.token == rhs.token &&
        lhs.connectionId == rhs.connectionId &&
        lhs.targetDeviceId == rhs.targetDeviceId &&
        lhs.transport == rhs.transport &&
            lhs.reason == rhs.reason &&
            lhs.remoteAccessToken == rhs.remoteAccessToken &&
            lhs.remoteAPIBaseURL == rhs.remoteAPIBaseURL &&
            lhs.remoteRelayReady == rhs.remoteRelayReady
    }
}

enum RemoteChatError: LocalizedError {
    case missingConfiguration
    case invalidURL
    case badStatus(Int)
    case serverMessage(String, statusCode: Int)
    case emptyResponse
    case webSocketMessageUnsupported
    case signalingUnavailable
    case remoteConnectionFailed
    case remoteTransportUnavailable

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: L10n.string("请先连接远程设备。")
        case .invalidURL: L10n.string("连接地址无效。")
        case .badStatus(let code): L10n.format("服务器返回错误状态：%d。", code)
        case .serverMessage(let message, _): message
        case .emptyResponse: L10n.string("服务器返回为空。")
        case .webSocketMessageUnsupported: L10n.string("收到不支持的 WebSocket 消息。")
        case .signalingUnavailable: L10n.string("信令通道不可用，请确认网络连接后重试。")
        case .remoteConnectionFailed: L10n.string("远程直连没有建立成功，请确认电脑端在线，并检查是否在同一 Wi‑Fi、已配置端口映射，或稍后重试。")
        case .remoteTransportUnavailable: L10n.string("远程直连没有建立成功，请确认电脑端在线，并检查是否在同一 Wi‑Fi、已配置端口映射，或稍后重试。")
        }
    }
}

struct RemoteServerErrorPayload: Decodable {
    let error: String?
    let message: String?
}
