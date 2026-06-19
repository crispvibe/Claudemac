import Foundation

struct AccountAuthClient {
    private let api: AccountAPIClient

    init(api: AccountAPIClient = AccountAPIClient()) {
        self.api = api
    }

    func requestRegisterCode(email: String) async throws -> RemoteVerificationCodeResponse {
        try await api.post("remote/auth/register-code", body: RemoteVerificationCodeRequest(email: email))
    }

    func register(email: String, verificationCode: String) async throws -> RemoteAuthSession {
        try await api.post("remote/auth/register", body: RemoteAuthRegisterRequest(email: email, verificationCode: verificationCode))
    }

    func requestLoginCode(email: String) async throws -> RemoteVerificationCodeResponse {
        try await api.post("remote/auth/login-code", body: RemoteVerificationCodeRequest(email: email))
    }

    func login(email: String, verificationCode: String) async throws -> RemoteAuthSession {
        try await api.post("remote/auth/login", body: RemoteAuthLoginRequest(email: email, verificationCode: verificationCode))
    }

    func refresh(refreshToken: String) async throws -> RemoteAuthSession {
        try await api.post("remote/auth/refresh", body: RemoteAuthRefreshRequest(refreshToken: refreshToken))
    }

    func logout(accessToken: String) async throws {
        try await api.postIgnoringPayload("remote/auth/logout", body: AccountAPIEmptyPayload(), authorizedToken: accessToken)
    }

    func deleteAccount(confirmAccount: String, confirmDestroy: String, confirmWaiveRights: String, reason: String, accessToken: String) async throws -> RemoteAccountDeletionResponse {
        try await api.post(
            "remote/account/deletion",
            body: RemoteAccountDeletionRequest(
                confirmAccount: confirmAccount,
                confirmDestroy: confirmDestroy,
                confirmWaiveRights: confirmWaiveRights,
                reason: reason
            ),
            authorizedToken: accessToken
        )
    }

    func legalDocument(type: RemoteLegalDocumentType, platform: String = AccountRemoteConfig.platform) async throws -> RemoteLegalDocument {
        let encodedType = type.rawValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? type.rawValue
        let encodedPlatform = platform.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? platform
        return try await api.get("remote/legal-documents?type=\(encodedType)&platform=\(encodedPlatform)")
    }

    func consentLegal(documentId: Int, platform: String = AccountRemoteConfig.platform, deviceId: Int = 0, accessToken: String) async throws {
        try await api.postIgnoringPayload(
            "remote/legal-consents",
            body: RemoteLegalConsentRequest(documentId: documentId, platform: platform, deviceId: deviceId),
            authorizedToken: accessToken
        )
    }

    func subscription(accessToken: String) async throws -> RemoteSubscription {
        try await api.get("remote/subscription", authorizedToken: accessToken)
    }

    func subscriptionPlans(accessToken: String) async throws -> [RemoteSubscriptionPlan] {
        try await api.get("remote/subscription/plans", authorizedToken: accessToken)
    }

    func createSubscriptionOrder(planCode: String, accessToken: String) async throws -> RemoteSubscriptionOrder {
        try await api.post(
            "remote/subscription/orders",
            body: RemoteSubscriptionOrderRequest(planCode: planCode, channelCode: nil, tradeType: "H5", returnUrl: nil),
            authorizedToken: accessToken
        )
    }
}
