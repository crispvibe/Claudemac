import Foundation
import Security

enum RemoteTokenStoreError: LocalizedError {
    case keychain(OSStatus)
    case encoding(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            SecCopyErrorMessageString(status, nil) as String? ?? L10n.string("钥匙串读写失败。")
        case .encoding(let error):
            error.localizedDescription
        case .decoding(let error):
            error.localizedDescription
        }
    }
}

actor RemoteTokenStore {
    static let shared = RemoteTokenStore()

    private let service = "com.anna.vin.codevoke.remote.auth"
    private let account = "session"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() throws -> RemoteAuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw RemoteTokenStoreError.keychain(status)
        }
        do {
            return try decoder.decode(RemoteAuthSession.self, from: data)
        } catch {
            throw RemoteTokenStoreError.decoding(error)
        }
    }

    func save(_ session: RemoteAuthSession) throws {
        let data: Data
        do {
            data = try encoder.encode(session)
        } catch {
            throw RemoteTokenStoreError.encoding(error)
        }

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
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw RemoteTokenStoreError.keychain(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw RemoteTokenStoreError.keychain(addStatus)
        }
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw RemoteTokenStoreError.keychain(status)
    }
}
