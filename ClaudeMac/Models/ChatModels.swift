import Foundation

struct ChatModelOption: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let cli: CLIType
}

enum ChatModelCatalog {
    static let defaultClaudeModelID = "default"
    static let defaultCodexModelID = "gpt-5.3-codex"

    static func options(for cli: CLIType) -> [ChatModelOption] {
        switch cli.visibleValue {
        case .claude:
            return [
                ChatModelOption(id: defaultClaudeModelID, title: "默认", cli: .claude),
                ChatModelOption(id: "claude-opus-4-7", title: "Opus 4.7 1M", cli: .claude),
                ChatModelOption(id: "claude-opus-4-6", title: "Opus 4.6", cli: .claude),
                ChatModelOption(id: "claude-sonnet-4-6", title: "Sonnet 4.6", cli: .claude),
                ChatModelOption(id: "claude-haiku-4-5", title: "Haiku 4.5", cli: .claude)
            ]
        case .codex:
            return [
                ChatModelOption(id: "gpt-5.5", title: "GPT-5.5", cli: .codex),
                ChatModelOption(id: defaultCodexModelID, title: "GPT-5.3 Codex", cli: .codex),
                ChatModelOption(id: "gpt-5.4", title: "GPT-5.4", cli: .codex),
                ChatModelOption(id: "gpt-5.2-codex", title: "GPT-5.2 Codex", cli: .codex),
                ChatModelOption(id: "gpt-5.2", title: "GPT-5.2", cli: .codex),
                ChatModelOption(id: "gpt-5.1-codex-mini", title: "GPT-5.1 Codex Mini", cli: .codex)
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

    static func executionModelID(for id: String) -> String {
        id.replacingOccurrences(of: "[1m]", with: "")
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
        case .ask, .autoEdit: "workspace-write"
        case .fullAccess: "danger-full-access"
        }
    }
}

enum ChatReasoningEffort: String, CaseIterable, Codable, Identifiable, Equatable {
    case low
    case medium
    case high
    case xhigh
    case max

    var id: String { rawValue }

    static func options(for cli: CLIType) -> [ChatReasoningEffort] {
        switch cli.visibleValue {
        case .claude:
            return [.low, .medium, .high, .xhigh, .max]
        case .codex:
            return [.low, .medium, .high, .xhigh]
        case .gemini, .custom:
            return [.low, .medium, .high, .xhigh]
        }
    }

    func title(for cli: CLIType) -> String {
        switch cli.visibleValue {
        case .claude:
            return rawValue
        case .codex, .gemini, .custom:
            switch self {
            case .low: return "低"
            case .medium: return "中"
            case .high: return "高"
            case .xhigh: return "超高"
            case .max: return "最高"
            }
        }
    }

    func menuTitle(for cli: CLIType) -> String {
        title(for: cli)
    }

    var claudeArgument: String {
        rawValue
    }

    var codexConfigValue: String {
        self == .max ? ChatReasoningEffort.xhigh.rawValue : rawValue
    }
}

enum ChatPermissionDecision: String, Codable, Equatable {
    case deny
    case allow
    case allowForSession

    var isAllowed: Bool {
        switch self {
        case .deny: false
        case .allow, .allowForSession: true
        }
    }

    var statusText: String {
        switch self {
        case .deny: "denied"
        case .allow: "allowed"
        case .allowForSession: "session allowed"
        }
    }

    var displayText: String {
        switch self {
        case .deny: "已拒绝"
        case .allow: "已允许"
        case .allowForSession: "本会话已允许"
        }
    }
}

enum ChatMessageKind: String, Codable, Equatable, Hashable {
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
    var reasoningEffort: ChatReasoningEffort
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
        reasoningEffort: ChatReasoningEffort = .high,
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
        self.reasoningEffort = reasoningEffort
        self.externalSessionID = externalSessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case cli
        case projectName
        case projectPath
        case title
        case modelID
        case permissionMode
        case reasoningEffort
        case externalSessionID
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        cli = try container.decode(CLIType.self, forKey: .cli)
        projectName = try container.decode(String.self, forKey: .projectName)
        projectPath = try container.decode(String.self, forKey: .projectPath)
        title = try container.decode(String.self, forKey: .title)
        modelID = try container.decode(String.self, forKey: .modelID)
        permissionMode = try container.decode(ChatPermissionMode.self, forKey: .permissionMode)
        reasoningEffort = try container.decodeIfPresent(ChatReasoningEffort.self, forKey: .reasoningEffort) ?? .high
        externalSessionID = try container.decodeIfPresent(String.self, forKey: .externalSessionID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(cli, forKey: .cli)
        try container.encode(projectName, forKey: .projectName)
        try container.encode(projectPath, forKey: .projectPath)
        try container.encode(title, forKey: .title)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(permissionMode, forKey: .permissionMode)
        try container.encode(reasoningEffort, forKey: .reasoningEffort)
        try container.encodeIfPresent(externalSessionID, forKey: .externalSessionID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct ChatRunOptions: Equatable {
    var cli: CLIType
    var executablePath: String
    var projectPath: String
    var modelID: String
    var permissionMode: ChatPermissionMode
    var reasoningEffort: ChatReasoningEffort
    var sessionMode: SessionMode
    var resumeSessionID: String?
}

enum ChatBackendEvent: Equatable {
    case appendMessage(kind: ChatMessageKind, title: String, subtitle: String, text: String, status: String, requestID: String?)
    case appendDelta(kind: ChatMessageKind, title: String, subtitle: String, text: String, status: String, requestID: String?)
    case updateStreamingStatus(String)
    case sessionID(String)
    case permissionRequest(id: String, title: String, text: String)
    case tokenUsage(used: Int, total: Int)
    case finished
    case failed(String)
}
