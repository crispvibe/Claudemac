import Foundation

@MainActor
final class ChatPanelState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var status: ChatRunStatus = .idle
    @Published var capabilities: [CLIType: ChatCLICapability] = [:]
    @Published var statusText = "就绪"
    @Published var tokensUsed: Int = 0
    @Published var tokensTotal: Int = 200_000

    private static let compactThreshold: Double = 0.90
    private var didAutoCompact = false

    static func defaultContextWindow(for modelID: String) -> Int {
        if isMillionContextModel(modelID) {
            return 1_000_000
        }
        return 200_000
    }

    static func isMillionContextModel(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        let executionID = ChatModelCatalog.executionModelID(for: lower)
        return executionID == "claude-opus-4-7"
            || lower.contains("gpt-5.5")
            || lower.contains("gpt5.5")
            || lower.contains("[1m]")
            || lower.contains("1m")
            || lower.contains("1000k")
    }

    private var currentSession: ChatSessionRecord?
    private var currentTask: Task<Void, Never>?
    private var activeBackend: ChatProcessBackend?
    private var isUserStopping = false
    private var activeAssistantMessageID: UUID?
    private var activeStreamingMessageIDs: [ChatMessageKind: UUID] = [:]
    private var activeParentUserMessageID: UUID?

    init() {
        refreshCapabilities()
    }

    func refreshCapabilities() {
        Task {
            let result = await ChatCLICapabilityProbe.probeAll()
            capabilities = result
        }
    }

    func syncContextWindow(modelID: String) {
        tokensTotal = Self.defaultContextWindow(for: modelID)
        didAutoCompact = false
    }

    func loadFromAppState(
        _ appState: AppState,
        modelID: String,
        permissionMode: ChatPermissionMode,
        reasoningEffort: ChatReasoningEffort
    ) {
        interruptIfNeededForLoad()
        activeAssistantMessageID = nil
        activeStreamingMessageIDs.removeAll()
        activeParentUserMessageID = nil
        isUserStopping = false

        guard let historyID = appState.selectedCLIHistoryID,
              let history = appState.cliHistory.first(where: { $0.id == historyID }) else {
            currentSession = nil
            messages = []
            status = .idle
            statusText = "新会话"
            return
        }

        if history.storageKey == ChatSessionStore.storageKey, let uuid = UUID(uuidString: history.sessionId) {
            let sessions = ChatSessionStore.loadSessions()
            currentSession = sessions.first { $0.id == uuid }
            messages = ChatSessionStore.loadMessages(sessionID: uuid)
            status = .idle
            statusText = "已加载本地会话"
            return
        }

        let projectName = appState.selectedProject?.name ?? URL(fileURLWithPath: history.projectPath ?? "").lastPathComponent
        currentSession = ChatSessionRecord(
            cli: history.cli,
            projectName: projectName,
            projectPath: history.projectPath ?? appState.selectedProject?.path ?? "",
            title: history.title,
            modelID: modelID,
            permissionMode: permissionMode,
            reasoningEffort: reasoningEffort,
            externalSessionID: history.sessionId,
            createdAt: history.createdAt ?? Date(),
            updatedAt: history.updatedAt ?? Date()
        )
        messages = [
            ChatMessage(
                sessionID: currentSession?.id ?? UUID(),
                kind: .system,
                title: history.cli.displayName,
                subtitle: history.sessionId,
                text: "已打开外部历史会话。发送新消息时会尝试通过 CLI resume 继续该会话。",
                status: "resume"
            )
        ]
        status = .idle
        statusText = "历史会话"
    }

    func send(
        text rawText: String,
        project: ProjectItem?,
        cli: CLIType,
        modelID: String,
        contextModelID: String? = nil,
        permissionMode: ChatPermissionMode,
        reasoningEffort: ChatReasoningEffort,
        sessionMode: SessionMode,
        resumeSessionID: String?
    ) {
        if status.isRunning {
            interrupt()
            return
        }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let project else {
            appendError("请先选择项目。")
            return
        }

        let visibleCLI = cli.visibleValue
        guard let capability = capabilities[visibleCLI] else {
            appendError("正在检测 \(visibleCLI.displayName)，请稍后重试。")
            refreshCapabilities()
            return
        }
        guard let executable = capability.executablePath, capability.errorMessage == nil else {
            status = .unsupportedVersion
            appendError(capability.errorMessage ?? "\(visibleCLI.displayName) 不可用。")
            return
        }
        if visibleCLI == .codex, !capability.supportsAppServer {
            status = .unsupportedVersion
            appendError("当前 Codex 版本不支持 app-server，无法在内嵌对话中启动。")
            return
        }

        let effectiveContextModelID = contextModelID?.nonEmptyTrimmed ?? modelID
        var session = ensureSession(
            project: project,
            cli: visibleCLI,
            modelID: effectiveContextModelID,
            permissionMode: permissionMode,
            reasoningEffort: reasoningEffort,
            firstPrompt: text
        )
        session.cli = visibleCLI
        session.modelID = effectiveContextModelID
        session.permissionMode = permissionMode
        session.reasoningEffort = reasoningEffort
        session.updatedAt = Date()
        currentSession = session

        tokensTotal = Self.defaultContextWindow(for: effectiveContextModelID)
        didAutoCompact = false

        let userMessage = ChatMessage(sessionID: session.id, kind: .user, text: text, status: "user")
        activeParentUserMessageID = userMessage.id
        activeAssistantMessageID = nil
        activeStreamingMessageIDs.removeAll()
        messages.append(userMessage)
        persistCurrentSession()

        let options = ChatRunOptions(
            cli: visibleCLI,
            executablePath: executable,
            projectPath: project.path,
            modelID: modelID,
            permissionMode: permissionMode,
            reasoningEffort: reasoningEffort,
            sessionMode: sessionMode,
            resumeSessionID: effectiveResumeSessionID(resumeSessionID, for: session)
        )
        let backend: ChatProcessBackend = visibleCLI == .codex ? CodexAppServerBackend() : ClaudeCodeProcessBackend()
        activeBackend = backend
        isUserStopping = false
        status = .starting
        statusText = "启动 \(visibleCLI.displayName)"

        currentTask = Task { [weak self] in
            guard let self else { return }
            let scopedURL: URL
            let didStartAccessing: Bool
            do {
                scopedURL = try ProjectStore.resolveURL(for: project)
                didStartAccessing = scopedURL.startAccessingSecurityScopedResource()
            } catch {
                await MainActor.run {
                    self.appendError(error.localizedDescription)
                    self.status = .failed
                    self.statusText = "项目权限失效"
                    self.persistCurrentSession()
                }
                return
            }
            defer {
                if didStartAccessing {
                    scopedURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                for try await event in backend.start(prompt: text, options: options, session: session) {
                    await MainActor.run {
                        self.apply(event)
                    }
                }
            } catch {
                await MainActor.run {
                    self.appendError(error.localizedDescription)
                    self.status = .failed
                    self.statusText = "失败"
                    self.finishStreamingMessages()
                    self.persistCurrentSession()
                }
            }
        }
    }

    func removeMessageThread(_ id: UUID) {
        messages.removeAll { $0.id == id || $0.parentUserMessageID == id }
        activeStreamingMessageIDs = activeStreamingMessageIDs.filter { $0.value != id }
        if activeAssistantMessageID == id {
            activeAssistantMessageID = nil
        }
        if activeParentUserMessageID == id {
            activeParentUserMessageID = nil
            activeAssistantMessageID = nil
            activeStreamingMessageIDs.removeAll()
        }
        persistCurrentSession()
    }

    func interrupt() {
        guard status.isRunning else { return }
        isUserStopping = true
        status = .stopping
        statusText = "正在停止"
        activeBackend?.interrupt()
        finishStreamingMessages(status: "stopped")
        persistCurrentSession()
    }

    func respondToPermission(requestID: String, allowed: Bool) {
        respondToPermission(requestID: requestID, decision: allowed ? .allow : .deny)
    }

    func respondToPermission(requestID: String, decision: ChatPermissionDecision) {
        activeBackend?.respondToPermission(requestID: requestID, decision: decision)
        if let index = messages.firstIndex(where: { $0.requestID == requestID }) {
            messages[index].status = decision.statusText
        }
        status = .streaming
        statusText = decision.displayText
        persistCurrentSession()
    }

    private func interruptIfNeededForLoad() {
        if status.isRunning { interrupt() }
    }

    private func effectiveResumeSessionID(_ resumeSessionID: String?, for session: ChatSessionRecord) -> String? {
        guard let resumeSessionID = resumeSessionID?.nonEmptyTrimmed else { return nil }
        return resumeSessionID.caseInsensitiveCompare(session.id.uuidString) == .orderedSame ? nil : resumeSessionID
    }

    private func ensureSession(
        project: ProjectItem,
        cli: CLIType,
        modelID: String,
        permissionMode: ChatPermissionMode,
        reasoningEffort: ChatReasoningEffort,
        firstPrompt: String
    ) -> ChatSessionRecord {
        if var currentSession, currentSession.projectPath == project.path, currentSession.cli == cli.visibleValue {
            currentSession.updatedAt = Date()
            return currentSession
        }
        return ChatSessionRecord(
            cli: cli,
            projectName: project.name,
            projectPath: project.path,
            title: title(from: firstPrompt),
            modelID: modelID,
            permissionMode: permissionMode,
            reasoningEffort: reasoningEffort
        )
    }

    private func apply(_ event: ChatBackendEvent) {
        switch event {
        case .appendMessage(let kind, let title, let subtitle, let text, let itemStatus, let requestID):
            guard let sessionID = currentSession?.id else { return }
            let message = ChatMessage(
                sessionID: sessionID,
                kind: kind,
                title: title,
                subtitle: subtitle,
                text: text,
                status: itemStatus,
                parentUserMessageID: activeParentUserMessageID,
                requestID: requestID,
                isStreaming: status.isRunning
            )
            messages.append(message)
            if itemStatus == "streaming" {
                activeStreamingMessageIDs[kind] = message.id
                if kind == .assistant {
                    activeAssistantMessageID = message.id
                }
            }
            if kind != .system && kind != .command { status = .streaming }
            statusText = itemStatus
        case .appendDelta(let kind, let text):
            appendDelta(kind: kind, text: text)
            status = .streaming
            statusText = "streaming"
        case .updateStreamingStatus(let value):
            statusText = value
        case .sessionID(let externalID):
            currentSession?.externalSessionID = externalID
        case .permissionRequest(let id, let title, let text):
            guard let sessionID = currentSession?.id else { return }
            messages.append(ChatMessage(
                sessionID: sessionID,
                kind: .permissionRequest,
                title: title,
                text: text,
                status: "waiting",
                parentUserMessageID: activeParentUserMessageID,
                requestID: id
            ))
            status = .waitingPermission
            statusText = "等待权限"
        case .tokenUsage(let used, let total):
            tokensUsed = used
            if total > 0 {
                let modelID = currentSession?.modelID ?? ""
                tokensTotal = Self.isMillionContextModel(modelID)
                    ? max(total, Self.defaultContextWindow(for: modelID))
                    : total
            }
            checkAutoCompact()
        case .finished:
            finishStreamingMessages(status: isUserStopping ? "stopped" : "done")
            currentSession?.updatedAt = Date()
            status = .completed
            statusText = isUserStopping ? "已停止" : "完成"
            isUserStopping = false
            persistCurrentSession()
        case .failed(let message):
            if isUserStopping {
                finishStreamingMessages(status: "stopped")
                currentSession?.updatedAt = Date()
                status = .completed
                statusText = "已停止"
                isUserStopping = false
                persistCurrentSession()
                return
            }
            finishStreamingMessages(status: "failed")
            appendError(message)
            currentSession?.updatedAt = Date()
            status = .failed
            statusText = "失败"
            persistCurrentSession()
        }
    }

    private func appendDelta(kind: ChatMessageKind, text: String) {
        guard !text.isEmpty, let sessionID = currentSession?.id else { return }
        if let activeMessageID = activeStreamingMessageIDs[kind],
           let index = messages.firstIndex(where: { $0.id == activeMessageID }) {
            messages[index].text += text
            messages[index].isStreaming = true
            messages[index].status = "streaming"
            return
        }

        let message = ChatMessage(
            sessionID: sessionID,
            kind: kind,
            text: text,
            status: "streaming",
            parentUserMessageID: activeParentUserMessageID,
            isStreaming: true
        )
        activeStreamingMessageIDs[kind] = message.id
        if kind == .assistant {
            activeAssistantMessageID = message.id
        }
        messages.append(message)
    }

    private func appendError(_ text: String) {
        let sessionID = currentSession?.id ?? UUID()
        messages.append(ChatMessage(
            sessionID: sessionID,
            kind: .error,
            title: "error",
            text: text,
            status: "failed",
            parentUserMessageID: activeParentUserMessageID
        ))
    }

    private func finishStreamingMessages(status itemStatus: String = "done") {
        for index in messages.indices where messages[index].isStreaming {
            messages[index].isStreaming = false
            messages[index].status = itemStatus
        }
        activeAssistantMessageID = nil
        activeStreamingMessageIDs.removeAll()
    }

    private func persistCurrentSession() {
        guard let session = currentSession else { return }
        do {
            try ChatSessionStore.saveSession(session)
            try ChatSessionStore.saveMessages(messages, sessionID: session.id)
        } catch {
            statusText = "保存失败"
        }
    }

    private func title(from text: String) -> String {
        let line = text.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "新会话"
        if line.count <= 30 { return line.isEmpty ? "新会话" : line }
        return String(line.prefix(30)) + "…"
    }

    private func checkAutoCompact() {
        guard !didAutoCompact, tokensTotal > 0 else { return }
        let usage = Double(tokensUsed) / Double(tokensTotal)
        if usage >= Self.compactThreshold {
            didAutoCompact = true
            activeBackend?.sendCompact()
            statusText = "自动压缩上下文"
        }
    }
}
