import Foundation

enum ChatSessionStore {
    private static let appDirectoryName = "ClaudeMac"
    private static let indexFileName = "chat-sessions.json"
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

    static func deleteSession(id: String) throws {
        guard let uuid = UUID(uuidString: id) else { return }
        var sessions = loadSessions()
        sessions.removeAll { $0.id == uuid }
        try JSONEncoder.chat.encode(sessions).write(to: indexURL(), options: .atomic)
        let url = messagesURL(for: uuid)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func historySessions() -> [CLIHistorySession] {
        loadSessions().map { session in
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
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appDirectoryName, isDirectory: true)
    }

    private static func indexURL() -> URL {
        appSupportURL().appendingPathComponent(indexFileName)
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
