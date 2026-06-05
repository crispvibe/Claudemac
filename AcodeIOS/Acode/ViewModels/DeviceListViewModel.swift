import Foundation

@MainActor
final class DeviceListViewModel: ObservableObject {
    @Published private(set) var devices: [RemoteDevice] = []
    @Published private(set) var isLoading = false
    @Published var message: String?

    private let client: RemoteDeviceClient
    private let signalingClient: SignalingClient

    init(client: RemoteDeviceClient = RemoteDeviceClient(), signalingClient: SignalingClient? = nil) {
        self.client = client
        self.signalingClient = signalingClient ?? .shared
        self.signalingClient.onPresenceUpdate = { [weak self] deviceId, online in
            self?.applyPresence(deviceId: deviceId, online: online)
        }
    }

    func startPresenceUpdates(session: RemoteAuthSession?) {
        Task { await load(session: session, showsLoading: devices.isEmpty) }
    }

    func stopPresenceUpdates() {
        signalingClient.onPresenceUpdate = nil
    }

    func load(session: RemoteAuthSession?, showsLoading: Bool = true) async {
        guard let session, !isLoading else {
#if DEBUG
            print("[AnnaCodeDeviceList] load skipped hasSession=\(session != nil) isLoading=\(isLoading)")
#endif
            return
        }
        if showsLoading { isLoading = true }
        message = nil
        defer { if showsLoading { isLoading = false } }

        do {
#if DEBUG
            print("[AnnaCodeDeviceList] devices load start")
#endif
            devices = try await client.devices(accessToken: session.accessToken)
                .filter { $0.deviceType == "desktop" || $0.platform == "macos" }
#if DEBUG
            let summary = devices.map { "\($0.id):\($0.deviceName):online=\($0.online):status=\($0.status):remote=\($0.remoteEnabled)" }.joined(separator: ";")
            print("[AnnaCodeDeviceList] devices load ok count=\(devices.count) \(summary)")
#endif
        } catch {
            message = authErrorMessage(error, fallback: "设备列表加载失败。")
#if DEBUG
            print("[AnnaCodeDeviceList] devices load failed: \(error.localizedDescription)")
#endif
        }
    }

    private func applyPresence(deviceId: Int, online: Bool) {
        devices = devices.map { device in
            device.id == deviceId ? device.withOnline(online) : device
        }
    }

    private func authErrorMessage(_ error: Error, fallback: String) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return fallback }
        return RemoteUserFacingText.apiError(message, fallback: fallback)
    }
}
