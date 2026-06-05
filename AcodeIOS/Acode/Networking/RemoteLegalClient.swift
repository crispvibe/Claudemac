import Foundation

struct RemoteLegalClient {
    private let api: RemoteAPIClient

    init(api: RemoteAPIClient = RemoteAPIClient()) {
        self.api = api
    }

    func fetchDocument(type: RemoteLegalDocumentType, platform: String = RemoteAPIConfig.platform) async throws -> RemoteLegalDocument {
        let encodedType = type.rawValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? type.rawValue
        let encodedPlatform = platform.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? platform
        return try await api.get("remote/legal-documents?type=\(encodedType)&platform=\(encodedPlatform)")
    }

    func fetchAppFooter(platform: String = RemoteAPIConfig.platform) async throws -> RemoteAppFooter {
        let encodedPlatform = platform.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? platform
        return try await api.get("remote/app-footer?platform=\(encodedPlatform)")
    }

    func checkAppUpdate(platform: String = RemoteAPIConfig.platform, version: String, buildNumber: String) async throws -> RemoteAppUpdateCheckResponse {
        let encodedPlatform = platform.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? platform
        let encodedVersion = version.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? version
        let encodedBuild = buildNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? buildNumber
        return try await api.get("remote/app-updates/check?platform=\(encodedPlatform)&channel=stable&version=\(encodedVersion)&buildNumber=\(encodedBuild)")
    }

    func consent(documentId: Int, platform: String = RemoteAPIConfig.platform, deviceId: Int = 0, accessToken: String) async throws {
        try await api.postIgnoringPayload(
            "remote/legal-consents",
            body: RemoteLegalConsentRequest(documentId: documentId, platform: platform, deviceId: deviceId),
            authorizedToken: accessToken
        )
    }
}
