import Foundation

struct RemoteAuthClient {
    private let api: RemoteAPIClient
    private let identityStore: DeviceIdentityStore

    init(api: RemoteAPIClient = RemoteAPIClient(), identityStore: DeviceIdentityStore = .shared) {
        self.api = api
        self.identityStore = identityStore
    }

    func requestRegisterCode(email: String) async throws -> RemoteVerificationCodeResponse {
        try await api.post("remote/auth/register-code", body: RemoteVerificationCodeRequest(email: email))
    }

    func register(email: String, password: String, verificationCode: String) async throws -> RemoteAuthSession {
        try await api.post("remote/auth/register", body: RemoteAuthRegisterRequest(email: email, password: password, verificationCode: verificationCode))
    }

    func login(email: String, password: String) async throws -> RemoteAuthSession {
        try await api.post("remote/auth/login", body: RemoteAuthLoginRequest(email: email, password: password))
    }

    func refresh(refreshToken: String) async throws -> RemoteAuthSession {
        try await api.post("remote/auth/refresh", body: RemoteAuthRefreshRequest(refreshToken: refreshToken))
    }

    func requestPasswordResetCode(email: String) async throws -> RemoteVerificationCodeResponse {
        try await api.post("remote/auth/password-reset-code", body: RemoteVerificationCodeRequest(email: email))
    }

    func resetPassword(email: String, password: String, verificationCode: String) async throws {
        try await api.postIgnoringPayload("remote/auth/reset-password", body: RemotePasswordResetRequest(email: email, password: password, verificationCode: verificationCode))
    }

    func changePassword(currentPassword: String, newPassword: String, accessToken: String) async throws {
        try await api.postIgnoringPayload(
            "remote/auth/change-password",
            body: RemoteChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword),
            authorizedToken: accessToken
        )
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

    func registerDevice(request: RemoteDeviceRegisterRequest, accessToken: String) async throws -> RemoteDevice {
        try await api.post("remote/devices/register", body: request, authorizedToken: accessToken)
    }

    func devices(accessToken: String) async throws -> [RemoteDevice] {
        try await api.get("remote/devices", authorizedToken: accessToken)
    }

    func resolveDeviceCode(_ deviceCode: String, accessToken: String) async throws -> RemoteDeviceResolveResponse {
        let identity = try await identityStore.loadOrCreateIdentity()
        guard let fromDeviceId = identity.deviceID else {
            throw LocalDeviceIdentityStoreError.missingProvisionedDeviceID
        }
        return try await api.post(
            "remote/device-codes/resolve",
            body: RemoteDeviceCodeResolveRequest(
                deviceCode: deviceCode,
                fromDeviceId: fromDeviceId,
                fromDeviceUid: identity.deviceUID,
                fromDevicePublicKey: identity.devicePublicKey
            ),
            authorizedToken: accessToken
        )
    }

    func connect(deviceId: Int, accessToken: String) async throws -> RemoteConnectionAttempt {
        let identity = try await identityStore.loadOrCreateIdentity()
        guard let fromDeviceId = identity.deviceID else {
            throw LocalDeviceIdentityStoreError.missingProvisionedDeviceID
        }
        return try await api.post(
            "remote/devices/\(deviceId)/connect",
            body: RemoteConnectRequest(
                fromDeviceId: fromDeviceId,
                fromDeviceUid: identity.deviceUID,
                fromDevicePublicKey: identity.devicePublicKey
            ),
            authorizedToken: accessToken
        )
    }
}
