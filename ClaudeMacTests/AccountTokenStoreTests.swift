import CryptoKit
import Darwin
import XCTest
import ChatCore
@testable import AnnaCode

final class AccountTokenStoreTests: XCTestCase {
    func testSessionCodecRoundTripsAndExpiry() throws {
        let future = Int64(Date().addingTimeInterval(60).timeIntervalSince1970 * 1_000)
        let session = RemoteAuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: future,
            user: RemoteAuthUser(id: 7, email: "user@example.com", status: "active")
        )

        let data = try AccountTokenStoreCodec.encode(session)
        let decoded = try AccountTokenStoreCodec.decode(data)

        XCTAssertEqual(decoded, session)
        XCTAssertFalse(decoded.isExpired)

        let expired = RemoteAuthSession(
            accessToken: "expired-access",
            refreshToken: "expired-refresh",
            expiresAt: Int64(Date().addingTimeInterval(-60).timeIntervalSince1970 * 1_000),
            user: session.user
        )
        XCTAssertTrue(expired.isExpired)
    }

    func testRemoteCredentialBlobCodecRoundTrips() throws {
        let key = Curve25519.Signing.PrivateKey()
        let blob = RemoteCredentialBlob(
            schemaVersion: 1,
            session: makeSession(),
            deviceIdentity: makeIdentity(publicKey: key.publicKey.rawRepresentation.base64EncodedString()),
            deviceSigningPrivateKey: key.rawRepresentation,
            deviceCode: "123456"
        )

        let decoded = try RemoteCredentialBlobCodec.decode(RemoteCredentialBlobCodec.encode(blob))

        XCTAssertEqual(decoded, blob)
    }

    func testFileCredentialStoragePersistsBlobWithoutKeychain() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteCredentialFileStorageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try RemoteCredentialFileStorage(directoryURL: directory)
        let credentialStore = RemoteCredentialStore(storage: storage)
        let blob = RemoteCredentialBlob(
            schemaVersion: 1,
            session: makeSession(),
            deviceIdentity: makeIdentity(publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()),
            deviceSigningPrivateKey: Data("private-key".utf8),
            deviceCode: "123456"
        )

        try await credentialStore.saveBlob(blob)
        let loaded = try await credentialStore.loadBlob()

        XCTAssertEqual(loaded, blob)
        let credentialURL = directory.appendingPathComponent("remote-credentials.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: credentialURL.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: credentialURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(permissions & 0o777, 0o600)
    }

    func testCredentialStoreMigratesFullLegacyData() async throws {
        let storage = RemoteCredentialMemoryStorage()
        let session = makeSession()
        let privateKey = Curve25519.Signing.PrivateKey()
        let identity = makeIdentity(publicKey: privateKey.publicKey.rawRepresentation.base64EncodedString())
        storage.seed(
            try AccountTokenStoreCodec.encode(session),
            service: RemoteCredentialStore.legacyAccountService,
            account: RemoteCredentialStore.legacySessionAccount
        )
        storage.seed(
            try JSONEncoder().encode(identity),
            service: RemoteCredentialStore.legacyDeviceService,
            account: RemoteCredentialStore.legacyIdentityAccount
        )
        storage.seed(
            privateKey.rawRepresentation,
            service: RemoteCredentialStore.legacyDeviceService,
            account: RemoteCredentialStore.legacyPrivateKeyAccount
        )
        storage.seed(
            Data("654321".utf8),
            service: RemoteCredentialStore.legacyDeviceService,
            account: RemoteCredentialStore.legacyDeviceCodeAccount
        )

        let store = RemoteCredentialStore(storage: storage)
        let migrated = try await store.loadBlob()
        let savedData = try XCTUnwrap(storage.data(service: RemoteCredentialStore.blobService, account: RemoteCredentialStore.blobAccount))
        let savedBlob = try RemoteCredentialBlobCodec.decode(savedData)

        XCTAssertEqual(migrated.session, session)
        XCTAssertEqual(migrated.deviceIdentity, identity)
        XCTAssertEqual(migrated.deviceSigningPrivateKey, privateKey.rawRepresentation)
        XCTAssertEqual(migrated.deviceCode, "654321")
        XCTAssertEqual(savedBlob, migrated)
    }

    func testAccountClearOnlyClearsSession() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let identity = makeIdentity(publicKey: privateKey.publicKey.rawRepresentation.base64EncodedString())
        let credentialStore = RemoteCredentialStore(storage: RemoteCredentialMemoryStorage())
        try await credentialStore.saveBlob(RemoteCredentialBlob(
            schemaVersion: 1,
            session: makeSession(),
            deviceIdentity: identity,
            deviceSigningPrivateKey: privateKey.rawRepresentation,
            deviceCode: "123456"
        ))
        let tokenStore = AccountTokenStore(credentialStore: credentialStore)

        try await tokenStore.clear()
        let blob = try await credentialStore.loadBlob()

        XCTAssertNil(blob.session)
        XCTAssertEqual(blob.deviceIdentity, identity)
        XCTAssertEqual(blob.deviceSigningPrivateKey, privateKey.rawRepresentation)
        XCTAssertEqual(blob.deviceCode, "123456")
    }

    func testClearProvisionedDevicePreservesPrivateKeyAndPublicKey() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let identity = makeIdentity(publicKey: privateKey.publicKey.rawRepresentation.base64EncodedString())
        let credentialStore = RemoteCredentialStore(storage: RemoteCredentialMemoryStorage())
        try await credentialStore.saveBlob(RemoteCredentialBlob(
            schemaVersion: 1,
            session: makeSession(),
            deviceIdentity: identity,
            deviceSigningPrivateKey: privateKey.rawRepresentation,
            deviceCode: "123456"
        ))
        let identityStore = DeviceIdentityStore(credentialStore: credentialStore)

        try await identityStore.clearProvisionedDevice()
        let blob = try await credentialStore.loadBlob()
        let clearedIdentity = try XCTUnwrap(blob.deviceIdentity)

        XCTAssertNotEqual(clearedIdentity.deviceUID, identity.deviceUID)
        XCTAssertNil(clearedIdentity.deviceID)
        XCTAssertEqual(clearedIdentity.deviceName, identity.deviceName)
        XCTAssertEqual(clearedIdentity.devicePublicKey, identity.devicePublicKey)
        XCTAssertEqual(blob.deviceSigningPrivateKey, privateKey.rawRepresentation)
        XCTAssertNil(blob.deviceCode)
    }

    func testLoadOrCreateIdentityReusesMigratedPrivateKey() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let credentialStore = RemoteCredentialStore(storage: RemoteCredentialMemoryStorage())
        try await credentialStore.saveBlob(RemoteCredentialBlob(
            schemaVersion: 1,
            session: nil,
            deviceIdentity: nil,
            deviceSigningPrivateKey: privateKey.rawRepresentation,
            deviceCode: nil
        ))
        let identityStore = DeviceIdentityStore(credentialStore: credentialStore)

        let identity = try await identityStore.loadOrCreateIdentity()
        let blob = try await credentialStore.loadBlob()

        XCTAssertEqual(identity.devicePublicKey, privateKey.publicKey.rawRepresentation.base64EncodedString())
        XCTAssertEqual(blob.deviceSigningPrivateKey, privateKey.rawRepresentation)
        XCTAssertEqual(blob.deviceIdentity, identity)
    }

    func testCorruptedNewBlobDoesNotFallBackToLegacyData() async throws {
        let storage = RemoteCredentialMemoryStorage()
        storage.seed(
            Data("not-json".utf8),
            service: RemoteCredentialStore.blobService,
            account: RemoteCredentialStore.blobAccount
        )
        storage.seed(
            try AccountTokenStoreCodec.encode(makeSession()),
            service: RemoteCredentialStore.legacyAccountService,
            account: RemoteCredentialStore.legacySessionAccount
        )
        let store = RemoteCredentialStore(storage: storage)

        do {
            _ = try await store.loadBlob()
            XCTFail("Expected corrupted blob to throw")
        } catch let error as RemoteCredentialStoreError {
            guard case .decoding = error else {
                return XCTFail("Expected decoding error, got \(error)")
            }
        } catch {
            XCTFail("Expected credential store error, got \(error)")
        }
    }

    func testRemoteAuthRequestsUseEmailOnlyPayloads() throws {
        let encoder = JSONEncoder()

        let login = try jsonObject(from: encoder.encode(RemoteAuthLoginRequest(email: "User@Example.COM", password: "pw")))
        XCTAssertEqual(login["email"] as? String, "user@example.com")
        XCTAssertEqual(login["password"] as? String, "pw")
        XCTAssertNil(login["phone"])

        let register = try jsonObject(from: encoder.encode(RemoteAuthRegisterRequest(email: "New@Example.COM", password: "pw", verificationCode: "654321")))
        XCTAssertEqual(register["email"] as? String, "new@example.com")
        XCTAssertEqual(register["verificationCode"] as? String, "654321")
        XCTAssertNil(register["phone"])

        let reset = try jsonObject(from: encoder.encode(RemotePasswordResetRequest(email: "Reset@Example.COM", password: "pw", verificationCode: "123456")))
        XCTAssertEqual(reset["email"] as? String, "reset@example.com")
        XCTAssertEqual(reset["verificationCode"] as? String, "123456")
        XCTAssertNil(reset["phone"])
    }

    func testLoginErrorDoesNotShowExpiredSessionMessage() {
        XCTAssertEqual(
            AccountRemoteUserFacingText.loginError("unauthorized", fallback: "邮箱或密码错误。"),
            "邮箱或密码错误。"
        )
        XCTAssertEqual(
            AccountRemoteUserFacingText.loginError("token is expired", fallback: "邮箱或密码错误。"),
            "邮箱或密码错误。"
        )
        XCTAssertEqual(
            AccountRemoteUserFacingText.loginError("邮箱或密码错误", fallback: "邮箱或密码错误。"),
            "邮箱或密码错误"
        )
    }

    private func makeSession() -> RemoteAuthSession {
        RemoteAuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Int64(Date().addingTimeInterval(60).timeIntervalSince1970 * 1_000),
            user: RemoteAuthUser(id: 7, email: "user@example.com", status: "active")
        )
    }

    private func makeIdentity(publicKey: String) -> DeviceIdentity {
        DeviceIdentity(
            deviceUID: "device-uid",
            deviceID: 42,
            deviceName: "Mac",
            devicePublicKey: publicKey
        )
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

final class RemoteConfigAPITests: XCTestCase {
    func testConfigProfilesDTOOmitsClaudeRelayAuthTokenByDefault() throws {
        let profile = ClaudeRelayProfile(
            id: UUID(),
            name: "Relay",
            baseURL: "https://api.example.com",
            authToken: "secret-token",
            model: "claude-sonnet",
            haikuModel: "",
            sonnetModel: "",
            opusModel: "",
            httpProxy: "",
            httpsProxy: "",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let dto = RemoteConfigProfilesDTO(collection: ConfigProfileCollection(
            activeClaudeRelayProfileID: profile.id,
            activeCodexProfileID: nil,
            claudeRelayProfiles: [profile],
            codexProfiles: []
        ))

        XCTAssertEqual(dto.claudeRelayProfiles.first?.authToken, "")
        XCTAssertEqual(dto.claudeRelayProfiles.first?.authTokenSet, true)
    }

    func testClaudeModelFetchRejectsLocalBaseURLBeforeNetwork() throws {
        let router = RemoteChatRouter(
            configuration: RemoteChatServerConfiguration(port: 42111, bindLAN: false, token: "token"),
            dataProvider: EmptyRemoteChatDataProvider()
        )
        let body = try JSONEncoder().encode(RemoteClaudeModelFetchRequestDTO(baseURL: "http://127.0.0.1:12345", authToken: "secret"))
        let request = RemoteChatHTTPRequest(
            method: "POST",
            path: "/config/claude-models",
            queryItems: [:],
            headers: ["authorization": "Bearer token"],
            body: body
        )

        let response = router.route(request)

        XCTAssertEqual(response.statusCode, 400)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        XCTAssertEqual(payload["error"] as? String, "invalid_base_url")
    }
}

private struct EmptyRemoteChatDataProvider: RemoteChatDataProviding {
    func loadProjects() -> [ProjectItem] { [] }
    func loadSessions() -> [ChatSessionRecord] { [] }
    func loadSession(id: UUID) -> ChatSessionRecord? { nil }
    func loadMessages(sessionID: UUID) -> [ChatMessage] { [] }
    func loadMessagePage(sessionID: UUID, beforeIndex: Int?, limit: Int) -> ChatMessagePage {
        ChatMessagePage(messages: [], nextBeforeIndex: nil, hasMore: false, totalCount: 0)
    }
}

private final class RemoteCredentialMemoryStorage: RemoteCredentialKeychainStorage, @unchecked Sendable {
    private struct Key: Hashable {
        let service: String
        let account: String
    }

    private let lock = NSLock()
    private var values: [Key: Data] = [:]

    func seed(_ data: Data, service: String, account: String) {
        lock.withLock {
            values[Key(service: service, account: account)] = data
        }
    }

    func data(service: String, account: String) -> Data? {
        lock.withLock {
            values[Key(service: service, account: account)]
        }
    }

    func loadData(service: String, account: String) throws -> Data? {
        data(service: service, account: account)
    }

    func saveData(_ data: Data, service: String, account: String) throws {
        seed(data, service: service, account: account)
    }

    func deleteData(service: String, account: String) throws {
        lock.withLock {
            values.removeValue(forKey: Key(service: service, account: account))
        }
    }
}

final class RemoteWebRTCBridgePolicyTests: XCTestCase {
    func testCandidateAllowlistAcceptsDirectAndRelayCandidates() {
        XCTAssertTrue(RemoteWebRTCBridge.isAllowedCandidate("candidate:1 1 udp 2122260223 192.168.1.8 62000 typ host generation 0"))
        XCTAssertTrue(RemoteWebRTCBridge.isAllowedCandidate("candidate:2 1 udp 1686052607 203.0.113.9 62001 typ srflx raddr 192.168.1.8 rport 62000 generation 0"))
        XCTAssertTrue(RemoteWebRTCBridge.isAllowedCandidate("candidate:3 1 udp 41885439 198.51.100.10 3478 typ relay raddr 0.0.0.0 rport 0 generation 0"))
        XCTAssertTrue(RemoteWebRTCBridge.isAllowedCandidate("candidate:7 1 udp 2122260223 240e:54d:306:bd1e::1 62000 typ host generation 0"))

        XCTAssertFalse(RemoteWebRTCBridge.isAllowedCandidate("candidate:4 1 udp 1853824767 192.0.2.55 62002 typ prflx generation 0"))
        XCTAssertFalse(RemoteWebRTCBridge.isAllowedCandidate("candidate:5 1 udp 2122260223 192.168.1.8 62000 generation 0"))
        XCTAssertFalse(RemoteWebRTCBridge.isAllowedCandidate("candidate:6 1 udp 2122260223 192.168.1.8 62000 typ unknown generation 0"))
        XCTAssertFalse(RemoteWebRTCBridge.isAllowedCandidate("candidate:8 1 udp 2122260223 fd74:6572:6d6e:7573::1 62000 typ host generation 0"))
    }

    func testSDPScrubKeepsRelayAndDropsUnknownCandidateLines() {
        let sdp = [
            "v=0",
            "o=- 46117317 2 IN IP4 127.0.0.1",
            "a=candidate:1 1 udp 2122260223 192.168.1.8 62000 typ host generation 0",
            "a=candidate:2 1 udp 1686052607 203.0.113.9 62001 typ srflx raddr 192.168.1.8 rport 62000 generation 0",
            "a=candidate:3 1 udp 41885439 198.51.100.10 3478 typ relay raddr 0.0.0.0 rport 0 generation 0",
            "a=candidate:4 1 udp 2122260223 192.168.1.9 62003 generation 0",
            "a=end-of-candidates"
        ].joined(separator: "\r\n") + "\r\n"

        let scrubbed = RemoteWebRTCBridge.scrubDisallowedCandidateLines(from: sdp)

        XCTAssertTrue(scrubbed.contains("typ host"))
        XCTAssertTrue(scrubbed.contains("typ srflx"))
        XCTAssertTrue(scrubbed.contains("typ relay"))
        XCTAssertTrue(scrubbed.contains("a=end-of-candidates"))
        XCTAssertFalse(scrubbed.contains("192.168.1.9 62003 generation 0"))
        XCTAssertTrue(scrubbed.hasSuffix("\r\n"))
    }
}

final class ChatComposerModelSelectionTests: XCTestCase {
    @MainActor
    func testSwitchingCLIAlsoNormalizesComposerModel() {
        let state = ChatPanelState()
        state.loadDraftDefaults(
            cli: .claude,
            modelID: ChatModelCatalog.defaultClaudeModelID,
            permissionMode: .autoEdit,
            reasoningEffort: .high
        )

        state.setCLI(.codex)

        XCTAssertEqual(state.composerCLI, .codex)
        XCTAssertEqual(state.composerModelID, ChatModelCatalog.defaultCodexModelID)
        XCTAssertEqual(state.composerContextModelID, ChatModelCatalog.defaultCodexModelID)
    }

    @MainActor
    func testSelectingCodexModelKeepsRunAndContextModelPaired() {
        let state = ChatPanelState()
        state.loadDraftDefaults(
            cli: .claude,
            modelID: ChatModelCatalog.defaultClaudeModelID,
            permissionMode: .autoEdit,
            reasoningEffort: .high
        )

        state.setCLI(.codex)
        state.setModel("gpt-5.5")

        XCTAssertEqual(state.composerCLI, .codex)
        XCTAssertEqual(state.composerModelID, "gpt-5.5")
        XCTAssertEqual(state.composerContextModelID, "gpt-5.5")
        XCTAssertEqual(
            ChatModelCatalog.compatibleModelID(state.composerModelID, cli: state.composerCLI),
            state.composerModelID
        )
    }

    func testContextWindowCatalogUsesModelSpecificValues() {
        XCTAssertEqual(ChatModelCatalog.contextWindow(for: "gpt-5.5", cli: .codex), 275_000)
        XCTAssertEqual(ChatModelCatalog.contextWindow(for: "gpt5.5", cli: .codex), 275_000)
        XCTAssertEqual(ChatModelCatalog.contextWindow(for: "claude-opus-4-7", cli: .claude), 1_000_000)
        XCTAssertEqual(ChatModelCatalog.contextWindow(for: "gpt-5.3-codex", cli: .codex), 200_000)
        XCTAssertEqual(ChatModelCatalog.contextWindow(for: "relay-custom", cli: .codex, metadataWindow: 512_000), 512_000)
    }

    @MainActor
    func testSyncContextWindowUsesSelectedModelLimit() {
        let state = ChatPanelState()

        state.syncContextWindow(modelID: "gpt-5.5", cli: .codex)
        XCTAssertEqual(state.tokensTotal, 275_000)

        state.syncContextWindow(modelID: "claude-opus-4-7", cli: .claude)
        XCTAssertEqual(state.tokensTotal, 1_000_000)
    }
}

final class RemoteRecoveryRouterTests: XCTestCase {
    func testWebSocketFrameLimitMatchesRecoveryUploadEnvelope() throws {
        var acceptedFrame = RemoteChatWebSocket.encodeText(String(repeating: "a", count: 1024 * 1024 + 1))
        let frames = try RemoteChatWebSocket.decodeFrames(from: &acceptedFrame)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.payload.count, 1024 * 1024 + 1)
    }

    func testWebSocketRejectsOversizedFrameBeforeBufferingPayload() throws {
        var oversizedHeader = Data([0x81, 127])
        let length = UInt64(RemoteRecoveryLimits.maximumTextFrameUTF8Bytes + 1)
        for shift in stride(from: 56, through: 0, by: -8) {
            oversizedHeader.append(UInt8((length >> UInt64(shift)) & 0xFF))
        }

        XCTAssertThrowsError(try RemoteChatWebSocket.decodeFrames(from: &oversizedHeader)) { error in
            XCTAssertTrue(error is RemoteChatWebSocketError)
        }
    }

    func testRecoverySessionsFilterByProjectAndSortByUpdatedAt() throws {
        let projectA = makeProject(name: "A", path: "/tmp/project-a")
        let projectB = makeProject(name: "B", path: "/tmp/project-b")
        let older = makeSession(project: projectA, title: "older", updatedAt: Date(timeIntervalSince1970: 100))
        let newer = makeSession(project: projectA, title: "newer", updatedAt: Date(timeIntervalSince1970: 200))
        let other = makeSession(project: projectB, title: "other", updatedAt: Date(timeIntervalSince1970: 300))
        let router = makeRouter(projects: [projectA, projectB], sessions: [older, newer, other])

        let response = router.recoveryResponse(for: RemoteRecoveryRequest(op: .sessions, projectId: projectA.id))

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.sessions?.map(\.title), ["newer", "older"])
        XCTAssertEqual(response.sessions?.map(\.projectId), [projectA.id, projectA.id])
    }

    func testRecoveryMessagesReturnsRequestedPageAndMissingSessionError() throws {
        let project = makeProject(name: "A", path: "/tmp/project-a")
        let session = makeSession(project: project, title: "chat")
        let messages = [
            makeMessage(sessionId: session.id, text: "one"),
            makeMessage(sessionId: session.id, text: "two")
        ]
        let router = makeRouter(projects: [project], sessions: [session], messages: [session.id: messages])

        let ok = router.recoveryResponse(for: RemoteRecoveryRequest(op: .messages, sessionId: session.id, limit: 1, before: 1, page: true))
        let missing = router.recoveryResponse(for: RemoteRecoveryRequest(op: .messages, sessionId: UUID(), limit: 1, page: true))

        XCTAssertEqual(ok.status, .ok)
        XCTAssertEqual(ok.messagePage?.messages.map(\.text), ["one"])
        XCTAssertEqual(ok.messagePage?.nextBeforeIndex, nil)
        XCTAssertEqual(ok.messagePage?.hasMore, false)
        XCTAssertEqual(ok.messagePage?.totalCount, 2)
        XCTAssertEqual(missing.status, .error)
        XCTAssertEqual(missing.message, "没有找到这个对话，请刷新后重试。")
    }

    func testRecoveryProjectFilesReadsDirectoryThroughSameRouterPath() throws {
        let root = try makeTemporaryProjectDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "hello".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources", isDirectory: true), withIntermediateDirectories: true)
        try "swift".write(to: root.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        let project = try makeProject(name: "Temp", url: root)
        let router = makeRouter(projects: [project], sessions: [])

        let rootResponse = router.recoveryResponse(for: RemoteRecoveryRequest(op: .projectFiles, projectId: project.id, path: ""))
        let nestedResponse = router.recoveryResponse(for: RemoteRecoveryRequest(op: .projectFiles, projectId: project.id, path: "Sources"))

        XCTAssertEqual(rootResponse.status, .ok)
        XCTAssertEqual(rootResponse.files?.projectId, project.id)
        XCTAssertEqual(rootResponse.files?.entries.map(\.name), ["Sources", "README.md"])
        XCTAssertEqual(nestedResponse.status, .ok)
        XCTAssertEqual(nestedResponse.files?.path, "Sources")
        XCTAssertEqual(nestedResponse.files?.parentPath, "")
        XCTAssertEqual(nestedResponse.files?.entries.map(\.relativePath), ["Sources/App.swift"])
    }

    func testRecoveryUploadAttachmentStoresFileAndRejectsDisallowedType() throws {
        let router = makeRouter(projects: [], sessions: [])

        let ok = router.recoveryResponse(for: RemoteRecoveryRequest(
            op: .uploadAttachment,
            filename: "../note.txt",
            contentBase64: Data("payload".utf8).base64EncodedString()
        ))
        let blocked = router.recoveryResponse(for: RemoteRecoveryRequest(
            op: .uploadAttachment,
            filename: "tool.app",
            contentBase64: Data("payload".utf8).base64EncodedString()
        ))

        XCTAssertEqual(ok.status, .ok)
        let upload = try XCTUnwrap(ok.attachmentUpload)
        XCTAssertEqual(upload.filename, "note.txt")
        XCTAssertEqual(try String(contentsOfFile: upload.path), "payload")
        XCTAssertFalse(upload.path.contains(".."))
        XCTAssertEqual(blocked.status, .error)
        XCTAssertEqual(blocked.message, "暂不支持这种附件类型。")
    }

    func testRecoveryUploadAttachmentRejectsInvalidOversizedAndLongNamesBeforeWriting() throws {
        let router = makeRouter(projects: [], sessions: [])
        let oversizedBase64 = String(repeating: "A", count: RemoteRecoveryLimits.maximumAttachmentContentBase64Length + 4)

        let invalid = router.recoveryResponse(for: RemoteRecoveryRequest(
            op: .uploadAttachment,
            filename: "note.txt",
            contentBase64: "not-base64%"
        ))
        let oversized = router.recoveryResponse(for: RemoteRecoveryRequest(
            op: .uploadAttachment,
            filename: "large.txt",
            contentBase64: oversizedBase64
        ))
        let tooLongName = router.recoveryResponse(for: RemoteRecoveryRequest(
            op: .uploadAttachment,
            filename: String(repeating: "a", count: 181) + ".txt",
            contentBase64: Data("payload".utf8).base64EncodedString()
        ))

        XCTAssertEqual(invalid.status, .error)
        XCTAssertEqual(invalid.message, "文件内容格式不正确，请重新上传。")
        XCTAssertEqual(oversized.status, .error)
        XCTAssertEqual(oversized.message, "附件超过大小限制，请压缩后再上传。")
        XCTAssertEqual(tooLongName.status, .error)
        XCTAssertEqual(tooLongName.message, "文件名过长，请重命名后再上传。")
    }

    func testHTTPAttachmentUploadAndRecoveryUploadUseSameValidation() throws {
        let router = makeRouter(projects: [], sessions: [])
        let body = try RemoteChatHTTPCodec.jsonEncoder.encode(RemoteAttachmentUploadRequestDTO(
            filename: "image.png",
            contentBase64: Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()
        ))
        let response = router.route(RemoteChatHTTPRequest(
            method: "POST",
            path: "/attachments",
            queryItems: [:],
            headers: ["authorization": "Bearer test-token"],
            body: body
        ))

        XCTAssertEqual(response.statusCode, 201)
        let upload = try RemoteChatHTTPCodec.jsonDecoder.decode(RemoteAttachmentUploadResponseDTO.self, from: response.body)
        XCTAssertEqual(upload.filename, "image.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: upload.path))
    }

    private func makeRouter(
        projects: [ProjectItem],
        sessions: [ChatSessionRecord],
        messages: [UUID: [ChatMessage]] = [:]
    ) -> RemoteChatRouter {
        RemoteChatRouter(
            configuration: RemoteChatServerConfiguration(port: 31337, bindLAN: false, token: "test-token"),
            dataProvider: RemoteRecoveryTestDataProvider(projects: projects, sessions: sessions, messages: messages)
        )
    }

    private func makeProject(name: String, path: String) -> ProjectItem {
        ProjectItem(
            id: UUID(),
            name: name,
            path: path,
            bookmarkData: Data(),
            defaultCLI: .claude,
            defaultTerminal: .terminal,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            lastOpenedAt: nil
        )
    }

    private func makeProject(name: String, url: URL) throws -> ProjectItem {
        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        var project = makeProject(name: name, path: url.path)
        project.bookmarkData = bookmark
        return project
    }

    private func makeSession(project: ProjectItem, title: String, updatedAt: Date = Date(timeIntervalSince1970: 100)) -> ChatSessionRecord {
        ChatSessionRecord(
            cli: .claude,
            projectName: project.name,
            projectPath: project.path,
            title: title,
            modelID: "claude-sonnet",
            permissionMode: .autoEdit,
            reasoningEffort: .high,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: updatedAt
        )
    }

    private func makeMessage(sessionId: UUID, text: String) -> ChatMessage {
        ChatMessage(sessionID: sessionId, kind: .assistant, title: "Assistant", text: text, status: "completed")
    }

    private func makeTemporaryProjectDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteRecoveryRouterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

final class ChatCLIEnvironmentTests: XCTestCase {
    func testLegacyAnthropicAuthTokenBecomesAPIKeyForClaudeProcess() {
        let environment = ChatCLIEnvironment.resolvedPersistedClaudeEnvironment(from: [
            "ANTHROPIC_BASE_URL": " https://relay.example.com ",
            "ANTHROPIC_AUTH_TOKEN": " legacy-secret ",
            "ANTHROPIC_MODEL": " claude-sonnet ",
            "UNRELATED_SECRET": "do-not-forward"
        ])

        XCTAssertEqual(environment["ANTHROPIC_API_KEY"], "legacy-secret")
        XCTAssertNil(environment["ANTHROPIC_AUTH_TOKEN"])
        XCTAssertEqual(environment["ANTHROPIC_BASE_URL"], "https://relay.example.com")
        XCTAssertEqual(environment["ANTHROPIC_MODEL"], "claude-sonnet")
        XCTAssertNil(environment["UNRELATED_SECRET"])
    }

    func testAnthropicAPIKeyTakesPrecedenceOverLegacyToken() {
        let environment = ChatCLIEnvironment.resolvedPersistedClaudeEnvironment(from: [
            "ANTHROPIC_API_KEY": "api-key-secret",
            "ANTHROPIC_AUTH_TOKEN": "legacy-secret"
        ])

        XCTAssertEqual(environment["ANTHROPIC_API_KEY"], "api-key-secret")
        XCTAssertNil(environment["ANTHROPIC_AUTH_TOKEN"])
    }
}

final class ClaudeCodeProcessBackendInteractionTests: XCTestCase {
    func testCancellingStreamTerminatesProcess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeBackendCancellation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pidURL = directory.appendingPathComponent("backend.pid")
        let scriptURL = directory.appendingPathComponent("fake-claude.sh")
        let script = """
        #!/bin/sh
        echo $$ > "\(pidURL.path)"
        printf '{"type":"system","subtype":"init","session_id":"fake-session","cwd":"\(directory.path)","tools":[],"model":"fake"}\\n'
        while true; do
          sleep 1
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let backend = ClaudeCodeProcessBackend()
        let options = ChatRunOptions(
            cli: .claude,
            executablePath: scriptURL.path,
            projectPath: directory.path,
            modelID: ChatModelCatalog.defaultClaudeModelID,
            permissionMode: .autoEdit,
            reasoningEffort: .high,
            sessionMode: .newSession,
            resumeSessionID: nil,
            supportsStreamJSONInput: true
        )
        var stream: AsyncThrowingStream<ChatBackendEvent, Error>? = backend.start(prompt: "hello", options: options, session: nil, attachments: [])
        let consumer = Task {
            guard let stream else { return }
            for try await event in stream {
                if case .backendActivity = event,
                   FileManager.default.fileExists(atPath: pidURL.path) {
                    return
                }
            }
        }
        let pid = try await waitForPID(at: pidURL)
        XCTAssertTrue(Self.isProcessAlive(pid))
        consumer.cancel()
        stream = nil
        _ = await consumer.result

        let didExit = await waitUntilProcessExits(pid, timeout: 4.0)
        XCTAssertTrue(didExit)
    }

    func testToolUseResultDoesNotCloseStreamJSONStdin() {
        let resultLine = #"{"type":"result","subtype":"success","stop_reason":"tool_use"}"#
        let successLine = #"{"type":"result","subtype":"success","stop_reason":"end_turn"}"#

        XCTAssertFalse(ClaudeCodeProcessBackend.debugShouldCloseStdinAfterLine(resultLine))
        XCTAssertTrue(ClaudeCodeProcessBackend.debugShouldCloseStdinAfterLine(successLine))
    }

    func testSendUserMessageToolUseBecomesInteractiveRequest() throws {
        let request = try XCTUnwrap(ClaudeCodeProcessBackend.debugInteractiveRequest(from: [
            "type": "tool_use",
            "id": "call_ask",
            "name": "SendUserMessage",
            "input": [
                "message": "这里需要你确认下一步。",
                "options": [
                    ["id": "continue", "label": "继续"],
                    ["id": "stop", "label": "停止"]
                ]
            ]
        ]))

        XCTAssertEqual(request.id, "call_ask")
        XCTAssertEqual(request.mode, .singleChoice)
        XCTAssertEqual(request.prompt, "这里需要你确认下一步。")
        XCTAssertEqual(request.options.map(\.id), ["continue", "stop"])
        XCTAssertTrue(request.allowCustomInput)
    }

    func testCompactingStatusBecomesStreamingStatusEvent() throws {
        let line = #"{"session_id":"session-1","status":"compacting","subtype":"status","type":"system","uuid":"status-1"}"#

        let events = ClaudeCodeProcessBackend.debugEvents(fromClaudeLine: line)

        XCTAssertTrue(events.contains(.updateStreamingStatus("正在压缩上下文")))
    }

    @MainActor
    func testStatusUpdateDoesNotCancelFirstOutputTimeout() {
        let state = ChatPanelState()
        state.debugSetAwaitingFirstModelOutput(true)

        XCTAssertTrue(state.debugHasFirstVisibleOutputTimeoutTask)

        state.debugApplyBackendEvent(.updateStreamingStatus("正在压缩上下文"))

        XCTAssertFalse(state.debugDidReceiveBackendActivityAfterStart)
        XCTAssertTrue(state.debugHasFirstVisibleOutputTimeoutTask)
        XCTAssertTrue(state.isAwaitingFirstModelOutput)
    }

    @MainActor
    func testHiddenBackendActivityCancelsFirstOutputTimeout() {
        let state = ChatPanelState()
        state.status = .starting
        state.debugSetAwaitingFirstModelOutput(true)

        XCTAssertTrue(state.debugHasFirstVisibleOutputTimeoutTask)

        state.debugApplyBackendEvent(.backendActivity("process-started"))

        XCTAssertTrue(state.debugDidReceiveBackendActivityAfterStart)
        XCTAssertFalse(state.debugHasFirstVisibleOutputTimeoutTask)
        XCTAssertTrue(state.isAwaitingFirstModelOutput)

        state.debugFireFirstVisibleOutputTimeout()

        XCTAssertEqual(state.status, .starting)
        XCTAssertFalse(state.debugHasFirstVisibleOutputTimeoutTask)
        XCTAssertTrue(state.isAwaitingFirstModelOutput)
    }

    private func waitForPID(at url: URL, timeout: TimeInterval = 2.0) async throws -> pid_t {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = try? String(contentsOf: url).trimmingCharacters(in: .whitespacesAndNewlines),
               let value = Int32(text) {
                return value
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(domain: "ClaudeCodeProcessBackendInteractionTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "fake backend did not write its pid"
        ])
    }

    private func waitUntilProcessExits(_ pid: pid_t, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !Self.isProcessAlive(pid) {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return !Self.isProcessAlive(pid)
    }

    private static func isProcessAlive(_ pid: pid_t) -> Bool {
        Darwin.kill(pid, 0) == 0
    }
}

private struct RemoteRecoveryTestDataProvider: RemoteChatDataProviding {
    let projects: [ProjectItem]
    let sessions: [ChatSessionRecord]
    let messages: [UUID: [ChatMessage]]

    func loadProjects() -> [ProjectItem] { projects }
    func loadSessions() -> [ChatSessionRecord] { sessions }
    func loadSession(id: UUID) -> ChatSessionRecord? { sessions.first { $0.id == id } }
    func loadMessages(sessionID: UUID) -> [ChatMessage] { messages[sessionID] ?? [] }

    func loadMessagePage(sessionID: UUID, beforeIndex: Int?, limit: Int) -> ChatMessagePage {
        let all = messages[sessionID] ?? []
        let pageLimit = min(max(limit, 1), 500)
        let endIndex = min(max(beforeIndex ?? all.count, 0), all.count)
        let startIndex = max(0, endIndex - pageLimit)
        return ChatMessagePage(
            messages: Array(all[startIndex..<endIndex]),
            nextBeforeIndex: startIndex > 0 ? startIndex : nil,
            hasMore: startIndex > 0,
            totalCount: all.count
        )
    }
}
