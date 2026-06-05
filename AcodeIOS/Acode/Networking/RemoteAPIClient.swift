import Foundation

enum RemoteAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized(String)
    case server(code: Int, message: String)
    case transport(Error)
    case decoding(Error)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            L10n.string("连接地址无效。")
        case .invalidResponse:
            L10n.string("服务器返回异常。")
        case .unauthorized(let message):
            RemoteUserFacingText.apiError(message, fallback: "未授权。")
        case .server(_, let message):
            RemoteUserFacingText.apiError(message, fallback: "请求失败。")
        case .transport(let error):
            RemoteUserFacingText.apiError(error.localizedDescription, fallback: "网络连接失败，请稍后重试。")
        case .decoding:
            L10n.string("响应解析失败。")
        case .emptyResponse:
            L10n.string("服务器返回为空。")
        }
    }
}

enum RemoteAPIConfig {
    static let baseURL = URL(string: "https://acode.anna.vin")!
    static let platform = "ios"
}

struct RemoteAPIClient {
    let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL = RemoteAPIConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func get<T: Decodable>(_ path: String, authorizedToken: String? = nil) async throws -> T {
        try await perform(path: path, method: "GET", body: Optional<RemoteAPIEmptyPayload>.none, authorizedToken: authorizedToken)
    }

    func post<T: Decodable, Body: Encodable>(_ path: String, body: Body, authorizedToken: String? = nil) async throws -> T {
        try await perform(path: path, method: "POST", body: body, authorizedToken: authorizedToken)
    }

    func postIgnoringPayload<Body: Encodable>(_ path: String, body: Body, authorizedToken: String? = nil) async throws {
        _ = try await perform(path: path, method: "POST", body: body, authorizedToken: authorizedToken) as RemoteAPIIgnoredPayload
    }

    private func perform<T: Decodable, Body: Encodable>(path: String, method: String, body: Body?, authorizedToken: String?) async throws -> T {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: normalizedPath, relativeTo: baseURL) else { throw RemoteAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authorizedToken, !authorizedToken.isEmpty {
            request.setValue("Bearer \(authorizedToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RemoteAPIError.invalidResponse
            }
            guard !data.isEmpty else {
                throw RemoteAPIError.emptyResponse
            }
            do {
                let envelope = try decoder.decode(RemoteAPIEnvelope<T>.self, from: data)
                if httpResponse.statusCode == 401 {
                    throw RemoteAPIError.unauthorized(envelope.msg)
                }
                guard envelope.code == 0 else {
                    throw RemoteAPIError.server(code: envelope.code, message: envelope.msg)
                }
                if T.self == RemoteAPIIgnoredPayload.self {
                    return RemoteAPIIgnoredPayload() as! T
                }
                guard let payload = envelope.data else {
                    throw RemoteAPIError.emptyResponse
                }
                return payload
            } catch let error as RemoteAPIError {
                throw error
            } catch {
                let envelope = try? decoder.decode(RemoteAPIEnvelope<RemoteAPIEmptyPayload>.self, from: data)
                if httpResponse.statusCode == 401 {
                    throw RemoteAPIError.unauthorized(envelope?.msg ?? L10n.string("未授权。"))
                }
                if let envelope {
                    throw RemoteAPIError.server(code: envelope.code, message: envelope.msg)
                }
                throw RemoteAPIError.decoding(error)
            }
        } catch let error as RemoteAPIError {
            throw error
        } catch {
            throw RemoteAPIError.transport(error)
        }
    }
}
