import Foundation
import Security

enum AccountTokenStoreError: LocalizedError {
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

struct AccountTokenStoreCodec {
    static func encode(_ session: RemoteAuthSession, encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        try encoder.encode(session)
    }

    static func decode(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> RemoteAuthSession {
        try decoder.decode(RemoteAuthSession.self, from: data)
    }
}

actor AccountTokenStore {
    static let shared = AccountTokenStore()

    private let credentialStore: RemoteCredentialStore

    init(credentialStore: RemoteCredentialStore = .shared) {
        self.credentialStore = credentialStore
    }

    func load() async throws -> RemoteAuthSession? {
        do {
            return try await credentialStore.loadBlob().session
        } catch {
            throw mapCredentialError(error)
        }
    }

    func save(_ session: RemoteAuthSession) async throws {
        do {
            try await credentialStore.update { blob in
                blob.session = session
            }
        } catch {
            throw mapCredentialError(error)
        }
    }

    func clear() async throws {
        do {
            try await credentialStore.update { blob in
                blob.session = nil
            }
        } catch {
            throw mapCredentialError(error)
        }
    }

    private func mapCredentialError(_ error: Error) -> AccountTokenStoreError {
        guard let error = error as? RemoteCredentialStoreError else {
            return .encoding(error)
        }
        switch error {
        case .keychain(let status):
            return .keychain(status)
        case .storage(let error):
            return .storage(error)
        case .encoding(let error):
            return .encoding(error)
        case .decoding(let error):
            return .decoding(error)
        }
    }
}
