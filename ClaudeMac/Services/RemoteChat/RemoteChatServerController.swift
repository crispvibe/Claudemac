import AppKit
import Foundation

struct RemoteChatServerDiagnostics: Equatable {
    var activeWebSocketCount: Int = 0
    var localWebSocketIDs: [String] = []
    var remoteConnectionIDs: [String] = []
    var latestRemoteConnectionID: String?
}

extension Notification.Name {
    static let remoteChatServerDiagnosticsDidChange = Notification.Name("remoteChatServerDiagnosticsDidChange")
    static let remoteChatServerDidStart = Notification.Name("remoteChatServerDidStart")
}

final class RemoteChatAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        RemoteChatServerController.shared.startIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        RemoteChatServerController.shared.stop()
    }
}

final class RemoteChatServerController {
    static let shared = RemoteChatServerController()
    static let defaultPort: UInt16 = 18765

    private(set) var isRunning = false
    private(set) var lastError: String?
    private(set) var diagnostics = RemoteChatServerDiagnostics()

    private var server: RemoteChatServer?
    private let transientTokenLock = NSLock()
    /// Multiple short-lived LAN tokens may be valid at once (cloud publish rotates every ~15s).
    private var transientTokens: [String: Date] = [:]

    deinit {
        server?.stop()
    }

    func startIfNeeded() {
        var settings = ProjectStore.loadSettings()
        guard settings.remoteChatServerEnabled else { return }
        guard server == nil else { return }

        // Generate a token on first launch and persist it back so it survives restarts.
        if settings.remoteChatServerToken.isEmpty {
            settings = ProjectStore.mutateSettings { s in
                if s.remoteChatServerToken.isEmpty { s.remoteChatServerToken = Self.generateToken() }
            }
        }

        // Audit A-P1: stale attachment tmp files were never cleaned up; over
        // time they accumulate and an attacker with the token could fill the
        // disk. Sweep anything older than 24h on startup.
        Self.sweepStaleAttachments()

        let port = UInt16(clamping: settings.remoteChatServerPort)
        let bindLAN = settings.remoteChatServerBindLAN || !settings.remoteChatPublicHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let configuration = RemoteChatServerConfiguration(
            port: port == 0 ? Self.defaultPort : port,
            bindLAN: bindLAN,
            token: settings.remoteChatServerToken
        )
        let server = RemoteChatServer(configuration: configuration)
        server.onDiagnosticsChanged = { [weak self] diagnostics in
            self?.updateDiagnostics(diagnostics)
        }
        updateDiagnostics(server.diagnosticsSnapshot())
        do {
            try server.start()
            self.server = server
            isRunning = true
            lastError = nil
            print("RemoteChatServer listening on \(configuration.bindLAN ? "LAN" : "127.0.0.1"):\(configuration.port)")
            NotificationCenter.default.post(name: .remoteChatServerDidStart, object: self)
        } catch {
            self.server = nil
            isRunning = false
            lastError = error.localizedDescription
            print("RemoteChatServer failed to start: \(error)")
        }
    }

    func restart() {
        stop()
        startIfNeeded()
    }

    func stop() {
        server?.stop()
        server = nil
        isRunning = false
        updateDiagnostics(RemoteChatServerDiagnostics())
    }

    /// Returns the latest local WebSocket diagnostics for account/settings UI.
    func currentDiagnostics() -> RemoteChatServerDiagnostics {
        if let server {
            updateDiagnostics(server.diagnosticsSnapshot())
        }
        return diagnostics
    }

    func handleWebRTCTextFrame(_ text: String, connectionId: Int, reply: @escaping (String) -> Void) {
        server?.handleWebRTCTextFrame(text, connectionId: connectionId, reply: reply)
    }

    func registerWebRTCSender(connectionId: Int, send: @escaping (String) -> Void) {
        server?.registerWebRTCSender(connectionId: connectionId, send: send)
    }

    func pushWebRTCBootstrapSnapshot(connectionId: Int) {
        server?.pushWebRTCBootstrapSnapshot(connectionId: connectionId)
    }

    func unregisterWebRTCConnection(connectionId: Int) {
        server?.unregisterWebRTCConnection(connectionId: connectionId)
    }

    private func updateDiagnostics(_ diagnostics: RemoteChatServerDiagnostics) {
        guard self.diagnostics != diagnostics else { return }
        self.diagnostics = diagnostics
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .remoteChatServerDiagnosticsDidChange, object: self)
        }
    }

    /// Returns the persisted token, generating + saving one if none exists yet.
    static func savedToken() -> String {
        var settings = ProjectStore.loadSettings()
        if settings.remoteChatServerToken.isEmpty {
            settings = ProjectStore.mutateSettings { s in
                if s.remoteChatServerToken.isEmpty { s.remoteChatServerToken = generateToken() }
            }
        }
        return settings.remoteChatServerToken
    }

    static func resetToken() -> String {
        let token = generateToken()
        ProjectStore.mutateSettings { $0.remoteChatServerToken = token }
        shared.restart()
        return token
    }

    static func generateTransientToken() -> String {
        "acm_lan_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    func setTransientToken(_ token: String, expiresAt: Date) {
        transientTokenLock.lock()
        pruneExpiredTransientTokensLocked(now: Date())
        transientTokens[token] = expiresAt
        transientTokenLock.unlock()
    }

    func clearTransientToken() {
        transientTokenLock.lock()
        transientTokens.removeAll()
        transientTokenLock.unlock()
    }

    func acceptsTransientToken(_ token: String) -> Bool {
        transientTokenLock.lock()
        defer { transientTokenLock.unlock() }
        let now = Date()
        pruneExpiredTransientTokensLocked(now: now)
        guard let expiresAt = transientTokens[token] else { return false }
        return expiresAt > now
    }

    private func pruneExpiredTransientTokensLocked(now: Date) {
        transientTokens = transientTokens.filter { $0.value > now }
    }

    private static func generateToken() -> String {
        "acm_local_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// Audit A-P1: best-effort cleanup of stale attachment tmp directories.
    /// Each upload lives in `tmp/AcodeRemoteChatAttachments/<uuid>/<file>`.
    /// We delete any subdirectory whose modification date is older than the
    /// retention window. Called from `startIfNeeded` so it runs once per app
    /// launch — adding a recurring sweeper would be overkill for the volume
    /// we expect.
    private static func sweepStaleAttachments() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcodeRemoteChatAttachments", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for url in entries {
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modDate < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
