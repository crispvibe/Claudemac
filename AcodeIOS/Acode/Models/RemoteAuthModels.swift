import Foundation

struct RemoteAPIEnvelope<DataType: Decodable>: Decodable {
    let code: Int
    let data: DataType?
    let msg: String

    private enum CodingKeys: String, CodingKey {
        case code
        case data
        case msg
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = (try? container.decode(Int.self, forKey: .code)) ?? -1
        msg = (try? container.decode(String.self, forKey: .msg)) ?? ""
        data = try? container.decode(DataType.self, forKey: .data)
    }
}

struct RemoteAPIEmptyPayload: Codable, Hashable {}

struct RemoteAPIIgnoredPayload: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}

struct RemoteAuthUser: Codable, Hashable {
    let id: Int
    let email: String
    let phone: String?
    let status: String

    var displayAccount: String {
        if !email.isEmpty { return email }
        return phone ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case email
        case phone
        case status
    }

    init(id: Int, email: String, phone: String? = nil, status: String) {
        self.id = id
        self.email = email
        self.phone = phone
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        let decodedEmail = (try? container.decode(String.self, forKey: .email)) ?? ""
        let decodedPhone = try? container.decode(String.self, forKey: .phone)
        email = decodedEmail.isEmpty ? (decodedPhone ?? "") : decodedEmail
        phone = decodedPhone
        status = (try? container.decode(String.self, forKey: .status)) ?? "active"
    }
}

struct RemoteAuthSession: Codable, Hashable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int64
    let user: RemoteAuthUser

    var expiryDate: Date {
        Date(timeIntervalSince1970: TimeInterval(expiresAt) / 1_000)
    }

    var isExpired: Bool {
        expiryDate <= Date()
    }
}

struct RemoteAuthLoginRequest: Codable {
    let email: String
    let password: String

    init(email: String, password: String) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.password = password
    }
}

struct RemoteAuthRegisterRequest: Codable {
    let email: String
    let password: String
    let verificationCode: String

    init(email: String, password: String, verificationCode: String) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.password = password
        self.verificationCode = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct RemoteAuthRefreshRequest: Codable {
    let refreshToken: String
}

struct RemoteVerificationCodeRequest: Codable {
    let email: String

    init(email: String) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct RemotePasswordResetRequest: Codable {
    let email: String
    let password: String
    let verificationCode: String

    init(email: String, password: String, verificationCode: String) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.password = password
        self.verificationCode = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct RemoteChangePasswordRequest: Codable {
    let currentPassword: String
    let newPassword: String
}

struct RemoteAccountDeletionRequest: Codable {
    let confirmAccount: String
    let confirmDestroy: String
    let confirmWaiveRights: String
    let reason: String
}

struct RemoteAccountDeletionResponse: Codable, Hashable {
    let recordId: Int
    let deletedAt: String
}

struct RemoteAppUpdateCheckResponse: Codable, Hashable {
    let updateAvailable: Bool
    let latestVersion: String
    let latestBuildNumber: String
    let minimumVersion: String
    let releaseNotes: String
    let updateType: String
    let downloadUrl: String
    let appStoreUrl: String
    let packageSha256: String
    let packageFileSize: Int64
    let forceUpdate: Bool
}

struct RemoteVerificationCodeResponse: Codable, Hashable {
    let verificationCode: String
    let expiresAt: Int64
}

struct RemoteLegalDocument: Codable, Identifiable, Hashable {
    let id: Int
    let type: String
    let platform: String
    let version: String
    let title: String
    let contentFormat: String
    let content: String
    let published: Bool

    var isMarkdown: Bool {
        contentFormat.lowercased() == "markdown"
    }
}

struct RemoteLegalConsentRequest: Codable {
    let documentId: Int
    let platform: String
    let deviceId: Int
}

struct RemoteDeviceRegisterRequest: Codable {
    let deviceUid: String
    let deviceType: String
    let platform: String
    let deviceName: String
    let devicePublicKey: String
    let appVersion: String
}

struct RemoteLanEndpoint: Decodable, Hashable {
    let ip: String
    let port: Int
    let lastSeenAt: String?

    private enum CodingKeys: String, CodingKey {
        case ip
        case port
        case lastSeenAt
        case lastSeenAtSnake = "last_seen_at"
    }

    init(ip: String, port: Int, lastSeenAt: String? = nil) {
        self.ip = ip
        self.port = port
        self.lastSeenAt = lastSeenAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ip = try container.decode(String.self, forKey: .ip)
        port = try container.decode(Int.self, forKey: .port)
        lastSeenAt = try container.decodeIfPresent(String.self, forKey: .lastSeenAt) ?? container.decodeIfPresent(String.self, forKey: .lastSeenAtSnake)
    }
}

struct RemoteDevice: Decodable, Identifiable, Hashable {
    let id: Int
    let userId: Int?
    let deviceUid: String?
    let deviceType: String?
    let platform: String?
    let deviceName: String
    let approvalPolicy: String
    let remoteEnabled: Bool
    let status: String
    let online: Bool
    let lastSeenAt: String?
    let lanEndpoint: RemoteLanEndpoint?
    let transientToken: String?

    init(id: Int, userId: Int?, deviceUid: String?, deviceType: String?, platform: String?, deviceName: String, approvalPolicy: String, remoteEnabled: Bool, status: String, online: Bool, lastSeenAt: String?, lanEndpoint: RemoteLanEndpoint?, transientToken: String?) {
        self.id = id
        self.userId = userId
        self.deviceUid = deviceUid
        self.deviceType = deviceType
        self.platform = platform
        self.deviceName = deviceName
        self.approvalPolicy = approvalPolicy
        self.remoteEnabled = remoteEnabled
        self.status = status
        self.online = online
        self.lastSeenAt = lastSeenAt
        self.lanEndpoint = lanEndpoint
        self.transientToken = transientToken
    }

    func withOnline(_ online: Bool) -> RemoteDevice {
        RemoteDevice(id: id, userId: userId, deviceUid: deviceUid, deviceType: deviceType, platform: platform, deviceName: deviceName, approvalPolicy: approvalPolicy, remoteEnabled: remoteEnabled, status: status, online: online, lastSeenAt: lastSeenAt, lanEndpoint: lanEndpoint, transientToken: transientToken)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case userId
        case deviceUid
        case deviceType
        case platform
        case deviceName
        case approvalPolicy
        case remoteEnabled
        case status
        case online
        case lastSeenAt
        case lanEndpoint
        case lanEndpointSnake = "lan_endpoint"
        case transientToken
        case transientTokenSnake = "transient_token"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        userId = try container.decodeIfPresent(Int.self, forKey: .userId)
        deviceUid = try container.decodeIfPresent(String.self, forKey: .deviceUid)
        deviceType = try container.decodeIfPresent(String.self, forKey: .deviceType)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? "我的电脑"
        approvalPolicy = try container.decodeIfPresent(String.self, forKey: .approvalPolicy) ?? "always_ask"
        remoteEnabled = try container.decodeIfPresent(Bool.self, forKey: .remoteEnabled) ?? true
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
        online = try container.decodeIfPresent(Bool.self, forKey: .online) ?? false
        lastSeenAt = try container.decodeIfPresent(String.self, forKey: .lastSeenAt)
        lanEndpoint = try container.decodeIfPresent(RemoteLanEndpoint.self, forKey: .lanEndpoint) ?? container.decodeIfPresent(RemoteLanEndpoint.self, forKey: .lanEndpointSnake)
        transientToken = try container.decodeIfPresent(String.self, forKey: .transientToken) ?? container.decodeIfPresent(String.self, forKey: .transientTokenSnake)
    }
}

struct RemoteDeviceCodeResolveRequest: Codable {
    let deviceCode: String
    let fromDeviceId: Int
    let fromDeviceUid: String
    let fromDevicePublicKey: String
}

struct RemoteDeviceResolveResponse: Codable, Hashable {
    let deviceId: Int
    let deviceName: String
    let platform: String
    let approvalPolicy: String
    let requiresConfirm: Bool
}

struct RemoteConnectRequest: Codable {
    let fromDeviceId: Int
    let fromDeviceUid: String
    let fromDevicePublicKey: String
}

struct RemoteICEServer: Codable, Hashable {
    let urls: [String]
    let username: String?
    let credential: String?
    let realm: String?
}

struct RemoteICEConfiguration: Codable, Hashable {
    let iceServers: [RemoteICEServer]
}

struct RemoteSignalingPayload: Codable, Hashable {
    let kind: String
    let sdp: String?
    let sdpMid: String?
    let sdpMLineIndex: Int32?
    let candidate: String?
    let message: String?

    init(kind: String, sdp: String? = nil, sdpMid: String? = nil, sdpMLineIndex: Int32? = nil, candidate: String? = nil, message: String? = nil) {
        self.kind = kind
        self.sdp = sdp
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
        self.candidate = candidate
        self.message = message
    }
}

struct RemoteConnectionAttempt: Decodable, Identifiable, Hashable {
    let id: Int
    let connectionId: Int?
    let fromUserId: Int?
    let fromDeviceId: Int?
    let toUserId: Int?
    let toDeviceId: Int?
    let grantId: Int?
    let status: String
    let reason: String?
    let completedAt: String?
    let transport: String?
    let endpoint: RemoteLanEndpoint?
    let transientToken: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case connectionId
        case connectionIdSnake = "connection_id"
        case fromUserId
        case fromUserIdSnake = "from_user_id"
        case fromDeviceId
        case fromDeviceIdSnake = "from_device_id"
        case toUserId
        case toUserIdSnake = "to_user_id"
        case toDeviceId
        case toDeviceIdSnake = "to_device_id"
        case grantId
        case grantIdSnake = "grant_id"
        case status
        case reason
        case completedAt
        case completedAtSnake = "completed_at"
        case transport
        case endpoint
        case transientToken
        case transientTokenSnake = "transient_token"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        connectionId = try container.decodeIfPresent(Int.self, forKey: .connectionId) ?? container.decodeIfPresent(Int.self, forKey: .connectionIdSnake)
        fromUserId = try container.decodeIfPresent(Int.self, forKey: .fromUserId) ?? container.decodeIfPresent(Int.self, forKey: .fromUserIdSnake)
        fromDeviceId = try container.decodeIfPresent(Int.self, forKey: .fromDeviceId) ?? container.decodeIfPresent(Int.self, forKey: .fromDeviceIdSnake)
        toUserId = try container.decodeIfPresent(Int.self, forKey: .toUserId) ?? container.decodeIfPresent(Int.self, forKey: .toUserIdSnake)
        toDeviceId = try container.decodeIfPresent(Int.self, forKey: .toDeviceId) ?? container.decodeIfPresent(Int.self, forKey: .toDeviceIdSnake)
        grantId = try container.decodeIfPresent(Int.self, forKey: .grantId) ?? container.decodeIfPresent(Int.self, forKey: .grantIdSnake)
        status = try container.decode(String.self, forKey: .status)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt) ?? container.decodeIfPresent(String.self, forKey: .completedAtSnake)
        transport = try container.decodeIfPresent(String.self, forKey: .transport)
        endpoint = try container.decodeIfPresent(RemoteLanEndpoint.self, forKey: .endpoint)
        transientToken = try container.decodeIfPresent(String.self, forKey: .transientToken) ?? container.decodeIfPresent(String.self, forKey: .transientTokenSnake)
    }
}

struct RemoteConnectionMetricsRequest: Codable, Hashable {
    let transport: String
    let firstPacketLatencyMs: Int?
    let stage: String?
    let path: String?
}

enum RemoteLegalDocumentType: String, CaseIterable, Hashable {
    case privacyPolicy = "privacy_policy"
    case userAgreement = "user_agreement"

    var title: String {
        switch self {
        case .privacyPolicy: L10n.string("隐私政策")
        case .userAgreement: L10n.string("用户协议")
        }
    }
}

struct RemoteAppFooter: Codable, Equatable {
    let companyName: String
    let copyrightText: String
    let icpText: String
    let recordText: String?
    let supportUrl: String?
    let privacyUrl: String?

    var displayLines: [String] {
        [
            copyrightText,
            icpText,
            recordText
        ]
        .compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    static let `default` = RemoteAppFooter(
        companyName: "禾屿科技",
        copyrightText: "© 2026 禾屿科技",
        icpText: "ICP备案信息待更新",
        recordText: nil,
        supportUrl: nil,
        privacyUrl: nil
    )
}
