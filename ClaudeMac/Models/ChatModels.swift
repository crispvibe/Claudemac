import Foundation

struct ChatModelOption: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let cli: CLIType
}

enum ChatModelCatalog {
    static let defaultClaudeModelID = "default"
    static let defaultCodexModelID = "gpt-5"

    static func options(for cli: CLIType) -> [ChatModelOption] {
        switch cli.visibleValue {
        case .claude:
            return [
                ChatModelOption(id: defaultClaudeModelID, title: "默认", cli: .claude),
                ChatModelOption(id: "claude-opus-4-7", title: "Opus 4.7", cli: .claude),
                ChatModelOption(id: "claude-sonnet-4-6", title: "Sonnet 4.6", cli: .claude),
                ChatModelOption(id: "claude-haiku-4-5-20251001", title: "Haiku 4.5", cli: .claude)
            ]
        case .codex:
            return [
                ChatModelOption(id: defaultCodexModelID, title: "GPT-5", cli: .codex),
                ChatModelOption(id: "gpt-5-codex", title: "GPT-5 Codex", cli: .codex),
                ChatModelOption(id: "o4-mini-high", title: "o4-mini-high", cli: .codex)
            ]
        case .gemini, .custom:
            return options(for: .claude)
        }
    }

    static func title(for id: String, cli: CLIType) -> String {
        options(for: cli).first { $0.id == id }?.title ?? id
    }

    static func defaultModelID(for cli: CLIType) -> String {
        cli.visibleValue == .codex ? defaultCodexModelID : defaultClaudeModelID
    }
}

enum ChatPermissionMode: String, CaseIterable, Codable, Identifiable, Equatable {
    case ask
    case autoEdit
    case fullAccess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "询问权限"
        case .autoEdit: "自动编辑"
        case .fullAccess: "完全访问权限"
        }
    }

    var shortTitle: String {
        switch self {
        case .ask: "询问"
        case .autoEdit: "自动"
        case .fullAccess: "完全"
        }
    }

    var claudePermissionMode: String {
        switch self {
        case .ask: "default"
        case .autoEdit: "acceptEdits"
        case .fullAccess: "bypassPermissions"
        }
    }

    var codexApprovalPolicy: String {
        switch self {
        case .ask: "on-request"
        case .autoEdit: "on-failure"
        case .fullAccess: "never"
        }
    }

    var codexSandbox: String {
        switch self {
        case .ask, .autoEdit: "workspaceWrite"
        case .fullAccess: "dangerFullAccess"
        }
    }
}

enum ChatMessageKind: String, Codable, Equatable {
    case user
    case assistant
    case reasoning
    case toolCall
    case toolResult
    case command
    case commandOutput
    case permissionRequest
    case diff
    case error
    case system
    case result
    case rawOutput
}

enum ChatRunStatus: String, Codable, Equatable {
    case idle
    case starting
    case streaming
    case waitingPermission
    case stopping
    case completed
    case failed
    case unsupportedVersion

    var isRunning: Bool {
        switch self {
        case .starting, .streaming, .waitingPermission, .stopping: true
        case .idle, .completed, .failed, .unsupportedVersion: false
        }
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID
    var sessionID: UUID
    var kind: ChatMessageKind
    var title: String
    var subtitle: String
    var text: String
    var status: String
    var createdAt: Date
    var parentUserMessageID: UUID?
    var requestID: String?
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        kind: ChatMessageKind,
        title: String = "",
        subtitle: String = "",
        text: String,
        status: String = "",
        createdAt: Date = Date(),
        parentUserMessageID: UUID? = nil,
        requestID: String? = nil,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.text = text
        self.status = status
        self.createdAt = createdAt
        self.parentUserMessageID = parentUserMessageID
        self.requestID = requestID
        self.isStreaming = isStreaming
    }

    var timestampText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter.string(from: createdAt)
    }

    var diffLines: [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

struct ChatSessionRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var cli: CLIType
    var projectName: String
    var projectPath: String
    var title: String
    var modelID: String
    var permissionMode: ChatPermissionMode
    var externalSessionID: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        cli: CLIType,
        projectName: String,
        projectPath: String,
        title: String,
        modelID: String,
        permissionMode: ChatPermissionMode,
        externalSessionID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.cli = cli.visibleValue
        self.projectName = projectName
        self.projectPath = projectPath
        self.title = title
        self.modelID = modelID
        self.permissionMode = permissionMode
        self.externalSessionID = externalSessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ChatRunOptions: Equatable {
    var cli: CLIType
    var executablePath: String
    var projectPath: String
    var modelID: String
    var permissionMode: ChatPermissionMode
    var sessionMode: SessionMode
    var resumeSessionID: String?
}

enum ChatBackendEvent: Equatable {
    case appendMessage(kind: ChatMessageKind, title: String, subtitle: String, text: String, status: String, requestID: String?)
    case appendDelta(kind: ChatMessageKind, text: String)
    case updateStreamingStatus(String)
    case sessionID(String)
    case permissionRequest(id: String, title: String, text: String)
    case finished
    case failed(String)
}
