import Darwin
import Foundation

@MainActor
final class ChatModelService: ObservableObject {
    @Published var claudeModels: [ChatModelOption] = []
    @Published var codexModels: [ChatModelOption] = []
    @Published var isFetching = false

    private var lastClaudeBaseURL: String = ""
    private var lastCodexBaseURL: String = ""
    private var configuredClaudeModels: [ChatModelOption] = []
    private var configuredCodexModels: [ChatModelOption] = []
    private var configuredClaudeDefaultModelID: String?
    private var configuredCodexDefaultModelID: String?

    // MARK: - Public API

    func options(for cli: CLIType) -> [ChatModelOption] {
        switch cli.visibleValue {
        case .claude:
            return withConfiguredDefaultTitle(
                mergedOptions(ChatModelCatalog.options(for: .claude), claudeModels, configuredClaudeModels),
                cli: .claude
            )
        case .codex:
            return withConfiguredDefaultTitle(
                mergedOptions(ChatModelCatalog.options(for: .codex), codexModels, configuredCodexModels),
                cli: .codex
            )
        case .gemini, .custom:
            return withConfiguredDefaultTitle(
                mergedOptions(ChatModelCatalog.options(for: .claude), claudeModels, configuredClaudeModels),
                cli: .claude
            )
        }
    }

    func title(for id: String, cli: CLIType) -> String {
        options(for: cli).first { $0.id == id }?.title ?? id
    }

    func defaultModelID(for cli: CLIType) -> String {
        switch cli.visibleValue {
        case .claude:
            configuredClaudeDefaultModelID?.nonEmptyTrimmed ?? ChatModelCatalog.defaultModelID(for: cli)
        case .codex:
            configuredCodexDefaultModelID?.nonEmptyTrimmed ?? ChatModelCatalog.defaultModelID(for: cli)
        case .gemini, .custom:
            configuredClaudeDefaultModelID?.nonEmptyTrimmed ?? ChatModelCatalog.defaultModelID(for: cli)
        }
    }

    func contextModelID(for id: String, cli: CLIType) -> String {
        let catalogDefault = ChatModelCatalog.defaultModelID(for: cli)
        if catalogDefault == "default", id == catalogDefault {
            return defaultModelID(for: cli)
        }
        return id
    }

    func defaultReasoningEffort(for cli: CLIType) -> ChatReasoningEffort {
        .high
    }

    func reloadConfiguredModels() {
        let claude = Self.loadClaudeConfiguredModels()
        configuredClaudeDefaultModelID = claude.defaultModelID
        configuredClaudeModels = claude.modelIDs.map { ChatModelOption(id: $0, title: prettifyModelID($0, cli: .claude), cli: .claude) }

        let codex = Self.loadCodexConfiguredModel()
        configuredCodexDefaultModelID = codex
        configuredCodexModels = codex.map { [ChatModelOption(id: $0, title: prettifyModelID($0, cli: .codex), cli: .codex)] } ?? []
    }

    /// Fetch models for both CLI types using the configured base URLs and keys.
    func fetchAll(claudeBaseURL: String, claudeKey: String, codexBaseURL: String, codexKey: String) {
        fetchClaudeModels(baseURL: claudeBaseURL, apiKey: claudeKey)
        fetchCodexModels(baseURL: codexBaseURL, apiKey: codexKey)
    }

    /// Fetch Claude models from the API.
    func fetchClaudeModels(baseURL: String, apiKey: String) {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty else {
            claudeModels = []
            return
        }

        // Skip if same URL and we already have results
        if trimmedURL == lastClaudeBaseURL && !claudeModels.isEmpty { return }
        lastClaudeBaseURL = trimmedURL

        isFetching = true

        let candidates = [
            trimmedURL.hasSuffix("/") ? trimmedURL + "v1/models" : trimmedURL + "/v1/models",
            trimmedURL.hasSuffix("/") ? trimmedURL + "models" : trimmedURL + "/models",
        ]

        Task {
            let fetched = await fetchModels(from: candidates, apiKey: apiKey, cli: .claude)
            await MainActor.run {
                if !fetched.isEmpty {
                    // Always prepend "default" option
                    var result = [ChatModelOption(id: ChatModelCatalog.defaultClaudeModelID, title: "默认", cli: .claude)]
                    result.append(contentsOf: fetched)
                    self.claudeModels = result
                }
                self.isFetching = false
            }
        }
    }

    /// Fetch Codex models from the API.
    func fetchCodexModels(baseURL: String, apiKey: String) {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty else {
            codexModels = []
            return
        }

        if trimmedURL == lastCodexBaseURL && !codexModels.isEmpty { return }
        lastCodexBaseURL = trimmedURL

        isFetching = true

        let candidates = [
            trimmedURL.hasSuffix("/") ? trimmedURL + "models" : trimmedURL + "/models",
        ]

        Task {
            let fetched = await fetchModels(from: candidates, apiKey: apiKey, cli: .codex)
            await MainActor.run {
                if !fetched.isEmpty {
                    self.codexModels = fetched
                }
                self.isFetching = false
            }
        }
    }

    /// Force re-fetch (ignores cache).
    func refresh(claudeBaseURL: String, claudeKey: String, codexBaseURL: String, codexKey: String) {
        lastClaudeBaseURL = ""
        lastCodexBaseURL = ""
        claudeModels = []
        codexModels = []
        reloadConfiguredModels()
        fetchAll(claudeBaseURL: claudeBaseURL, claudeKey: claudeKey, codexBaseURL: codexBaseURL, codexKey: codexKey)
    }

    // MARK: - Private

    private func mergedOptions(_ groups: [ChatModelOption]...) -> [ChatModelOption] {
        groups.flatMap { $0 }.reduce(into: [ChatModelOption]()) { result, option in
            let key = modelIdentityKey(option)
            if let existingIndex = result.firstIndex(where: { modelIdentityKey($0) == key }) {
                result[existingIndex] = option
            } else {
                result.append(option)
            }
        }
    }

    private func modelIdentityKey(_ option: ChatModelOption) -> String {
        let executionID = ChatModelCatalog.executionModelID(for: option.id).lowercased()
        return "\(option.cli.visibleValue.rawValue):\(executionID)"
    }

    private func withConfiguredDefaultTitle(_ options: [ChatModelOption], cli: CLIType) -> [ChatModelOption] {
        let catalogDefault = ChatModelCatalog.defaultModelID(for: cli)
        let configured = defaultModelID(for: cli)
        guard catalogDefault == "default", configured != catalogDefault else { return options }

        let configuredTitle = prettifyModelID(configured, cli: cli)
        return options.map { option in
            guard option.id == catalogDefault else { return option }
            return ChatModelOption(id: option.id, title: "默认（\(configuredTitle)）", cli: option.cli)
        }
    }

    private func fetchModels(from candidates: [String], apiKey: String, cli: CLIType) async -> [ChatModelOption] {
        let token = apiKey.trimmingCharacters(in: .whitespaces)

        for urlString in candidates {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "GET"
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue(token, forHTTPHeaderField: "x-api-key")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { continue }
                if let ids = parseModelListResponse(data) {
                    return ids.sorted().map { id in
                        ChatModelOption(id: id, title: prettifyModelID(id, cli: cli), cli: cli)
                    }
                }
            } catch {
                continue
            }
        }

        return []
    }

    /// Parse OpenAI-compatible /models response.
    private func parseModelListResponse(_ data: Data) -> [String]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Some relays return a plain array
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let ids = arr.compactMap { $0["id"] as? String }
                return ids.isEmpty ? nil : ids
            }
            return nil
        }

        // OpenAI format: { "data": [{ "id": "model-name", ... }] }
        if let dataArray = json["data"] as? [[String: Any]] {
            let ids = dataArray.compactMap { $0["id"] as? String }
            return ids.isEmpty ? nil : ids
        }

        return nil
    }

    /// Generate a human-friendly title from a model ID.
    private func prettifyModelID(_ id: String, cli: CLIType) -> String {
        let knownOptions = ChatModelCatalog.options(for: cli)
        let executionID = ChatModelCatalog.executionModelID(for: id)
        if let known = knownOptions.first(where: { $0.id == executionID }) {
            if id.lowercased().contains("[1m]"), !known.title.lowercased().contains("1m") {
                return "\(known.title) 1M"
            }
            return known.title
        }
        return id
    }

    private static func loadClaudeConfiguredModels() -> (defaultModelID: String?, modelIDs: [String]) {
        guard let data = try? Data(contentsOf: claudeSettingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = json["env"] as? [String: String] else {
            return (nil, [])
        }

        let ids = [
            env["ANTHROPIC_MODEL"],
            env["ANTHROPIC_DEFAULT_OPUS_MODEL"],
            env["ANTHROPIC_DEFAULT_SONNET_MODEL"],
            env["ANTHROPIC_DEFAULT_HAIKU_MODEL"]
        ]
        .compactMap { $0?.nonEmptyTrimmed }

        return (env["ANTHROPIC_MODEL"]?.nonEmptyTrimmed, unique(ids))
    }

    private static func loadCodexConfiguredModel() -> String? {
        guard let text = try? String(contentsOf: codexConfigURL, encoding: .utf8) else { return nil }
        return parseTomlValue(text, key: "model")?.nonEmptyTrimmed
    }

    private static func parseTomlValue(_ text: String, key: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key)") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            return parts[1]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    private static func unique(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { result, value in
            if !result.contains(value) { result.append(value) }
        }
    }

    private static var realHomeDirectory: URL {
        if let passwd = getpwuid(getuid()), let directory = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static var claudeSettingsURL: URL {
        realHomeDirectory.appendingPathComponent(".claude/settings.json")
    }

    private static var codexConfigURL: URL {
        realHomeDirectory.appendingPathComponent(".codex/config.toml")
    }
}
