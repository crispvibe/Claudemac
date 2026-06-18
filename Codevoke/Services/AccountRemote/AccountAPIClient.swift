import Foundation

struct AccountAPIClient {
    let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL = AccountRemoteConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func get<T: Decodable>(_ path: String, authorizedToken: String? = nil) async throws -> T {
        try await perform(path: path, method: "GET", body: Optional<AccountAPIEmptyPayload>.none, authorizedToken: authorizedToken)
    }

    func post<T: Decodable, Body: Encodable>(_ path: String, body: Body, authorizedToken: String? = nil) async throws -> T {
        try await perform(path: path, method: "POST", body: body, authorizedToken: authorizedToken)
    }

    func patch<T: Decodable, Body: Encodable>(_ path: String, body: Body, authorizedToken: String? = nil) async throws -> T {
        try await perform(path: path, method: "PATCH", body: body, authorizedToken: authorizedToken)
    }

    func postIgnoringPayload<Body: Encodable>(_ path: String, body: Body, authorizedToken: String? = nil) async throws {
        _ = try await perform(path: path, method: "POST", body: body, authorizedToken: authorizedToken) as AccountAPIIgnoredPayload
    }

    private func perform<T: Decodable, Body: Encodable>(path: String, method: String, body: Body?, authorizedToken: String?) async throws -> T {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: normalizedPath, relativeTo: baseURL) else { throw AccountAPIError.invalidURL }
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
                throw AccountAPIError.invalidResponse
            }

            let statusCode = httpResponse.statusCode
            let errorEnvelope = data.isEmpty ? nil : try? decoder.decode(AccountAPIEnvelope<AccountAPIEmptyPayload>.self, from: data)
            guard (200...299).contains(statusCode) else {
                if statusCode == 401 {
                    throw AccountAPIError.unauthorized(errorEnvelope?.msg ?? "未授权。")
                }
                throw AccountAPIError.server(code: errorEnvelope?.code ?? statusCode, message: errorEnvelope?.msg ?? "请求失败（HTTP \(statusCode)）。")
            }

            if data.isEmpty {
                if T.self == AccountAPIIgnoredPayload.self {
                    return AccountAPIIgnoredPayload() as! T
                }
                throw AccountAPIError.emptyResponse
            }

            do {
                let envelope = try decoder.decode(AccountAPIEnvelope<T>.self, from: data)
                guard envelope.code == 0 else {
                    throw AccountAPIError.server(code: envelope.code, message: envelope.msg)
                }
                if T.self == AccountAPIIgnoredPayload.self {
                    return AccountAPIIgnoredPayload() as! T
                }
                guard let payload = envelope.data else {
                    throw AccountAPIError.emptyResponse
                }
                return payload
            } catch let error as AccountAPIError {
                throw error
            } catch {
                throw AccountAPIError.decoding(error)
            }
        } catch let error as AccountAPIError {
            throw error
        } catch {
            throw AccountAPIError.transport(error)
        }
    }
}
