import Foundation

struct CLIHistoryScanner {
    static func claudeTranscriptExists(sessionID: String, projectPath: String?) -> Bool {
        let fileName = "\(sessionID).jsonl"
        let projectsRoot = claudeProjectsRoot()
        if let projectPath {
            let direct = projectsRoot
                .appendingPathComponent(claudeStorageKey(for: projectPath), isDirectory: true)
                .appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: direct.path) { return true }
        }
        guard let enumerator = FileManager.default.enumerator(
            at: projectsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return false }
        for case let url as URL in enumerator where url.lastPathComponent == fileName {
            if !url.pathComponents.contains("subagents") { return true }
        }
        return false
    }

    func scan(projectPath: String?) -> [CLIHistorySession] {
        let sessions = scanClaude(projectPath: projectPath) + scanCodex(projectPath: projectPath)
        return deduplicated(sessions).sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    private func scanClaude(projectPath: String?) -> [CLIHistorySession] {
        let home = URL(fileURLWithPath: ChatCLIEnvironment.realHomeDirectory, isDirectory: true)
        let projectsRoot = home.appendingPathComponent(".claude", isDirectory: true).appendingPathComponent("projects", isDirectory: true)
        var sessions: [CLIHistorySession] = []

        if let enumerator = FileManager.default.enumerator(
            at: projectsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard !url.pathComponents.contains("subagents") else { continue }
                if let session = parseClaudeProjectJSONL(url: url), matches(session: session, projectPath: projectPath) {
                    sessions.append(session)
                }
            }
        }

        let availableSessionIDs = Set(sessions.map(\.sessionId))
        let historyURL = home.appendingPathComponent(".claude", isDirectory: true).appendingPathComponent("history.jsonl")
        sessions.append(contentsOf: parseClaudeHistoryJSONL(url: historyURL).filter { session in
            matches(session: session, projectPath: projectPath)
                && (availableSessionIDs.contains(session.sessionId) || Self.claudeTranscriptExists(sessionID: session.sessionId, projectPath: session.projectPath))
        })
        return sessions
    }

    private func scanCodex(projectPath: String?) -> [CLIHistorySession] {
        let home = URL(fileURLWithPath: ChatCLIEnvironment.realHomeDirectory, isDirectory: true)
        let codexRoot = home.appendingPathComponent(".codex", isDirectory: true)
        let index = parseCodexSessionIndex(url: codexRoot.appendingPathComponent("session_index.jsonl"))
        var sessions: [CLIHistorySession] = []

        let roots = [
            codexRoot.appendingPathComponent("sessions", isDirectory: true),
            codexRoot.appendingPathComponent("archived_sessions", isDirectory: true)
        ]

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                if let session = parseCodexSessionJSONL(url: url, index: index), matches(session: session, projectPath: projectPath) {
                    sessions.append(session)
                }
            }
        }

        sessions.append(contentsOf: parseCodexHistoryJSONL(url: codexRoot.appendingPathComponent("history.jsonl"), index: index).filter { matches(session: $0, projectPath: projectPath) })
        return sessions
    }

    private func parseClaudeProjectJSONL(url: URL) -> CLIHistorySession? {
        guard let content = readUTF8(url: url) else { return nil }

        var sessionId = url.deletingPathExtension().lastPathComponent
        var cwd: String?
        var title: String?
        var firstPrompt: String?
        var createdAt: Date?
        var updatedAt: Date?

        for object in jsonObjects(from: content) {
            if let value = object["sessionId"] as? String, !value.isEmpty { sessionId = value }
            if let value = object["cwd"] as? String, !value.isEmpty { cwd = value }
            if let date = date(from: object["timestamp"]) {
                if createdAt == nil { createdAt = date }
                updatedAt = date
            }
            if let value = object["aiTitle"] as? String, !value.isEmpty { title = value }
            if title == nil, let value = object["summary"] as? String, !value.isEmpty { title = value }
            if firstPrompt == nil,
               let type = object["type"] as? String,
               type == "user" {
                firstPrompt = userPrompt(from: object)
            }
        }

        let storageKey = url.deletingLastPathComponent().lastPathComponent
        return CLIHistorySession(
            cli: .claude,
            sessionId: sessionId,
            title: clippedTitle(title ?? firstLine(firstPrompt) ?? "Claude 历史会话"),
            projectPath: cwd,
            storageKey: storageKey,
            storagePath: url.path,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func parseClaudeHistoryJSONL(url: URL) -> [CLIHistorySession] {
        guard let content = readUTF8(url: url) else { return [] }
        var sessions: [String: CLIHistorySession] = [:]

        for object in jsonObjects(from: content) {
            guard let sessionId = object["sessionId"] as? String, !sessionId.isEmpty else { continue }
            let projectPath = object["project"] as? String
            let display = object["display"] as? String
            let updatedAt = date(from: object["timestamp"])
            let current = sessions[sessionId]
            let session = CLIHistorySession(
                cli: .claude,
                sessionId: sessionId,
                title: clippedTitle(firstLine(display) ?? current?.title ?? "Claude 历史会话"),
                projectPath: projectPath ?? current?.projectPath,
                storageKey: current?.storageKey,
                storagePath: url.path,
                createdAt: current?.createdAt ?? updatedAt,
                updatedAt: newer(current?.updatedAt, updatedAt)
            )
            sessions[sessionId] = session
        }

        return Array(sessions.values)
    }

    private func parseCodexSessionJSONL(url: URL, index: [String: CodexIndexEntry]) -> CLIHistorySession? {
        guard let content = readUTF8(url: url) else { return nil }

        var sessionId = url.deletingPathExtension().lastPathComponent
        var cwd: String?
        var title: String?
        var firstPrompt: String?
        var createdAt: Date?
        var updatedAt: Date?

        for object in jsonObjects(from: content) {
            if let date = date(from: object["timestamp"]) {
                if createdAt == nil { createdAt = date }
                updatedAt = date
            }
            guard let payload = object["payload"] as? [String: Any] else { continue }
            if let value = payload["id"] as? String, !value.isEmpty { sessionId = value }
            if let value = payload["thread_id"] as? String, !value.isEmpty { sessionId = value }
            if let value = payload["cwd"] as? String, !value.isEmpty { cwd = value }
            if let date = date(from: payload["timestamp"]) ?? date(from: payload["started_at"]) {
                if createdAt == nil { createdAt = date }
                updatedAt = newer(updatedAt, date)
            }
            if title == nil, let value = payload["summary"] as? String, !value.isEmpty { title = value }
            if firstPrompt == nil,
               let role = payload["role"] as? String,
               role == "user" {
                firstPrompt = text(from: payload["content"])
            }
        }

        let indexed = index[sessionId]
        return CLIHistorySession(
            cli: .codex,
            sessionId: sessionId,
            title: clippedTitle(indexed?.threadName ?? title ?? firstLine(firstPrompt) ?? "Codex 历史会话"),
            projectPath: cwd,
            storageKey: url.deletingLastPathComponent().lastPathComponent,
            storagePath: url.path,
            createdAt: createdAt,
            updatedAt: newer(updatedAt, indexed?.updatedAt)
        )
    }

    private func parseCodexHistoryJSONL(url: URL, index: [String: CodexIndexEntry]) -> [CLIHistorySession] {
        guard let content = readUTF8(url: url) else { return [] }
        var sessions: [String: CLIHistorySession] = [:]

        for object in jsonObjects(from: content) {
            guard let sessionId = object["session_id"] as? String, !sessionId.isEmpty else { continue }
            let updatedAt = date(from: object["ts"])
            let indexed = index[sessionId]
            let current = sessions[sessionId]
            let title = indexed?.threadName ?? firstLine(object["text"] as? String) ?? current?.title ?? "Codex 历史会话"
            sessions[sessionId] = CLIHistorySession(
                cli: .codex,
                sessionId: sessionId,
                title: clippedTitle(title),
                projectPath: current?.projectPath,
                storageKey: current?.storageKey,
                storagePath: url.path,
                createdAt: current?.createdAt ?? updatedAt,
                updatedAt: newer(newer(current?.updatedAt, updatedAt), indexed?.updatedAt)
            )
        }

        return Array(sessions.values)
    }

    private func parseCodexSessionIndex(url: URL) -> [String: CodexIndexEntry] {
        guard let content = readUTF8(url: url) else { return [:] }
        var entries: [String: CodexIndexEntry] = [:]

        for object in jsonObjects(from: content) {
            guard let id = object["id"] as? String, !id.isEmpty else { continue }
            entries[id] = CodexIndexEntry(
                threadName: object["thread_name"] as? String,
                updatedAt: date(from: object["updated_at"])
            )
        }
        return entries
    }

    private func matches(session: CLIHistorySession, projectPath: String?) -> Bool {
        guard let projectPath, !projectPath.isEmpty else { return true }
        if let sessionPath = session.projectPath, normalizedPath(sessionPath) == normalizedPath(projectPath) {
            return true
        }
        return session.storageKey == storageKey(for: projectPath)
    }

    private func deduplicated(_ sessions: [CLIHistorySession]) -> [CLIHistorySession] {
        var unique: [String: CLIHistorySession] = [:]
        for session in sessions {
            guard let current = unique[session.id] else {
                unique[session.id] = session
                continue
            }
            unique[session.id] = preferred(current, session)
        }
        return Array(unique.values)
    }

    private func preferred(_ lhs: CLIHistorySession, _ rhs: CLIHistorySession) -> CLIHistorySession {
        if lhs.projectPath == nil, rhs.projectPath != nil { return rhs }
        if lhs.storagePath?.hasSuffix("history.jsonl") == true, rhs.storagePath?.hasSuffix("history.jsonl") == false { return rhs }
        if (rhs.updatedAt ?? .distantPast) > (lhs.updatedAt ?? .distantPast) { return rhs }
        return lhs
    }

    private func userPrompt(from object: [String: Any]) -> String? {
        if let value = object["lastPrompt"] as? String, !value.isEmpty { return value }
        guard let message = object["message"] as? [String: Any] else { return nil }
        return text(from: message["content"])
    }

    private func text(from content: Any?) -> String? {
        if let value = content as? String, !value.isEmpty { return value }
        if let parts = content as? [Any] {
            let text = parts.compactMap { part -> String? in
                if let value = part as? String, !value.isEmpty { return value }
                guard let object = part as? [String: Any] else { return nil }
                if let value = object["text"] as? String, !value.isEmpty { return value }
                if let value = object["content"] as? String, !value.isEmpty { return value }
                return nil
            }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private func jsonObjects(from content: String) -> [[String: Any]] {
        content.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
    }

    private func readUTF8(url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func date(from value: Any?) -> Date? {
        if let value = value as? String {
            return ISO8601DateFormatter.claudeMacFractional.date(from: value)
                ?? ISO8601DateFormatter.claudeMac.date(from: value)
        }
        if let value = value as? Int {
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? TimeInterval(value) / 1000 : TimeInterval(value))
        }
        if let value = value as? Double {
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
        }
        return nil
    }

    private func newer(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (.some(let lhs), .some(let rhs)): max(lhs, rhs)
        case (.some(let lhs), .none): lhs
        case (.none, .some(let rhs)): rhs
        case (.none, .none): nil
        }
    }

    private func firstLine(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    private func clippedTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 80 else { return trimmed.isEmpty ? "历史会话" : trimmed }
        return String(trimmed.prefix(80))
    }

    private func normalizedPath(_ value: String) -> String {
        (value as NSString).standardizingPath
    }

    private func storageKey(for projectPath: String) -> String {
        Self.claudeStorageKey(for: normalizedPath(projectPath))
    }

    private static func claudeProjectsRoot() -> URL {
        URL(fileURLWithPath: ChatCLIEnvironment.realHomeDirectory, isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    private static func claudeStorageKey(for projectPath: String) -> String {
        "-" + (projectPath as NSString).standardizingPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).replacingOccurrences(of: "/", with: "-")
    }

    private func projectPath(fromStorageKey storageKey: String) -> String? {
        guard storageKey.hasPrefix("-") else { return nil }
        return "/" + storageKey.dropFirst().replacingOccurrences(of: "-", with: "/")
    }
}

private struct CodexIndexEntry {
    let threadName: String?
    let updatedAt: Date?
}

private extension ISO8601DateFormatter {
    static let claudeMacFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let claudeMac: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
