import Foundation

struct QueuedChatRequest: Identifiable, Equatable {
    let id: UUID
    let text: String
    let project: ProjectItem
    let cli: CLIType
    let modelID: String
    let contextModelID: String?
    let permissionMode: ChatPermissionMode
    let reasoningEffort: ChatReasoningEffort
    let sessionMode: SessionMode
    let resumeSessionID: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        project: ProjectItem,
        cli: CLIType,
        modelID: String,
        contextModelID: String?,
        permissionMode: ChatPermissionMode,
        reasoningEffort: ChatReasoningEffort,
        sessionMode: SessionMode,
        resumeSessionID: String?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.project = project
        self.cli = cli
        self.modelID = modelID
        self.contextModelID = contextModelID
        self.permissionMode = permissionMode
        self.reasoningEffort = reasoningEffort
        self.sessionMode = sessionMode
        self.resumeSessionID = resumeSessionID
        self.createdAt = createdAt
    }
}

@MainActor
final class ChatPanelState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var queuedRequests: [QueuedChatRequest] = []
    @Published var status: ChatRunStatus = .idle
    @Published var capabilities: [CLIType: ChatCLICapability] = [:]
    @Published var statusText = "就绪"
    @Published var tokensUsed: Int = 0
    @Published var tokensTotal: Int = 200_000
    @Published var isAwaitingFirstModelOutput = false
    @Published var transcriptRevision = 0

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
    private struct StreamingMessageKey: Hashable {
        let kind: ChatMessageKind
        let requestID: String?

        init(kind: ChatMessageKind, requestID: String?) {
            self.kind = kind
            self.requestID = requestID?.nonEmptyTrimmed
        }
    }

    private var isUserStopping = false
    private var shouldStartQueuedRequestAfterBackendEnds = false
    private var activeAssistantMessageID: UUID?
    private var activeStreamingMessageIDs: [StreamingMessageKey: UUID] = [:]
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
        shouldStartQueuedRequestAfterBackendEnds = false
        queuedRequests.removeAll()
        setAwaitingFirstModelOutput(false)
        bumpTranscriptRevision()

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

    @discardableResult
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
    ) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard let project else {
            appendError("请先选择项目。")
            return false
        }

        let request = QueuedChatRequest(
            text: text,
            project: project,
            cli: cli,
            modelID: modelID,
            contextModelID: contextModelID,
            permissionMode: permissionMode,
            reasoningEffort: reasoningEffort,
            sessionMode: sessionMode,
            resumeSessionID: resumeSessionID
        )
        if status.isRunning {
            queuedRequests.append(request)
            statusText = "已加入队列"
            bumpTranscriptRevision()
            return true
        }
        return startRun(request)
    }

    func cancelQueuedRequest(_ id: UUID) {
        queuedRequests.removeAll { $0.id == id }
        bumpTranscriptRevision()
    }

    @discardableResult
    private func startRun(_ request: QueuedChatRequest) -> Bool {
        let visibleCLI = request.cli.visibleValue
        guard let capability = capabilities[visibleCLI] else {
            appendError("正在检测 \(visibleCLI.displayName)，请稍后重试。")
            refreshCapabilities()
            return false
        }
        guard let executable = capability.executablePath, capability.errorMessage == nil else {
            status = .unsupportedVersion
            appendError(capability.errorMessage ?? "\(visibleCLI.displayName) 不可用。")
            return false
        }
        if visibleCLI == .codex, !capability.supportsAppServer {
            status = .unsupportedVersion
            appendError("当前 Codex 版本不支持 app-server，无法在内嵌对话中启动。")
            return false
        }
        if visibleCLI == .claude, request.permissionMode == .ask {
            status = .unsupportedVersion
            let reason = capability.supportsStreamJSONInput
                ? "当前 Claude Code CLI 未公开 stdin 权限 allow/deny 回写协议。"
                : "当前 Claude Code 版本不支持 stream-json stdin 输入。"
            appendError("\(reason)请改用自动编辑/完全访问权限后重试，避免工具调用时出现无法响应的假权限按钮。")
            return false
        }

        let effectiveContextModelID = request.contextModelID?.nonEmptyTrimmed ?? request.modelID
        var session = ensureSession(
            project: request.project,
            cli: visibleCLI,
            modelID: effectiveContextModelID,
            permissionMode: request.permissionMode,
            reasoningEffort: request.reasoningEffort,
            firstPrompt: request.text
        )
        session.cli = visibleCLI
        session.modelID = effectiveContextModelID
        session.permissionMode = request.permissionMode
        session.reasoningEffort = request.reasoningEffort
        session.updatedAt = Date()
        currentSession = session

        tokensTotal = Self.defaultContextWindow(for: effectiveContextModelID)
        didAutoCompact = false

        let userMessage = ChatMessage(sessionID: session.id, kind: .user, text: request.text, status: "user")
        activeParentUserMessageID = userMessage.id
        activeAssistantMessageID = nil
        activeStreamingMessageIDs.removeAll()
        messages.append(userMessage)
        setAwaitingFirstModelOutput(true)
        bumpTranscriptRevision()
        persistCurrentSession()

        let options = ChatRunOptions(
            cli: visibleCLI,
            executablePath: executable,
            projectPath: request.project.path,
            modelID: request.modelID,
            permissionMode: request.permissionMode,
            reasoningEffort: request.reasoningEffort,
            sessionMode: request.sessionMode,
            resumeSessionID: effectiveResumeSessionID(request.resumeSessionID, for: session)
        )
        let backend: ChatProcessBackend = visibleCLI == .codex ? CodexAppServerBackend() : ClaudeCodeProcessBackend()
        activeBackend = backend
        isUserStopping = false
        shouldStartQueuedRequestAfterBackendEnds = false
        status = .starting
        statusText = "启动 \(visibleCLI.displayName)"

        currentTask = Task { [weak self] in
            guard let self else { return }
            let scopedURL: URL
            let didStartAccessing: Bool
            do {
                scopedURL = try ProjectStore.resolveURL(for: request.project)
                didStartAccessing = scopedURL.startAccessingSecurityScopedResource()
            } catch {
                await MainActor.run {
                    self.appendError(error.localizedDescription)
                    self.status = .failed
                    self.statusText = "项目权限失效"
                    self.setAwaitingFirstModelOutput(false)
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
                for try await event in backend.start(prompt: request.text, options: options, session: session) {
                    await MainActor.run {
                        self.apply(event)
                    }
                }
                await MainActor.run {
                    self.backendStreamDidEnd()
                }
            } catch {
                await MainActor.run {
                    self.appendError(error.localizedDescription)
                    self.status = .failed
                    self.statusText = "失败"
                    self.finishStreamingMessages(status: "failed")
                    self.setAwaitingFirstModelOutput(false)
                    self.shouldStartQueuedRequestAfterBackendEnds = false
                    self.persistCurrentSession()
                }
            }
        }
        return true
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
        bumpTranscriptRevision()
        persistCurrentSession()
    }

    func interrupt() {
        guard status.isRunning else { return }
        isUserStopping = true
        shouldStartQueuedRequestAfterBackendEnds = false
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
        guard activeBackend?.respondToPermission(requestID: requestID, decision: decision) == true else {
            if let index = messages.firstIndex(where: { $0.requestID == requestID }) {
                messages[index].status = "failed"
            }
            appendError("权限响应写回失败。当前 CLI 模式不支持内嵌权限交互，请改用自动编辑/完全访问权限后重试。")
            status = .failed
            statusText = "权限写回失败"
            bumpTranscriptRevision()
            persistCurrentSession()
            return
        }
        if let index = messages.firstIndex(where: { $0.requestID == requestID }) {
            messages[index].status = decision.statusText
        }
        status = .streaming
        statusText = decision.displayText
        bumpTranscriptRevision()
        persistCurrentSession()
    }

    func respondToInteractiveRequest(_ response: ChatInteractiveResponse) {
        guard activeBackend?.respondToInteractiveRequest(requestID: response.requestID, response: response) == true else {
            updateInteractiveRequestStatus(response.requestID, status: .failed)
            appendError("交互响应写回失败。当前 CLI 模式不支持此类选择题/输入回写。")
            status = .failed
            statusText = "交互写回失败"
            persistCurrentSession()
            return
        }
        updateInteractiveRequestStatus(response.requestID, status: .answered)
        status = .streaming
        statusText = "已回复选择"
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
                activeStreamingMessageIDs[StreamingMessageKey(kind: kind, requestID: requestID)] = message.id
                if kind == .assistant {
                    activeAssistantMessageID = message.id
                }
            }
            if isVisibleModelOutput(kind) {
                setAwaitingFirstModelOutput(false)
                status = .streaming
            }
            statusText = itemStatus
            bumpTranscriptRevision()
        case .appendDelta(let kind, let title, let subtitle, let text, let itemStatus, let requestID):
            appendDelta(kind: kind, title: title, subtitle: subtitle, text: text, status: itemStatus, requestID: requestID)
            if isVisibleModelOutput(kind) { status = .streaming }
            statusText = itemStatus.nonEmptyTrimmed ?? "streaming"
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
            setAwaitingFirstModelOutput(false)
            status = .waitingPermission
            statusText = "等待权限"
            bumpTranscriptRevision()
        case .interactiveRequest(let request):
            guard let sessionID = currentSession?.id else { return }
            messages.append(ChatMessage(
                sessionID: sessionID,
                kind: .interactiveRequest,
                title: request.title,
                text: request.prompt,
                status: request.status.rawValue,
                parentUserMessageID: activeParentUserMessageID,
                requestID: request.id,
                interactiveRequest: request
            ))
            setAwaitingFirstModelOutput(false)
            status = .waitingInput
            statusText = "等待输入"
            bumpTranscriptRevision()
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
            shouldStartQueuedRequestAfterBackendEnds = !isUserStopping
            finishStreamingMessages(status: isUserStopping ? "stopped" : "done")
            setAwaitingFirstModelOutput(false)
            currentSession?.updatedAt = Date()
            status = .completed
            statusText = isUserStopping ? "已停止" : "完成"
            isUserStopping = false
            persistCurrentSession()
        case .failed(let message):
            if isUserStopping {
                finishStreamingMessages(status: "stopped")
                setAwaitingFirstModelOutput(false)
                currentSession?.updatedAt = Date()
                status = .completed
                statusText = "已停止"
                isUserStopping = false
                shouldStartQueuedRequestAfterBackendEnds = false
                persistCurrentSession()
                return
            }
            finishStreamingMessages(status: "failed")
            appendError(message)
            setAwaitingFirstModelOutput(false)
            currentSession?.updatedAt = Date()
            status = .failed
            statusText = "失败"
            shouldStartQueuedRequestAfterBackendEnds = false
            persistCurrentSession()
        }
    }

    private func backendStreamDidEnd() {
        let shouldStartQueuedRequest = shouldStartQueuedRequestAfterBackendEnds
        shouldStartQueuedRequestAfterBackendEnds = false
        if status.isRunning {
            finishStreamingMessages(status: isUserStopping ? "stopped" : "done")
            setAwaitingFirstModelOutput(false)
            currentSession?.updatedAt = Date()
            status = .completed
            statusText = isUserStopping ? "已停止" : "完成"
            isUserStopping = false
            persistCurrentSession()
        }
        if shouldStartQueuedRequest {
            startNextQueuedRequestIfNeeded()
        }
    }

    private func appendDelta(kind: ChatMessageKind, title: String, subtitle: String, text: String, status itemStatus: String, requestID: String?) {
        guard !text.isEmpty, let sessionID = currentSession?.id else { return }
        let key = StreamingMessageKey(kind: kind, requestID: requestID)
        let status = itemStatus.nonEmptyTrimmed ?? "streaming"
        if let activeMessageID = activeStreamingMessageIDs[key],
           let index = messages.firstIndex(where: { $0.id == activeMessageID }),
           shouldAppendDeltaToExistingMessage(kind: kind, requestID: requestID, activeMessageID: activeMessageID) {
            messages[index].text += text
            messages[index].isStreaming = true
            messages[index].status = status
            if messages[index].requestID == nil {
                messages[index].requestID = requestID?.nonEmptyTrimmed
            }
            if isVisibleModelOutput(kind) { setAwaitingFirstModelOutput(false) }
            bumpTranscriptRevision()
            return
        }

        let message = ChatMessage(
            sessionID: sessionID,
            kind: kind,
            title: title,
            subtitle: subtitle,
            text: text,
            status: status,
            parentUserMessageID: activeParentUserMessageID,
            requestID: requestID?.nonEmptyTrimmed,
            isStreaming: true
        )
        activeStreamingMessageIDs[key] = message.id
        if kind == .assistant {
            activeAssistantMessageID = message.id
        }
        messages.append(message)
        if isVisibleModelOutput(kind) { setAwaitingFirstModelOutput(false) }
        bumpTranscriptRevision()
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
        setAwaitingFirstModelOutput(false)
        bumpTranscriptRevision()
    }

    private func finishStreamingMessages(status itemStatus: String = "done") {
        for index in messages.indices where messages[index].isStreaming {
            messages[index].isStreaming = false
            messages[index].status = itemStatus
        }
        activeAssistantMessageID = nil
        activeStreamingMessageIDs.removeAll()
        bumpTranscriptRevision()
    }

    private func startNextQueuedRequestIfNeeded() {
        guard !status.isRunning, !queuedRequests.isEmpty else { return }
        let request = queuedRequests.removeFirst()
        bumpTranscriptRevision()
        _ = startRun(request)
    }

    private func shouldAppendDeltaToExistingMessage(kind: ChatMessageKind, requestID: String?, activeMessageID: UUID) -> Bool {
        switch kind {
        case .assistant, .reasoning:
            guard lastVisibleMessageID == activeMessageID else { return false }
            return true
        default:
            return true
        }
    }

    private var lastVisibleMessageID: UUID? {
        messages.last(where: { isVisibleModelOutput($0.kind) || $0.kind == .user })?.id
    }

    private func setAwaitingFirstModelOutput(_ value: Bool) {
        guard isAwaitingFirstModelOutput != value else { return }
        isAwaitingFirstModelOutput = value
        bumpTranscriptRevision()
    }

    private func bumpTranscriptRevision() {
        transcriptRevision &+= 1
    }

    private func isVisibleModelOutput(_ kind: ChatMessageKind) -> Bool {
        switch kind {
        case .assistant, .reasoning, .toolCall, .toolResult, .command, .commandOutput, .permissionRequest, .interactiveRequest, .diff, .error:
            true
        case .user, .system, .result, .rawOutput:
            false
        }
    }

    private func updateInteractiveRequestStatus(_ requestID: String, status: ChatInteractiveStatus) {
        guard let index = messages.firstIndex(where: { $0.requestID == requestID }) else { return }
        messages[index].status = status.rawValue
        messages[index].interactiveRequest?.status = status
        bumpTranscriptRevision()
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
            if activeBackend?.sendCompact() == true {
                statusText = "自动压缩上下文"
            } else {
                statusText = "上下文接近上限"
            }
        }
    }
}
