import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var projects: [ProjectItem]
    @Published var selectedProjectID: UUID?
    @Published var rootNodes: [FileNode] = []
    @Published var childCache: [String: [FileNode]] = [:]
    @Published var expandedFileTreePaths: Set<String> = []
    @Published var openTabs: [EditorTab] = []
    @Published var selectedTabID: UUID?
    @Published var launchHistory: [LaunchRecord]
    @Published var cliHistory: [CLIHistorySession] = []
    @Published var selectedMode: SessionMode = .newSession
    @Published var selectedCLI: CLIType
    @Published var selectedTerminal: TerminalType
    @Published var resumeSessionId = ""
    @Published var selectedHistoryProjectPath: String?
    @Published var selectedCLIHistoryID: String?
    @Published var chatConversationSerial = UUID()
    @Published var cursorLine = 1
    @Published var cursorColumn = 1
    @Published var errorMessage: String?
    @Published var settings: AppSettings
    @Published var showSettings: Bool = false

    private var scanner: FileTreeScanner

    init() {
        var settings = ProjectStore.loadSettings()
        settings.defaultCLI = settings.defaultCLI.visibleValue
        settings.chatCLI = settings.chatCLI.visibleValue
        self.settings = settings
        self.projects = ProjectStore.loadProjects().sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
        self.launchHistory = LaunchHistoryStore.load().sorted { $0.createdAt > $1.createdAt }
        self.selectedCLI = settings.chatCLI
        self.selectedTerminal = settings.defaultTerminal
        self.scanner = FileTreeScanner(ignoredNames: Set(settings.ignoredFolders))
        self.selectedProjectID = projects.first?.id
        refreshProjectContext()
    }

    var selectedProject: ProjectItem? {
        projects.first { $0.id == selectedProjectID }
    }

    private func project(matching path: String?) -> ProjectItem? {
        guard let normalizedPath = Self.normalizedProjectPath(path) else { return nil }
        return projects.first { Self.normalizedProjectPath($0.path) == normalizedPath }
    }

    nonisolated private static func normalizedProjectPath(_ path: String?) -> String? {
        path?.nonEmptyTrimmed.map { ($0 as NSString).standardizingPath }
    }

    var selectedTab: EditorTab? {
        openTabs.first { $0.id == selectedTabID }
    }

    var breadcrumb: String {
        guard let project = selectedProject else { return "未选择项目" }
        guard let tab = selectedTab else { return project.name }
        return "\(project.name) / \(tab.url.deletingLastPathComponent().lastPathComponent) / \(tab.title)"
    }

    var commandPreview: String {
        guard let projectPath = selectedHistoryProjectPath ?? selectedProject?.path else { return "选择项目后生成命令" }
        let sessionId = resumeSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandBuilder.command(
            projectPath: projectPath,
            cli: selectedCLI,
            mode: selectedMode,
            sessionId: sessionId.isEmpty ? nil : sessionId
        )
    }

    func addProject() {
        guard confirmDiscardUnsavedChangesIfNeeded() else { return }
        do {
            guard let project = try ProjectStore.chooseProjectDirectory() else { return }
            projects.removeAll { $0.path == project.path }
            projects.insert(project, at: 0)
            selectedProjectID = project.id
            try ProjectStore.saveProjects(projects)
            refreshProjectContext()
        } catch {
            show(error)
        }
    }

    func removeProject(_ project: ProjectItem) {
        if selectedProjectID == project.id {
            guard confirmDiscardUnsavedChangesIfNeeded() else { return }
        }
        projects.removeAll { $0.id == project.id }
        if selectedProjectID == project.id {
            selectedProjectID = projects.first?.id
        }
        do {
            try ProjectStore.saveProjects(projects)
            refreshProjectContext()
        } catch {
            show(error)
        }
    }

    @discardableResult
    func selectProject(_ project: ProjectItem) -> Bool {
        guard selectedProjectID != project.id else { return true }
        guard confirmDiscardUnsavedChangesIfNeeded() else { return false }
        selectedProjectID = project.id
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index].lastOpenedAt = Date()
            projects[index].updatedAt = Date()
            try? ProjectStore.saveProjects(projects)
        }
        refreshProjectContext()
        return true
    }

    func refreshProjectContext() {
        rootNodes = []
        childCache = [:]
        expandedFileTreePaths = selectedProject.map { ProjectStore.loadExpandedFileTreePaths(for: $0.path) } ?? []
        selectedHistoryProjectPath = nil
        selectedCLIHistoryID = nil
        selectedMode = .newSession
        resumeSessionId = ""
        openTabs.removeAll()
        selectedTabID = nil
        cursorLine = 1
        cursorColumn = 1
        refreshFileTree()
        openInitialTextFile()
        refreshCLIHistory()
    }

    func refreshFileTree() {
        guard let project = selectedProject else { return }
        do {
            rootNodes = try withProjectAccess(project) { root in
                try scanner.scanChildren(of: root)
            }
        } catch {
            rootNodes = []
        }
    }

    private func openInitialTextFile() {
        guard openTabs.isEmpty, let project = selectedProject else { return }
        do {
            _ = try withProjectAccess(project, operation: { $0 })
        } catch {
            show(error)
            return
        }
        let preferredNames = ["README.md", "README", "readme.md"]
        if let preferred = rootNodes.first(where: { !$0.isDirectory && preferredNames.contains($0.name) }) {
            openFile(preferred)
            return
        }
        let textExtensions: Set<String> = ["md", "swift", "txt", "json", "yaml", "yml", "go", "ts", "js", "py"]
        if let firstTextFile = rootNodes.first(where: { !$0.isDirectory && textExtensions.contains($0.url.pathExtension.lowercased()) }) {
            openFile(firstTextFile)
        }
    }

    func loadChildren(for node: FileNode) {
        guard node.isDirectory, childCache[node.id] == nil, let project = selectedProject else { return }
        do {
            childCache[node.id] = try withProjectAccess(project) { _ in
                try scanner.scanChildren(of: node.url)
            }
        } catch {
            childCache[node.id] = []
            show(error)
        }
    }

    func isFileTreeNodeExpanded(_ node: FileNode) -> Bool {
        expandedFileTreePaths.contains(normalizedFileTreePath(node.url.path))
    }

    func toggleFileTreeNode(_ node: FileNode) {
        guard node.isDirectory, let project = selectedProject else { return }
        let path = normalizedFileTreePath(node.url.path)
        if expandedFileTreePaths.contains(path) {
            expandedFileTreePaths.remove(path)
        } else {
            expandedFileTreePaths.insert(path)
            loadChildren(for: node)
        }
        try? ProjectStore.saveExpandedFileTreePaths(expandedFileTreePaths, for: project.path)
    }

    func restoreExpandedFileTreeNode(_ node: FileNode) {
        guard node.isDirectory, isFileTreeNodeExpanded(node) else { return }
        loadChildren(for: node)
    }

    private func normalizedFileTreePath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    func openFile(_ node: FileNode) {
        guard !node.isDirectory, let project = selectedProject else { return }
        if let existing = openTabs.first(where: { $0.url == node.url }) {
            selectedTabID = existing.id
            return
        }

        do {
            let (text, modifiedAt) = try withProjectAccess(project) { _ in
                let text = try readTextFile(node.url)
                let modifiedAt = (try? node.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                return (text, modifiedAt)
            }
            appendEditorTab(url: node.url, projectId: project.id, text: text, modifiedAt: modifiedAt, isExternal: false)
        } catch {
            show(error)
        }
    }

    func openExternalFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor [weak self] in
                self?.openExternalFileURLs(panel.urls)
            }
        }
    }

    private func openExternalFileURLs(_ urls: [URL]) {
        let projectId = selectedProject?.id ?? UUID()
        for url in urls {
            if let existing = openTabs.first(where: { $0.url == url }) {
                selectedTabID = existing.id
                continue
            }
            do {
                let text = try readTextFile(url)
                let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                appendEditorTab(url: url, projectId: projectId, text: text, modifiedAt: modifiedAt, isExternal: true)
            } catch {
                show(error)
            }
        }
    }

    private func appendEditorTab(url: URL, projectId: UUID, text: String, modifiedAt: Date, isExternal: Bool) {
        let tab = EditorTab(
            id: UUID(),
            projectId: projectId,
            url: url,
            title: url.lastPathComponent,
            text: text,
            savedText: text,
            isDirty: false,
            isExternal: isExternal,
            openedAt: Date(),
            lastActiveAt: Date(),
            modifiedAt: modifiedAt
        )
        openTabs.append(tab)
        selectedTabID = tab.id
    }

    func selectTab(_ tab: EditorTab) {
        selectedTabID = tab.id
        if let index = openTabs.firstIndex(where: { $0.id == tab.id }) {
            openTabs[index].lastActiveAt = Date()
        }
    }

    func closeTab(_ tab: EditorTab) {
        guard let index = openTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        guard confirmDiscardUnsavedTabsIfNeeded([tab]) else { return }
        openTabs.remove(at: index)
        if selectedTabID == tab.id {
            selectedTabID = openTabs.indices.contains(index) ? openTabs[index].id : openTabs.last?.id
        }
    }

    func updateText(tabID: UUID, text: String) {
        guard let index = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        openTabs[index].text = text
        openTabs[index].isDirty = text != openTabs[index].savedText
    }

    func saveSelectedTab() {
        guard let id = selectedTabID else { return }
        saveTab(id: id)
    }

    @discardableResult
    func saveTab(id: UUID) -> Bool {
        guard let index = openTabs.firstIndex(where: { $0.id == id }) else { return false }
        return saveTab(at: index)
    }

    @discardableResult
    private func saveTab(at index: Int) -> Bool {
        do {
            let tab = openTabs[index]
            if tab.isExternal {
                let didStart = tab.url.startAccessingSecurityScopedResource()
                defer {
                    if didStart { tab.url.stopAccessingSecurityScopedResource() }
                }
                try tab.text.write(to: tab.url, atomically: true, encoding: .utf8)
            } else if let project = selectedProject {
                try withProjectAccess(project) { _ in
                    try tab.text.write(to: tab.url, atomically: true, encoding: .utf8)
                }
            } else {
                throw AppStateError.missingProjectForSave
            }
            openTabs[index].savedText = tab.text
            openTabs[index].isDirty = false
            openTabs[index].modifiedAt = (try? tab.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            return true
        } catch {
            show(error)
            return false
        }
    }

    func setMode(_ mode: SessionMode) {
        selectedMode = mode
        if mode != .resume {
            selectedHistoryProjectPath = nil
        }
    }

    func selectLaunchRecord(_ record: LaunchRecord) {
        selectedCLI = record.cliType.visibleValue
        selectedTerminal = record.terminal
        selectedMode = record.mode
        resumeSessionId = record.sessionId ?? ""
        selectedHistoryProjectPath = record.mode == .resume ? record.projectPath : nil
    }

    func startNewChat(for project: ProjectItem? = nil) {
        if let project, selectedProjectID != project.id {
            guard selectProject(project) else { return }
        }
        selectedHistoryProjectPath = nil
        selectedCLIHistoryID = nil
        selectedMode = .newSession
        resumeSessionId = ""
        chatConversationSerial = UUID()
    }

    func selectCLIHistory(_ session: CLIHistorySession) {
        let matchingProject = project(matching: session.projectPath)
        if selectedProjectID != matchingProject?.id {
            guard confirmDiscardUnsavedChangesIfNeeded() else { return }
            selectedProjectID = matchingProject?.id
            if let matchingProject, let index = projects.firstIndex(where: { $0.id == matchingProject.id }) {
                projects[index].lastOpenedAt = Date()
                projects[index].updatedAt = Date()
                try? ProjectStore.saveProjects(projects)
            }
            refreshProjectContext()
        }
        selectedCLI = session.cli.visibleValue
        selectedMode = .resume
        resumeSessionId = session.sessionId
        selectedHistoryProjectPath = session.projectPath
        selectedCLIHistoryID = session.id
        chatConversationSerial = UUID()
    }

    func deleteCLIHistory(_ session: CLIHistorySession) {
        cliHistory.removeAll { $0.id == session.id }
        if selectedCLIHistoryID == session.id {
            startNewChat()
        }

        guard let storagePath = session.storagePath else { return }
        let shouldScanExternalHistory = settings.enableClaudeHistoryScan
        Task { [weak self] in
            do {
                let history = try await Task.detached(priority: .utility) { () throws -> [CLIHistorySession] in
                    try Self.deleteCLIHistoryFiles(session: session, storagePath: storagePath)
                    return Self.loadCLIHistory(enableClaudeHistoryScan: shouldScanExternalHistory)
                }.value
                guard let self else { return }
                self.cliHistory = history
            } catch {
                guard let self else { return }
                self.show(error)
                self.refreshCLIHistory()
            }
        }
    }

    nonisolated private static func deleteCLIHistoryFiles(session: CLIHistorySession, storagePath: String) throws {
        if session.storageKey == ChatSessionStore.storageKey {
            try ChatSessionStore.deleteSession(id: session.sessionId)
            return
        }

        let url = URL(fileURLWithPath: storagePath)
        if url.lastPathComponent == "history.jsonl" {
            try removeHistoryIndexEntries(from: url, matching: session)
        } else {
            try FileManager.default.removeItem(at: url)
        }
    }

    nonisolated private static func removeHistoryIndexEntries(from url: URL, matching session: CLIHistorySession) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        let keptLines = content.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            guard !line.isEmpty, let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return true
            }
            return (object["sessionId"] as? String) != session.sessionId && (object["session_id"] as? String) != session.sessionId
        }
        try keptLines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    nonisolated private static func loadCLIHistory(enableClaudeHistoryScan: Bool) -> [CLIHistorySession] {
        let local = ChatSessionStore.historySessions()
        guard enableClaudeHistoryScan else { return local }
        let external = CLIHistoryScanner().scan(projectPath: nil)
        return (local + external).sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commandPreview, forType: .string)
    }

    func openTerminal() {
        guard let projectPath = selectedHistoryProjectPath ?? selectedProject?.path else {
            errorMessage = "请先添加并选择项目。"
            return
        }
        let projectId = selectedProject?.id ?? UUID()
        let projectName = selectedProject?.name ?? URL(fileURLWithPath: projectPath).lastPathComponent
        let command = commandPreview
        let cli = selectedCLI
        let mode = selectedMode
        let sessionId = resumeSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        let terminal = selectedTerminal

        Task {
            do {
                try await TerminalLauncher.launch(command: command, terminal: terminal)
                let now = Date()
                let record = LaunchRecord(
                    id: UUID(),
                    projectId: projectId,
                    projectName: projectName,
                    projectPath: projectPath,
                    cliType: cli,
                    mode: mode,
                    sessionId: sessionId.isEmpty ? nil : sessionId,
                    title: mode.title,
                    command: command,
                    terminal: terminal,
                    source: "本地",
                    createdAt: now,
                    launchedAt: now
                )
                launchHistory.insert(record, at: 0)
                try LaunchHistoryStore.save(launchHistory)
            } catch {
                show(error)
            }
        }
    }

    func refreshCLIHistory() {
        let local = ChatSessionStore.historySessions()
        cliHistory = local
        guard settings.enableClaudeHistoryScan else { return }

        Task { [weak self] in
            let history = await Task.detached(priority: .utility) {
                Self.loadCLIHistory(enableClaudeHistoryScan: true)
            }.value
            guard let self else { return }
            self.cliHistory = history
        }
    }

    func saveSettings(
        defaultCLI: CLIType,
        defaultTerminal: TerminalType,
        showCommandPreview: Bool,
        enableClaudeHistoryScan: Bool,
        ignoredFolders: [String]
    ) {
        settings = AppSettings(
            defaultTerminal: defaultTerminal,
            defaultCLI: defaultCLI,
            chatCLI: settings.chatCLI,
            chatPermissionMode: settings.chatPermissionMode,
            selectedClaudeModelID: settings.selectedClaudeModelID,
            selectedCodexModelID: settings.selectedCodexModelID,
            showCommandPreview: showCommandPreview,
            ignoredFolders: ignoredFolders,
            enableClaudeHistoryScan: enableClaudeHistoryScan,
            apiBaseURL: settings.apiBaseURL,
            apiKey: settings.apiKey
        )
        selectedTerminal = defaultTerminal
        scanner = FileTreeScanner(ignoredNames: Set(ignoredFolders))
        do {
            try ProjectStore.saveSettings(settings)
            refreshFileTree()
            refreshCLIHistory()
        } catch {
            show(error)
        }
    }

    func saveChatSelection(cli: CLIType, permissionMode: ChatPermissionMode, modelID: String) {
        let cli = cli.visibleValue
        settings.chatCLI = cli
        settings.chatPermissionMode = permissionMode
        if cli == .codex {
            settings.selectedCodexModelID = modelID
        } else {
            settings.selectedClaudeModelID = modelID
        }
        selectedCLI = cli
        do {
            try ProjectStore.saveSettings(settings)
        } catch {
            show(error)
        }
    }

    func bindingForTabText(_ id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.openTabs.first(where: { $0.id == id })?.text ?? "" },
            set: { [weak self] newValue in self?.updateText(tabID: id, text: newValue) }
        )
    }

    private func readTextFile(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = values.fileSize ?? 0
        if size > 5 * 1024 * 1024 {
            throw AppStateError.fileTooLarge
        }

        let data = try Data(contentsOf: url)
        if data.prefix(4096).contains(0) {
            throw AppStateError.binaryFile
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw AppStateError.unsupportedEncoding
        }
        return text
    }

    private func withProjectAccess<T>(_ project: ProjectItem, operation: (URL) throws -> T) throws -> T {
        let url = try ProjectStore.resolveURL(for: project)
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        return try operation(url)
    }

    private func confirmDiscardUnsavedChangesIfNeeded() -> Bool {
        confirmDiscardUnsavedTabsIfNeeded(openTabs)
    }

    private func confirmDiscardUnsavedTabsIfNeeded(_ tabs: [EditorTab]) -> Bool {
        let dirtyTabs = tabs.filter(\.isDirty)
        guard !dirtyTabs.isEmpty else { return true }

        let alert = NSAlert()
        alert.messageText = dirtyTabs.count == 1 ? "保存对“\(dirtyTabs[0].title)”的修改？" : "保存 \(dirtyTabs.count) 个已修改文件？"
        alert.informativeText = "不保存会丢失当前编辑内容。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "放弃")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return dirtyTabs.allSatisfy { tab in
                guard let index = openTabs.firstIndex(where: { $0.id == tab.id }) else { return true }
                return saveTab(at: index)
            }
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func show(_ error: Error) {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            errorMessage = description
        } else {
            errorMessage = "操作失败：\(error.localizedDescription)"
        }
    }
}

private enum AppStateError: LocalizedError {
    case fileTooLarge
    case binaryFile
    case unsupportedEncoding
    case missingProjectForSave

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: "文件过大，暂不支持打开超过 5 MB 的文件。"
        case .binaryFile: "这是二进制文件，暂不支持在编辑器中打开。"
        case .unsupportedEncoding: "文件编码不是 UTF-8，暂不支持打开。"
        case .missingProjectForSave: "当前文件不在已授权项目中，无法保存。"
        }
    }
}
