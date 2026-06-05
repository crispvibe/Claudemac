import Foundation

struct DeviceRegistrationClient {
    private let api: AccountAPIClient

    init(api: AccountAPIClient = AccountAPIClient()) {
        self.api = api
    }

    func register(request: RemoteDeviceRegisterRequest, accessToken: String) async throws -> RemoteDevice {
        try await api.post("remote/devices/register", body: request, authorizedToken: accessToken)
    }

    func deviceCode(deviceId: Int, accessToken: String) async throws -> RemoteDeviceCodeResponse {
        try await api.get("remote/devices/\(deviceId)/device-code", authorizedToken: accessToken)
    }

    func resetDeviceCode(deviceId: Int, accessToken: String) async throws -> RemoteDeviceCodeResponse {
        try await api.post("remote/devices/\(deviceId)/device-code/reset", body: AccountAPIEmptyPayload(), authorizedToken: accessToken)
    }

    func updateDevice(deviceId: Int, request: RemoteDeviceUpdateRequest, accessToken: String) async throws -> RemoteDevice {
        try await api.patch("remote/devices/\(deviceId)", body: request, authorizedToken: accessToken)
    }

    func publishLanToken(deviceId: Int, request: RemoteLanTokenRequest, accessToken: String) async throws -> RemoteDevice {
        try await api.post("remote/devices/\(deviceId)/lan-token", body: request, authorizedToken: accessToken)
    }

    func decideConnection(connectionId: Int, accepted: Bool, remember: Bool, reason: String, accessToken: String) async throws -> RemoteConnectionAttempt {
        let action = accepted ? "approve" : "reject"
        return try await api.post(
            "remote/connections/\(connectionId)/\(action)",
            body: RemoteConnectionDecisionRequest(reason: reason, remember: remember),
            authorizedToken: accessToken
        )
    }

    func iceServers(connectionId: Int, accessToken: String) async throws -> RemoteICEConfiguration {
        try await api.get("remote/ice-config?connectionId=\(connectionId)", authorizedToken: accessToken)
    }
}
