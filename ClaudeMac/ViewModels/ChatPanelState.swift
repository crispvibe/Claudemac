import Foundation

@MainActor
final class ChatPanelState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var status: ChatRunStatus = .idle
    @Published var capabilities: [CLIType: ChatCLICapability] = [:]
    @Published var statusText = "就绪"

    private var currentSession: ChatSessionRecord?
    private var currentTask: Task<Void, Never>?
    private var activeBackend: ChatProcessBackend?
    private var activeAssistantMessageID: UUID?
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

    func loadFromAppState(_ appState: AppState, modelID: String, permissionMode: ChatPermissionMode) {
        interruptIfNeededForLoad()
        activeAssistantMessageID = nil
        activeParentUserMessageID = nil

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
        permissionMode: ChatPermissionMode,
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

        var session = ensureSession(project: project, cli: visibleCLI, modelID: modelID, permissionMode: permissionMode, firstPrompt: text)
        session.cli = visibleCLI
        session.modelID = modelID
        session.permissionMode = permissionMode
        session.updatedAt = Date()
        currentSession = session

        let userMessage = ChatMessage(sessionID: session.id, kind: .user, text: text, status: "user")
        activeParentUserMessageID = userMessage.id
        activeAssistantMessageID = nil
        messages.append(userMessage)
        persistCurrentSession()

        let options = ChatRunOptions(
            cli: visibleCLI,
            executablePath: executable,
            projectPath: project.path,
            modelID: modelID,
            permissionMode: permissionMode,
            sessionMode: sessionMode,
            resumeSessionID: resumeSessionID?.nonEmptyTrimmed
        )
        let backend: ChatProcessBackend = visibleCLI == .codex ? CodexAppServerBackend() : ClaudeCodeProcessBackend()
        activeBackend = backend
        status = .starting
        statusText = "启动 \(visibleCLI.displayName)"

        currentTask = Task { [weak self] in
            guard let self else { return }
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
        if activeParentUserMessageID == id {
            activeParentUserMessageID = nil
            activeAssistantMessageID = nil
        }
        persistCurrentSession()
    }

    func interrupt() {
        guard status.isRunning else { return }
        status = .stopping
        statusText = "正在停止"
        activeBackend?.interrupt()
        currentTask?.cancel()
        finishStreamingMessages(status: "stopped")
        status = .completed
        statusText = "已停止"
        persistCurrentSession()
    }

    func respondToPermission(requestID: String, allowed: Bool) {
        activeBackend?.respondToPermission(requestID: requestID, allowed: allowed)
        if let index = messages.firstIndex(where: { $0.requestID == requestID }) {
            messages[index].status = allowed ? "allowed" : "denied"
        }
        status = .streaming
        statusText = allowed ? "已允许" : "已拒绝"
        persistCurrentSession()
    }

    private func interruptIfNeededForLoad() {
        if status.isRunning { interrupt() }
    }

    private func ensureSession(project: ProjectItem, cli: CLIType, modelID: String, permissionMode: ChatPermissionMode, firstPrompt: String) -> ChatSessionRecord {
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
            permissionMode: permissionMode
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
        case .finished:
            finishStreamingMessages()
            currentSession?.updatedAt = Date()
            status = .completed
            statusText = "完成"
            persistCurrentSession()
        case .failed(let message):
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
        if let activeAssistantMessageID,
           let index = messages.firstIndex(where: { $0.id == activeAssistantMessageID }) {
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
        activeAssistantMessageID = message.id
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
}
