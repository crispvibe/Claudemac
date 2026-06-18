import Foundation
import Security

struct RemoteCredentialBlob: Codable, Hashable {
    var schemaVersion: Int
    var session: RemoteAuthSession?
    var deviceIdentity: DeviceIdentity?
    var deviceSigningPrivateKey: Data?
    var deviceCode: String?

    static var empty: RemoteCredentialBlob {
        RemoteCredentialBlob(
            schemaVersion: 1,
            session: nil,
            deviceIdentity: nil,
            deviceSigningPrivateKey: nil,
            deviceCode: nil
        )
    }
}

enum RemoteCredentialStoreError: LocalizedError {
    case keychain(OSStatus)
    case storage(Error)
    case encoding(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            SecCopyErrorMessageString(status, nil) as String? ?? "钥匙串读写失败。"
        case .storage(let error):
            "本机凭据存储读写失败：\(error.localizedDescription)"
        case .encoding(let error):
            error.localizedDescription
        case .decoding(let error):
            error.localizedDescription
        }
    }
}

enum RemoteCredentialBlobCodec {
    static func encode(_ blob: RemoteCredentialBlob, encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        try encoder.encode(blob)
    }

    static func decode(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> RemoteCredentialBlob {
        try decoder.decode(RemoteCredentialBlob.self, from: data)
    }
}

protocol RemoteCredentialStorage: Sendable {
    func loadData(service: String, account: String) throws -> Data?
    func saveData(_ data: Data, service: String, account: String) throws
    func deleteData(service: String, account: String) throws
}

typealias RemoteCredentialKeychainStorage = RemoteCredentialStorage

struct RemoteCredentialFileStorage: RemoteCredentialStorage, @unchecked Sendable {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) throws {
        self.fileManager = fileManager
        self.directoryURL = try directoryURL ?? Self.defaultDirectoryURL(fileManager: fileManager)
        try createCredentialDirectoryIfNeeded()
    }

    func loadData(service: String, account: String) throws -> Data? {
        let url = credentialURL(service: service, account: account)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw RemoteCredentialStoreError.storage(error)
        }
    }

    func saveData(_ data: Data, service: String, account: String) throws {
        let url = credentialURL(service: service, account: account)
        do {
            try createCredentialDirectoryIfNeeded()
            try data.write(to: url, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw RemoteCredentialStoreError.storage(error)
        }
    }

    func deleteData(service: String, account: String) throws {
        let url = credentialURL(service: service, account: account)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw RemoteCredentialStoreError.storage(error)
        }
    }

    private static func defaultDirectoryURL(fileManager: FileManager) throws -> URL {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw RemoteCredentialStoreError.storage(CocoaError(.fileNoSuchFile))
        }
        return base
            .appendingPathComponent("Codevoke", isDirectory: true)
            .appendingPathComponent("Credentials", isDirectory: true)
    }

    private func createCredentialDirectoryIfNeeded() throws {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        } catch {
            throw RemoteCredentialStoreError.storage(error)
        }
    }

    private func credentialURL(service: String, account: String) -> URL {
        if service == RemoteCredentialStore.blobService, account == RemoteCredentialStore.blobAccount {
            return directoryURL.appendingPathComponent("remote-credentials.json")
        }
        let filename = "\(sanitizedPathComponent(service))-\(sanitizedPathComponent(account)).bin"
        return directoryURL.appendingPathComponent(filename)
    }

    private func sanitizedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }.joined()
    }
}

/// Keychain-primary storage that transparently migrates any pre-existing plaintext-file
/// credentials into the Keychain on first read, and falls back to file storage only when the
/// Keychain itself is unavailable (so a missing entitlement can't lock the user out).
struct MigratingKeychainStorage: RemoteCredentialStorage {
    let keychain: RemoteCredentialStorage
    let file: RemoteCredentialStorage?

    func loadData(service: String, account: String) throws -> Data? {
        if let data = try? keychain.loadData(service: service, account: account) {
            return data
        }
        guard let file, let data = try? file.loadData(service: service, account: account) else {
            return nil
        }
        try? keychain.saveData(data, service: service, account: account)
        try? file.deleteData(service: service, account: account)
        return data
    }

    func saveData(_ data: Data, service: String, account: String) throws {
        do {
            try keychain.saveData(data, service: service, account: account)
        } catch {
            guard let file else { throw error }
            try file.saveData(data, service: service, account: account)
        }
    }

    func deleteData(service: String, account: String) throws {
        try? keychain.deleteData(service: service, account: account)
        try? file?.deleteData(service: service, account: account)
    }
}

struct RemoteSystemCredentialKeychainStorage: RemoteCredentialStorage {
    func loadData(service: String, account: String) throws -> Data? {
        var lastStatus: OSStatus = errSecItemNotFound
        for var query in baseQueries(service: service, account: account) {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data {
                return data
            }
            lastStatus = status
            if shouldTryNextKeychain(after: status) {
                continue
            }
            throw RemoteCredentialStoreError.keychain(status)
        }
        if lastStatus == errSecItemNotFound || lastStatus == errSecMissingEntitlement {
            return nil
        }
        throw RemoteCredentialStoreError.keychain(lastStatus)
    }

    func saveData(_ data: Data, service: String, account: String) throws {
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var lastStatus: OSStatus = errSecItemNotFound
        for baseQuery in baseQueries(service: service, account: account) {
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
            if updateStatus == errSecSuccess { return }
            if updateStatus != errSecItemNotFound {
                lastStatus = updateStatus
                if shouldTryNextKeychain(after: updateStatus) {
                    continue
                }
                throw RemoteCredentialStoreError.keychain(updateStatus)
            }

            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess { return }
            lastStatus = addStatus
            if shouldTryNextKeychain(after: addStatus) {
                continue
            }
            throw RemoteCredentialStoreError.keychain(addStatus)
        }
        throw RemoteCredentialStoreError.keychain(lastStatus)
    }

    func deleteData(service: String, account: String) throws {
        var firstError: OSStatus?
        for query in baseQueries(service: service, account: account) {
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecSuccess || shouldTryNextKeychain(after: status) {
                continue
            }
            firstError = firstError ?? status
        }
        if let firstError {
            throw RemoteCredentialStoreError.keychain(firstError)
        }
    }

    private func baseQueries(service: String, account: String) -> [[String: Any]] {
        let standardQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        var dataProtectionQuery = standardQuery
        dataProtectionQuery[kSecUseDataProtectionKeychain as String] = true
        return [dataProtectionQuery, standardQuery]
    }

    private func shouldTryNextKeychain(after status: OSStatus) -> Bool {
        status == errSecItemNotFound || status == errSecMissingEntitlement
    }
}

actor RemoteCredentialStore {
    static let shared = RemoteCredentialStore(storage: RemoteCredentialStore.makeDefaultStorage())

    static let blobService = "com.anna.vin.codevoke.remote.credentials"
    static let blobAccount = "blob"
    static let legacyAccountService = "com.anna.vin.codevoke.remote.account"
    static let legacySessionAccount = "session"
    static let legacyDeviceService = "com.anna.vin.codevoke.remote.device"
    static let legacyIdentityAccount = "identity"
    static let legacyPrivateKeyAccount = "curve25519.signing.privateKey"
    static let legacyDeviceCodeAccount = "deviceCode"

    private let storage: RemoteCredentialStorage

    init(storage: RemoteCredentialStorage = RemoteCredentialStore.makeDefaultStorage()) {
        self.storage = storage
    }

    func loadBlob() throws -> RemoteCredentialBlob {
        if let data = try storage.loadData(service: Self.blobService, account: Self.blobAccount) {
            do {
                return try RemoteCredentialBlobCodec.decode(data)
            } catch {
                throw RemoteCredentialStoreError.decoding(error)
            }
        }
        let blob = try migrateLegacyBlob()
        try saveBlob(blob)
        return blob
    }

    private static func makeDefaultStorage() -> RemoteCredentialStorage {
        // Prefer the system Keychain (tokens + device signing private key are sensitive and
        // must not sit in plaintext JSON). Keep file storage as a migration source / fallback
        // for environments where the Keychain is unavailable (e.g. missing entitlement).
        let keychain = RemoteSystemCredentialKeychainStorage()
        let file = try? RemoteCredentialFileStorage()
        return MigratingKeychainStorage(keychain: keychain, file: file)
    }

    func saveBlob(_ blob: RemoteCredentialBlob) throws {
        do {
            try storage.saveData(try RemoteCredentialBlobCodec.encode(blob), service: Self.blobService, account: Self.blobAccount)
        } catch let error as RemoteCredentialStoreError {
            throw error
        } catch {
            throw RemoteCredentialStoreError.encoding(error)
        }
    }

    func update(_ mutate: (inout RemoteCredentialBlob) throws -> Void) throws {
        var blob = try loadBlob()
        try mutate(&blob)
        try saveBlob(blob)
    }

    func clearBlob() throws {
        try storage.deleteData(service: Self.blobService, account: Self.blobAccount)
    }

    private func migrateLegacyBlob() throws -> RemoteCredentialBlob {
        RemoteCredentialBlob(
            schemaVersion: 1,
            session: try loadLegacySession(),
            deviceIdentity: try loadLegacyIdentity(),
            deviceSigningPrivateKey: try storage.loadData(service: Self.legacyDeviceService, account: Self.legacyPrivateKeyAccount),
            deviceCode: try loadLegacyDeviceCode()
        )
    }

    private func loadLegacySession() throws -> RemoteAuthSession? {
        guard let data = try storage.loadData(service: Self.legacyAccountService, account: Self.legacySessionAccount) else { return nil }
        do {
            return try AccountTokenStoreCodec.decode(data)
        } catch {
            throw RemoteCredentialStoreError.decoding(error)
        }
    }

    private func loadLegacyIdentity() throws -> DeviceIdentity? {
        guard let data = try storage.loadData(service: Self.legacyDeviceService, account: Self.legacyIdentityAccount) else { return nil }
        do {
            return try JSONDecoder().decode(DeviceIdentity.self, from: data)
        } catch {
            throw RemoteCredentialStoreError.decoding(error)
        }
    }

    private func loadLegacyDeviceCode() throws -> String? {
        guard let data = try storage.loadData(service: Self.legacyDeviceService, account: Self.legacyDeviceCodeAccount) else { return nil }
        guard let code = String(data: data, encoding: .utf8) else { return nil }
        return code.isEmpty ? nil : code
    }
}
