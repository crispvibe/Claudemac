import Foundation

final class LanTokenPublisher {
    private let client: DeviceRegistrationClient
    private let authClient: AccountAuthClient
    private let tokenStore: AccountTokenStore
    private var publishTask: Task<Void, Never>?
    private var serverStartObserver: NSObjectProtocol?
    var onSessionRefreshed: ((RemoteAuthSession) -> Void)?
    var onPublishStatus: ((String) -> Void)?

    init(
        client: DeviceRegistrationClient = DeviceRegistrationClient(),
        authClient: AccountAuthClient = AccountAuthClient(),
        tokenStore: AccountTokenStore = .shared
    ) {
        self.client = client
        self.authClient = authClient
        self.tokenStore = tokenStore
    }

    deinit {
        if let serverStartObserver {
            NotificationCenter.default.removeObserver(serverStartObserver)
        }
    }

    func start(session: RemoteAuthSession, deviceId: Int) {
        stop()
        serverStartObserver = NotificationCenter.default.addObserver(
            forName: .remoteChatServerDidStart,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.publishNow(session: session, deviceId: deviceId) }
        }
        publishTask = Task { [weak self] in
            await self?.publishWithRetries(session: session, deviceId: deviceId, maxAttempts: 12)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.publishOnce(session: session, deviceId: deviceId)
            }
        }
    }

    func stop() {
        publishTask?.cancel()
        publishTask = nil
        if let serverStartObserver {
            NotificationCenter.default.removeObserver(serverStartObserver)
            self.serverStartObserver = nil
        }
    }

    func publishNow(session: RemoteAuthSession, deviceId: Int) async {
        await publishWithRetries(session: session, deviceId: deviceId, maxAttempts: 4)
    }

    private func publishWithRetries(session: RemoteAuthSession, deviceId: Int, maxAttempts: Int) async {
        for attempt in 1...maxAttempts {
            let published = await publishOnce(session: session, deviceId: deviceId)
            if published { return }
            guard attempt < maxAttempts, !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func resolveSession(fallback: RemoteAuthSession) async -> RemoteAuthSession? {
        do {
            var session = try await tokenStore.load() ?? fallback
            if session.isExpired {
                session = try await authClient.refresh(refreshToken: session.refreshToken)
                try await tokenStore.save(session)
            }
            onSessionRefreshed?(session)
            return session
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            onPublishStatus?("局域网地址发布失败：\(message)")
            print("[LanTokenPublisher] session resolve failed: \(message)")
            return nil
        }
    }

    @discardableResult
    private func publishOnce(session: RemoteAuthSession, deviceId: Int) async -> Bool {
        guard let activeSession = await resolveSession(fallback: session) else { return false }

        let settings = ProjectStore.loadSettings()
        guard settings.remoteChatServerEnabled else {
            onPublishStatus?("局域网地址未发布：设备连接服务已关闭。")
            print("[LanTokenPublisher] skipped: remote chat server disabled")
            return false
        }
        guard RemoteChatServerController.shared.isRunning else {
            onPublishStatus?("局域网地址未发布：本机服务尚未启动。")
            print("[LanTokenPublisher] skipped: local server not running yet")
            return false
        }

        let configuredPort = settings.remoteChatServerPort
        let port = configuredPort > 0 ? configuredPort : Int(RemoteChatServerController.defaultPort)
        guard (1...65535).contains(port) else {
            print("[LanTokenPublisher] skipped: invalid port \(port)")
            return false
        }

        let publicHost = settings.remoteChatPublicHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lanHost = settings.remoteChatServerBindLAN ? LanNetworkAddress.primaryIPv4() : nil
        let publishHost: String?
        let publishPort: Int
        if !publicHost.isEmpty {
            publishHost = publicHost
            publishPort = settings.remoteChatPublicPort > 0 ? settings.remoteChatPublicPort : port
        } else if let lanHost {
            publishHost = lanHost
            publishPort = port
        } else {
            publishHost = nil
            publishPort = port
        }

        guard let publishHost, !publishHost.isEmpty else {
            onPublishStatus?("局域网地址未发布：未检测到本机局域网 IP。")
            print("[LanTokenPublisher] skipped: no LAN/public host available")
            return false
        }

        let token = RemoteChatServerController.generateTransientToken()
        let expiresAt = Date().addingTimeInterval(120)
        RemoteChatServerController.shared.setTransientToken(token, expiresAt: expiresAt)

        let request = RemoteLanTokenRequest(
            ip: publishHost,
            port: publishPort,
            transientToken: token,
            expiresAt: Int64(expiresAt.timeIntervalSince1970 * 1_000)
        )

        do {
            _ = try await client.publishLanToken(
                deviceId: deviceId,
                request: request,
                accessToken: activeSession.accessToken
            )
            let status = publicHost.isEmpty
                ? "局域网地址已发布：\(publishHost):\(publishPort)"
                : "公网端口地址已发布：\(publishHost):\(publishPort)"
            onPublishStatus?(status)
            print("[LanTokenPublisher] published endpoint=\(publishHost):\(publishPort)")
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            onPublishStatus?("云端地址登记失败：\(message)（同 WiFi 连接时将通过信令协商局域网地址。）")
            print("[LanTokenPublisher] publish failed: \(message)")
            return false
        }
    }
}
