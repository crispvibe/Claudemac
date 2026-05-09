import Foundation

enum ChatSessionStore {
    private static let indexFileName = "chat-sessions.json"
    private static let draftsFileName = "chat-drafts.json"
    private static let messagesDirectoryName = "chat-messages"
    static let storageKey = "claudemac"

    static func loadSessions() -> [ChatSessionRecord] {
        guard let data = try? Data(contentsOf: indexURL()) else { return [] }
        return (try? JSONDecoder.chat.decode([ChatSessionRecord].self, from: data)) ?? []
    }

    static func saveSession(_ session: ChatSessionRecord) throws {
        try ensureDirectories()
        var sessions = loadSessions()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
        let data = try JSONEncoder.chat.encode(sessions)
        try data.write(to: indexURL(), options: .atomic)
    }

    static func loadMessages(sessionID: UUID) -> [ChatMessage] {
        let url = messagesURL(for: sessionID)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").compactMap { line in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return try? JSONDecoder.chat.decode(ChatMessage.self, from: data)
        }
    }

    static func saveMessages(_ messages: [ChatMessage], sessionID: UUID) throws {
        try ensureDirectories()
        let encoder = JSONEncoder.chat
        let lines = try messages.map { message -> String in
            let data = try encoder.encode(message)
            return String(data: data, encoding: .utf8) ?? ""
        }
        try lines.joined(separator: "\n").write(to: messagesURL(for: sessionID), atomically: true, encoding: .utf8)
    }

    static func session(id: String) -> ChatSessionRecord? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return loadSessions().first { $0.id == uuid }
    }

    static func deleteSession(id: String) throws {
        guard let uuid = UUID(uuidString: id) else { return }
        var sessions = loadSessions()
        let deletedSession = sessions.first { $0.id == uuid }
        sessions.removeAll { $0.id == uuid }
        try JSONEncoder.chat.encode(sessions).write(to: indexURL(), options: .atomic)
        if let deletedSession {
            try? deleteDraft(for: "history:\(deletedSession.cli.rawValue):\(uuid.uuidString)")
        }
        let url = messagesURL(for: uuid)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func draft(for key: String) -> String {
        loadDrafts()[key] ?? ""
    }

    static func saveDraft(_ text: String, for key: String) throws {
        try ensureDirectories()
        var drafts = loadDrafts()
        if text.isEmpty {
            drafts.removeValue(forKey: key)
        } else {
            drafts[key] = text
        }
        try JSONEncoder.chat.encode(drafts).write(to: draftsURL(), options: .atomic)
    }

    static func deleteDraft(for key: String) throws {
        try saveDraft("", for: key)
    }

    static func historySessions() -> [CLIHistorySession] {
        historySessions(from: loadSessions())
    }

    static func historySessions(from sessions: [ChatSessionRecord]) -> [CLIHistorySession] {
        sessions.map { session in
            CLIHistorySession(
                cli: session.cli,
                sessionId: session.id.uuidString,
                title: session.title,
                projectPath: session.projectPath,
                storageKey: storageKey,
                storagePath: messagesURL(for: session.id).path,
                createdAt: session.createdAt,
                updatedAt: session.updatedAt
            )
        }
    }

    private static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: appSupportURL(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: messagesDirectoryURL(), withIntermediateDirectories: true)
    }

    private static func appSupportURL() -> URL {
        (try? ProjectStore.appSupportDirectory)
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Acode", isDirectory: true)
    }

    private static func loadDrafts() -> [String: String] {
        guard let data = try? Data(contentsOf: draftsURL()) else { return [:] }
        return (try? JSONDecoder.chat.decode([String: String].self, from: data)) ?? [:]
    }

    private static func indexURL() -> URL {
        appSupportURL().appendingPathComponent(indexFileName)
    }

    private static func draftsURL() -> URL {
        appSupportURL().appendingPathComponent(draftsFileName)
    }

    private static func messagesDirectoryURL() -> URL {
        appSupportURL().appendingPathComponent(messagesDirectoryName, isDirectory: true)
    }

    private static func messagesURL(for sessionID: UUID) -> URL {
        messagesDirectoryURL().appendingPathComponent("\(sessionID.uuidString).jsonl")
    }
}

private extension JSONEncoder {
    static var chat: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var chat: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
