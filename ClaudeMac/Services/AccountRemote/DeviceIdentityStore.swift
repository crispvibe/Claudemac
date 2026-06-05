import CryptoKit
import Foundation
import Security

struct DeviceIdentity: Codable, Hashable {
    var deviceUID: String
    var deviceID: Int?
    var deviceName: String
    var devicePublicKey: String
}

enum DeviceIdentityStoreError: LocalizedError {
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

actor DeviceIdentityStore {
    static let shared = DeviceIdentityStore()

    private let credentialStore: RemoteCredentialStore

    init(credentialStore: RemoteCredentialStore = .shared) {
        self.credentialStore = credentialStore
    }

    func loadIdentity() async throws -> DeviceIdentity? {
        do {
            return try await credentialStore.loadBlob().deviceIdentity
        } catch {
            throw mapCredentialError(error)
        }
    }

    func saveIdentity(_ identity: DeviceIdentity) async throws {
        do {
            try await credentialStore.update { blob in
                blob.deviceIdentity = identity
            }
        } catch {
            throw mapCredentialError(error)
        }
    }

    func clearProvisionedDevice() async throws {
        do {
            try await credentialStore.update { blob in
                if var identity = blob.deviceIdentity {
                    identity.deviceUID = UUID().uuidString
                    identity.deviceID = nil
                    blob.deviceIdentity = identity
                }
                blob.deviceCode = nil
            }
        } catch {
            throw mapCredentialError(error)
        }
    }

    func loadOrCreateIdentity() async throws -> DeviceIdentity {
        do {
            var blob = try await credentialStore.loadBlob()
            if let identity = blob.deviceIdentity {
                return identity
            }

            let privateKey: Curve25519.Signing.PrivateKey
            if let privateKeyData = blob.deviceSigningPrivateKey,
               let restoredPrivateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData) {
                privateKey = restoredPrivateKey
            } else {
                privateKey = Curve25519.Signing.PrivateKey()
                blob.deviceSigningPrivateKey = privateKey.rawRepresentation
            }

            let identity = DeviceIdentity(
                deviceUID: Self.deviceUID(for: privateKey.publicKey),
                deviceID: nil,
                deviceName: Host.current().localizedName ?? "我的 Mac",
                devicePublicKey: privateKey.publicKey.rawRepresentation.base64EncodedString()
            )
            blob.deviceIdentity = identity
            try await credentialStore.saveBlob(blob)
            return identity
        } catch {
            throw mapCredentialError(error)
        }
    }

    func updateDeviceID(_ deviceID: Int) async throws {
        var identity = try await loadOrCreateIdentity()
        identity.deviceID = deviceID
        try await saveIdentity(identity)
    }

    func updateDeviceName(_ deviceName: String) async throws {
        var identity = try await loadOrCreateIdentity()
        identity.deviceName = deviceName
        try await saveIdentity(identity)
    }

    private static func deviceUID(for publicKey: Curve25519.Signing.PublicKey) -> String {
        let digest = SHA256.hash(data: publicKey.rawRepresentation)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "macos-\(hex.prefix(32))"
    }

    func loadDeviceCode() async throws -> String? {
        do {
            guard let code = try await credentialStore.loadBlob().deviceCode else { return nil }
            return code.isEmpty ? nil : code
        } catch {
            throw mapCredentialError(error)
        }
    }

    func saveDeviceCode(_ deviceCode: String) async throws {
        do {
            try await credentialStore.update { blob in
                blob.deviceCode = deviceCode.isEmpty ? nil : deviceCode
            }
        } catch {
            throw mapCredentialError(error)
        }
    }

    func deleteDeviceCode() async throws {
        do {
            try await credentialStore.update { blob in
                blob.deviceCode = nil
            }
        } catch {
            throw mapCredentialError(error)
        }
    }

    private func mapCredentialError(_ error: Error) -> DeviceIdentityStoreError {
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
