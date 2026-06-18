import Foundation

struct RemoteDeviceClient {
    private let api: RemoteAPIClient
    private let identityStore: DeviceIdentityStore

    init(api: RemoteAPIClient = RemoteAPIClient(), identityStore: DeviceIdentityStore = .shared) {
        self.api = api
        self.identityStore = identityStore
    }

    func devices(accessToken: String) async throws -> [RemoteDevice] {
        try await api.get("remote/devices", authorizedToken: accessToken)
    }

    func device(deviceId: Int, accessToken: String) async throws -> RemoteDevice {
        try await api.get("remote/devices/\(deviceId)", authorizedToken: accessToken)
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

    func connection(connectionId: Int, accessToken: String) async throws -> RemoteConnectionAttempt {
        try await api.get("remote/connections/\(connectionId)", authorizedToken: accessToken)
    }

    func reportConnectionMetrics(connectionId: Int, request: RemoteConnectionMetricsRequest, accessToken: String) async throws -> RemoteConnectionAttempt {
        try await api.post("remote/connections/\(connectionId)/metrics", body: request, authorizedToken: accessToken)
    }

    func iceServers(connectionId: Int, accessToken: String) async throws -> RemoteICEConfiguration {
        try await api.get("remote/ice-config?connectionId=\(connectionId)", authorizedToken: accessToken)
    }
}
