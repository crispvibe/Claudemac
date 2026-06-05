import Foundation

struct AccountAPIEnvelope<DataType: Decodable>: Decodable {
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

struct AccountAPIEmptyPayload: Codable, Hashable {}

struct AccountAPIIgnoredPayload: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}

enum AccountMessageSeverity {
    case info
    case success
    case error
}

enum AccountAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized(String)
    case server(code: Int, message: String)
    case transport(Error)
    case decoding(Error)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "连接地址无效。"
        case .invalidResponse:
            "服务器返回异常。"
        case .unauthorized(let message):
            AccountRemoteUserFacingText.apiError(message, fallback: "登录状态失效，请重新登录。")
        case .server(_, let message):
            AccountRemoteUserFacingText.apiError(message, fallback: "请求失败。")
        case .transport(let error):
            AccountRemoteUserFacingText.apiError(error.localizedDescription, fallback: "网络连接失败，请稍后重试。")
        case .decoding:
            "响应解析失败。"
        case .emptyResponse:
            "服务器返回为空。"
        }
    }
}

enum AccountRemoteUserFacingText {
    static func apiError(_ rawMessage: String, fallback: String) -> String {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return fallback }
        switch normalize(message) {
        case "record not found":
            return fallback
        case "unauthorized", "token is expired", "invalid token", "没有所需的授权。", "没有所需的授权":
            return "登录状态已失效，请重新登录。"
        case "forbidden":
            return "当前账号没有权限执行此操作。"
        case "entitlement_required":
            return "当前账号未开通远程连接权限，请确认电脑端服务状态后再试。"
        case "grant_required":
            return "当前账号还没有这台 Mac 的连接授权。"
        case "network connection lost", "the network connection was lost.":
            return "网络连接已中断，请稍后重试。"
        case "timed out", "the request timed out.":
            return "请求超时，请检查网络后重试。"
        default:
            return containsLikelyEnglish(message) ? fallback : message
        }
    }

    static func loginError(_ rawMessage: String, fallback: String) -> String {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return fallback }
        switch normalize(message) {
        case "unauthorized", "token is expired", "invalid token", "没有所需的授权。", "没有所需的授权":
            return fallback
        default:
            return apiError(message, fallback: fallback)
        }
    }

    private static func normalize(_ rawValue: String?) -> String {
        rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func containsLikelyEnglish(_ text: String) -> Bool {
        text.range(of: "[A-Za-z_]{3,}", options: .regularExpression) != nil
    }
}

enum AccountRemoteConfig {
    static let baseURL = URL(string: "https://acode.anna.vin")!
    static let platform = "macos"
}

struct RemoteAuthUser: Codable, Hashable {
    let id: Int
    let email: String
    let status: String

    var displayAccount: String {
        email
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case email
        case status
    }

    init(id: Int, email: String = "", status: String) {
        self.id = id
        self.email = email
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        email = (try? container.decode(String.self, forKey: .email)) ?? ""
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

struct RemoteVerificationCodeResponse: Codable, Hashable {
    let verificationCode: String
    let expiresAt: Int64
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

struct RemoteLegalDocument: Codable, Identifiable, Hashable {
    let id: Int
    let type: String
    let platform: String
    let version: String
    let title: String
    let contentFormat: String
    let content: String
    let published: Bool
}

struct RemoteLegalConsentRequest: Codable {
    let documentId: Int
    let platform: String
    let deviceId: Int
}

enum RemoteLegalDocumentType: String, CaseIterable, Hashable {
    case privacyPolicy = "privacy_policy"
    case userAgreement = "user_agreement"

    var title: String {
        switch self {
        case .privacyPolicy: "隐私政策"
        case .userAgreement: "用户协议"
        }
    }
}

struct RemoteDeviceRegisterRequest: Codable {
    let deviceUid: String
    let deviceType: String
    let platform: String
    let deviceName: String
    let devicePublicKey: String
    let appVersion: String
}

struct RemoteDeviceUpdateRequest: Codable {
    let deviceName: String?
    let approvalPolicy: String?
    let remoteEnabled: Bool?
    let status: String?
    let appVersion: String?
}

struct RemoteDevice: Codable, Identifiable, Hashable {
    let id: Int
    let userId: Int?
    let deviceUid: String?
    let deviceType: String?
    let platform: String?
    let deviceName: String
    let devicePublicKey: String?
    let deviceCodeHint: String?
    let approvalPolicy: String
    let remoteEnabled: Bool
    let status: String
    let appVersion: String?
    let lastSeenAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case userId
        case deviceUid
        case deviceType
        case platform
        case deviceName
        case devicePublicKey
        case deviceCodeHint
        case approvalPolicy
        case remoteEnabled
        case status
        case appVersion
        case lastSeenAt
    }

    init(
        id: Int,
        userId: Int? = nil,
        deviceUid: String? = nil,
        deviceType: String? = nil,
        platform: String? = nil,
        deviceName: String,
        devicePublicKey: String? = nil,
        deviceCodeHint: String? = nil,
        approvalPolicy: String = "always_ask",
        remoteEnabled: Bool = true,
        status: String = "active",
        appVersion: String? = nil,
        lastSeenAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.deviceUid = deviceUid
        self.deviceType = deviceType
        self.platform = platform
        self.deviceName = deviceName
        self.devicePublicKey = devicePublicKey
        self.deviceCodeHint = deviceCodeHint
        self.approvalPolicy = approvalPolicy
        self.remoteEnabled = remoteEnabled
        self.status = status
        self.appVersion = appVersion
        self.lastSeenAt = lastSeenAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        userId = try container.decodeIfPresent(Int.self, forKey: .userId)
        deviceUid = try container.decodeIfPresent(String.self, forKey: .deviceUid)
        deviceType = try container.decodeIfPresent(String.self, forKey: .deviceType)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? "我的 Mac"
        devicePublicKey = try container.decodeIfPresent(String.self, forKey: .devicePublicKey)
        deviceCodeHint = try container.decodeIfPresent(String.self, forKey: .deviceCodeHint)
        approvalPolicy = try container.decodeIfPresent(String.self, forKey: .approvalPolicy) ?? "always_ask"
        remoteEnabled = try container.decodeIfPresent(Bool.self, forKey: .remoteEnabled) ?? true
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        lastSeenAt = try container.decodeIfPresent(String.self, forKey: .lastSeenAt)
    }
}

struct RemoteDeviceCodeResponse: Codable, Hashable {
    let deviceCode: String
    let hint: String
}

struct RemoteLanTokenRequest: Codable {
    let ip: String
    let port: Int
    let transientToken: String
    let expiresAt: Int64
}

struct RemoteSignalingPayload: Codable, Hashable {
    let kind: String
    let sdp: String?
    let sdpMid: String?
    let sdpMLineIndex: Int32?
    let candidate: String?
    /// Error/control-frame detail only. Remote chat business data is not carried
    /// in signaling payloads.
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

struct RemoteICEServer: Codable, Hashable {
    let urls: [String]
    let username: String?
    let credential: String?
    let realm: String?
}

struct RemoteICEConfiguration: Codable, Hashable {
    let iceServers: [RemoteICEServer]
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
        lastSeenAt = try container.decodeIfPresent(String.self, forKey: .lastSeenAt)
            ?? container.decodeIfPresent(String.self, forKey: .lastSeenAtSnake)
    }
}

struct RemoteConnectionAttempt: Decodable, Identifiable, Hashable {
    let id: Int
    let connectionId: Int?
    let fromUserId: Int
    let fromDeviceId: Int?
    let toUserId: Int
    let toDeviceId: Int
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
        connectionId = try container.decodeIfPresent(Int.self, forKey: .connectionId)
            ?? container.decodeIfPresent(Int.self, forKey: .connectionIdSnake)
        fromUserId = try container.decodeIfPresent(Int.self, forKey: .fromUserId)
            ?? container.decode(Int.self, forKey: .fromUserIdSnake)
        fromDeviceId = try container.decodeIfPresent(Int.self, forKey: .fromDeviceId)
            ?? container.decodeIfPresent(Int.self, forKey: .fromDeviceIdSnake)
        toUserId = try container.decodeIfPresent(Int.self, forKey: .toUserId)
            ?? container.decode(Int.self, forKey: .toUserIdSnake)
        toDeviceId = try container.decodeIfPresent(Int.self, forKey: .toDeviceId)
            ?? container.decode(Int.self, forKey: .toDeviceIdSnake)
        grantId = try container.decodeIfPresent(Int.self, forKey: .grantId)
            ?? container.decodeIfPresent(Int.self, forKey: .grantIdSnake)
        status = try container.decode(String.self, forKey: .status)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
            ?? container.decodeIfPresent(String.self, forKey: .completedAtSnake)
        transport = try container.decodeIfPresent(String.self, forKey: .transport)
        endpoint = try container.decodeIfPresent(RemoteLanEndpoint.self, forKey: .endpoint)
        transientToken = try container.decodeIfPresent(String.self, forKey: .transientToken)
            ?? container.decodeIfPresent(String.self, forKey: .transientTokenSnake)
    }
}

struct RemoteConnectionDecisionRequest: Codable {
    let reason: String
    let remember: Bool
}

struct RemoteSubscription: Codable, Hashable {
    let planCode: String
    let status: String
    let expiresAt: String?
    let trialSecondsAllowed: Int
    let trialSecondsUsed: Int
    let trialSecondsLeft: Int
    let renewUrl: String?

    var trialMinutesLeft: Int {
        max(0, Int(ceil(Double(trialSecondsLeft) / 60.0)))
    }
}

struct RemoteSubscriptionPlan: Codable, Identifiable, Hashable {
    var id: String { code }
    let code: String
    let name: String
    let description: String
    let durationMonths: Int
    let priceFen: Int64
    let currency: String

    var priceText: String {
        let amount = Double(priceFen) / 100.0
        return String(format: "%.2f 元", amount)
    }
}

struct RemoteSubscriptionOrderRequest: Codable {
    let planCode: String
    let channelCode: String?
    let tradeType: String?
    let returnUrl: String?
}

struct RemoteSubscriptionOrder: Codable, Hashable {
    let outTradeNo: String
    let payOrderNo: String
    let status: String
    let amountFen: Int64
    let currency: String
    let planCode: String
    let planName: String
    let payUrl: String?
}
