import Foundation

enum CLIType: String, CaseIterable, Codable, Identifiable {
    case claude
    case codex
    case gemini
    case custom

    static let visibleCases: [CLIType] = [.claude, .codex]

    var id: String { rawValue }

    var visibleValue: CLIType {
        switch self {
        case .claude, .codex: self
        case .gemini, .custom: .claude
        }
    }

    var displayName: String {
        switch visibleValue {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini, .custom: "Claude Code"
        }
    }

    var executable: String {
        switch visibleValue {
        case .claude: "claude"
        case .codex: "codex"
        case .gemini, .custom: "claude"
        }
    }
}

enum TerminalType: String, CaseIterable, Codable, Identifiable {
    case terminal
    case iTerm2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: "终端"
        case .iTerm2: "iTerm2"
        }
    }
}

enum SessionMode: String, CaseIterable, Codable, Identifiable {
    case newSession
    case continueLast
    case resume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newSession: "新建会话"
        case .continueLast: "继续上次"
        case .resume: "恢复历史"
        }
    }

    var shortTitle: String {
        switch self {
        case .newSession: "新建"
        case .continueLast: "继续"
        case .resume: "恢复"
        }
    }
}

struct ProjectItem: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var path: String
    var bookmarkData: Data
    var defaultCLI: CLIType
    var defaultTerminal: TerminalType
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
}

struct FileNode: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool

    var id: String { url.path }
}

struct EditorTab: Identifiable, Equatable {
    var id: UUID
    var projectId: UUID
    var url: URL
    var title: String
    var text: String
    var savedText: String
    var isDirty: Bool
    var isExternal: Bool
    var openedAt: Date
    var lastActiveAt: Date
    var modifiedAt: Date
}

struct LaunchRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var projectId: UUID
    var projectName: String
    var projectPath: String
    var cliType: CLIType
    var mode: SessionMode
    var sessionId: String?
    var title: String
    var command: String
    var terminal: TerminalType
    var source: String
    var createdAt: Date
    var launchedAt: Date?
}

struct CLIHistorySession: Identifiable, Equatable {
    var id: String { "\(cli.rawValue):\(sessionId)" }
    let cli: CLIType
    let sessionId: String
    let title: String
    let projectPath: String?
    let storageKey: String?
    let storagePath: String?
    let createdAt: Date?
    let updatedAt: Date?

    var sourceLabel: String {
        "\(cli.displayName) 历史"
    }

    var relativeUpdatedText: String {
        guard let updatedAt else { return "" }
        let interval = Date().timeIntervalSince(updatedAt)
        if interval < 60 * 60 { return "刚刚" }
        if interval < 60 * 60 * 24 { return "\(max(1, Int(interval / 3600))) 时" }
        if interval < 60 * 60 * 24 * 30 { return "\(max(1, Int(interval / 86400))) 天" }
        return "\(max(1, Int(interval / 2_592_000))) 月"
    }
}

struct AppSettings: Codable, Equatable {
    var defaultTerminal: TerminalType
    var defaultCLI: CLIType
    var chatCLI: CLIType
    var chatPermissionMode: ChatPermissionMode
    var selectedClaudeModelID: String
    var selectedCodexModelID: String
    var showCommandPreview: Bool
    var ignoredFolders: [String]
    var enableClaudeHistoryScan: Bool
    var apiBaseURL: String
    var apiKey: String
    var lastSelectedProjectPath: String?
    var lastSelectedCLIHistoryID: String?

    static let `default` = AppSettings(
        defaultTerminal: .terminal,
        defaultCLI: .claude,
        chatCLI: .claude,
        chatPermissionMode: .ask,
        selectedClaudeModelID: ChatModelCatalog.defaultClaudeModelID,
        selectedCodexModelID: ChatModelCatalog.defaultCodexModelID,
        showCommandPreview: true,
        ignoredFolders: FileTreeScanner.defaultIgnoredNames.sorted(),
        enableClaudeHistoryScan: true,
        apiBaseURL: "",
        apiKey: "",
        lastSelectedProjectPath: nil,
        lastSelectedCLIHistoryID: nil
    )

    init(
        defaultTerminal: TerminalType,
        defaultCLI: CLIType,
        chatCLI: CLIType,
        chatPermissionMode: ChatPermissionMode,
        selectedClaudeModelID: String,
        selectedCodexModelID: String,
        showCommandPreview: Bool,
        ignoredFolders: [String],
        enableClaudeHistoryScan: Bool,
        apiBaseURL: String,
        apiKey: String,
        lastSelectedProjectPath: String?,
        lastSelectedCLIHistoryID: String?
    ) {
        self.defaultTerminal = defaultTerminal
        self.defaultCLI = defaultCLI
        self.chatCLI = chatCLI.visibleValue
        self.chatPermissionMode = chatPermissionMode
        self.selectedClaudeModelID = selectedClaudeModelID
        self.selectedCodexModelID = selectedCodexModelID
        self.showCommandPreview = showCommandPreview
        self.ignoredFolders = ignoredFolders
        self.enableClaudeHistoryScan = enableClaudeHistoryScan
        self.apiBaseURL = apiBaseURL
        self.apiKey = apiKey
        self.lastSelectedProjectPath = lastSelectedProjectPath
        self.lastSelectedCLIHistoryID = lastSelectedCLIHistoryID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        defaultTerminal = try values.decodeIfPresent(TerminalType.self, forKey: .defaultTerminal) ?? .terminal
        defaultCLI = try values.decodeIfPresent(CLIType.self, forKey: .defaultCLI) ?? .claude
        chatCLI = (try values.decodeIfPresent(CLIType.self, forKey: .chatCLI) ?? defaultCLI).visibleValue
        chatPermissionMode = try values.decodeIfPresent(ChatPermissionMode.self, forKey: .chatPermissionMode) ?? .ask
        selectedClaudeModelID = try values.decodeIfPresent(String.self, forKey: .selectedClaudeModelID) ?? ChatModelCatalog.defaultClaudeModelID
        selectedCodexModelID = try values.decodeIfPresent(String.self, forKey: .selectedCodexModelID) ?? ChatModelCatalog.defaultCodexModelID
        showCommandPreview = try values.decodeIfPresent(Bool.self, forKey: .showCommandPreview) ?? true
        ignoredFolders = try values.decodeIfPresent([String].self, forKey: .ignoredFolders) ?? FileTreeScanner.defaultIgnoredNames.sorted()
        enableClaudeHistoryScan = try values.decodeIfPresent(Bool.self, forKey: .enableClaudeHistoryScan) ?? true
        apiBaseURL = try values.decodeIfPresent(String.self, forKey: .apiBaseURL) ?? ""
        apiKey = try values.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        lastSelectedProjectPath = try values.decodeIfPresent(String.self, forKey: .lastSelectedProjectPath)
        lastSelectedCLIHistoryID = try values.decodeIfPresent(String.self, forKey: .lastSelectedCLIHistoryID)
    }
}

struct ClaudeRelayProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var baseURL: String
    var authToken: String
    var model: String
    var haikuModel: String
    var sonnetModel: String
    var opusModel: String
    var httpProxy: String
    var httpsProxy: String
    var createdAt: Date
    var updatedAt: Date
}

struct CodexConfigProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var authMode: String
    var model: String
    var baseURL: String
    var apiKey: String
    var wireApi: String
    var createdAt: Date
    var updatedAt: Date
}

struct ConfigProfileCollection: Codable, Equatable {
    var activeClaudeRelayProfileID: UUID?
    var activeCodexProfileID: UUID?
    var claudeRelayProfiles: [ClaudeRelayProfile]
    var codexProfiles: [CodexConfigProfile]

    static let empty = ConfigProfileCollection(
        activeClaudeRelayProfileID: nil,
        activeCodexProfileID: nil,
        claudeRelayProfiles: [],
        codexProfiles: []
    )
}
