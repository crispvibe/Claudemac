import CryptoKit
import Foundation
import Security

struct LocalDeviceIdentity: Codable, Hashable {
    var deviceUID: String
    var deviceID: Int?
    var deviceName: String
    var devicePublicKey: String
}

enum LocalDeviceIdentityStoreError: LocalizedError {
    case keychain(OSStatus)
    case encoding(Error)
    case decoding(Error)
    case missingProvisionedDeviceID

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            SecCopyErrorMessageString(status, nil) as String? ?? L10n.string("钥匙串读写失败。")
        case .encoding(let error):
            error.localizedDescription
        case .decoding(let error):
            error.localizedDescription
        case .missingProvisionedDeviceID:
            L10n.string("请先在账号中注册这台 iPhone 后再连接 Mac。")
        }
    }
}

actor DeviceIdentityStore {
    static let shared = DeviceIdentityStore()

    private let service = "vin.anna.AnnaCodeMobile.remote.device"
    private let identityAccount = "identity"
    private let privateKeyAccount = "curve25519.signing.privateKey"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadIdentity() throws -> LocalDeviceIdentity? {
        guard let data = try loadData(account: identityAccount) else { return nil }
        do {
            return try decoder.decode(LocalDeviceIdentity.self, from: data)
        } catch {
            throw LocalDeviceIdentityStoreError.decoding(error)
        }
    }

    func loadOrCreateIdentity() throws -> LocalDeviceIdentity {
        if let identity = try loadIdentity() {
            return identity
        }
        let privateKey = Curve25519.Signing.PrivateKey()
        try saveData(privateKey.rawRepresentation, account: privateKeyAccount)
        let identity = LocalDeviceIdentity(
            deviceUID: UUID().uuidString,
            deviceID: nil,
            deviceName: "AnnaCode iPhone",
            devicePublicKey: privateKey.publicKey.rawRepresentation.base64EncodedString()
        )
        try saveIdentity(identity)
        return identity
    }

    func saveIdentity(_ identity: LocalDeviceIdentity) throws {
        do {
            try saveData(try encoder.encode(identity), account: identityAccount)
        } catch let error as LocalDeviceIdentityStoreError {
            throw error
        } catch {
            throw LocalDeviceIdentityStoreError.encoding(error)
        }
    }

    func updateDeviceID(_ deviceID: Int) throws {
        var identity = try loadOrCreateIdentity()
        identity.deviceID = deviceID
        try saveIdentity(identity)
    }

    func requireProvisionedDeviceID() throws -> Int {
        guard let deviceID = try loadOrCreateIdentity().deviceID else {
            throw LocalDeviceIdentityStoreError.missingProvisionedDeviceID
        }
        return deviceID
    }

    func signNonce(_ nonce: String) throws -> String {
        let privateKey = try loadOrCreatePrivateKey()
        let signature = try privateKey.signature(for: Data(nonce.utf8))
        return signature.base64EncodedString()
    }

    private func loadOrCreatePrivateKey() throws -> Curve25519.Signing.PrivateKey {
        if let data = try loadData(account: privateKeyAccount) {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        }
        let privateKey = Curve25519.Signing.PrivateKey()
        try saveData(privateKey.rawRepresentation, account: privateKeyAccount)
        return privateKey
    }

    private func loadData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw LocalDeviceIdentityStoreError.keychain(status)
        }
        return data
    }

    private func saveData(_ data: Data, account: String) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw LocalDeviceIdentityStoreError.keychain(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw LocalDeviceIdentityStoreError.keychain(addStatus)
        }
    }
}
