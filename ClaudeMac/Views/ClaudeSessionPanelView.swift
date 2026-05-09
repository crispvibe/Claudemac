import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatPanelView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var modelService: ChatModelService
    @EnvironmentObject private var chatRuntimeStore: ChatRuntimeStore
    @State private var draftMessage = ""
    @State private var editingMessageID: UUID?
    @State private var selectedModelID = ChatModelCatalog.defaultClaudeModelID
    @State private var permissionMode = ChatPermissionMode.ask
    @State private var reasoningEffort = ChatReasoningEffort.high
    @State private var activePicker: ChatPicker?
    @State private var customModelInput = ""
    @State private var showCopiedToast = false
    @State private var attachedPaths: [String] = []
    @State private var expandedTranscriptMessageIDs: Set<UUID> = []
    @State private var composerHasMarkedText = false
    @State private var suggestedCommand: ComposerSuggestedCommand?
    @State private var lastSuggestedAssistantMessageID: UUID?
    @State private var lastTranscriptScrollAt = Date.distantPast
    @State private var shouldFollowTranscriptBottom = true
    @State private var composerTextHeight: CGFloat = 42
    @State private var selectedSubagentDetail: SubagentDetailRequest?
    @State private var activeComposerDraftKey = ""
    @State private var cachedTranscriptRevision = -1
    @State private var cachedTranscriptProjectKey = ""
    @State private var cachedTranscriptItems: [ChatTranscriptItem] = []
    private let transcriptBottomID = "chat-transcript-bottom"
    private let composerMinimumTextHeight: CGFloat = 42

    private var chatState: ChatPanelState {
        chatRuntimeStore.state(
            for: appState,
            modelID: selectedModelID,
            permissionMode: permissionMode,
            reasoningEffort: reasoningEffort
        )
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header

                Divider()
                    .opacity(0.35)
                    .padding(.horizontal, 18)

                transcript

                composer
            }

            if showCopiedToast {
                Text("复制成功")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.82))
                    .clipShape(Capsule())
                    .transition(.opacity)
                    .zIndex(900)
            }

            if let activePicker {
                globalPickerLayer(activePicker)
                    .zIndex(1_000)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .onAppear {
            applyPersistedChatSelection()
            resetReasoningEffortToConfiguredDefault()
            syncSelectedContextWindow()
            activateComposerDraftKey(composerDraftKey)
            refreshTranscriptItems()
        }
        .onChange(of: composerDraftKey) { oldKey, newKey in
            switchComposerDraft(from: oldKey, to: newKey)
        }
        .onChange(of: draftMessage) { _, newValue in
            persistComposerDraft(newValue)
        }
        .onChange(of: appState.chatConversationSerial) { _, _ in
            applyPersistedChatSelection()
            normalizeReasoningEffort()
            syncSelectedContextWindow()
            clearSuggestedCommand()
            shouldFollowTranscriptBottom = true
            lastSuggestedAssistantMessageID = nil
            refreshTranscriptItems(force: true)
        }
        .onChange(of: appState.selectedCLI) { _, _ in
            selectedModelID = persistedModelID(for: appState.selectedCLI)
            normalizeSelectedModel()
            resetReasoningEffortToConfiguredDefault()
            syncSelectedContextWindow()
            persistChatSelection()
            shouldFollowTranscriptBottom = true
            activePicker = nil
        }
        .onChange(of: selectedModelID) { _, _ in
            syncSelectedContextWindow()
            persistChatSelection()
        }
        .onChange(of: chatState.transcriptRevision) { _, _ in
            refreshTranscriptItems()
            installSuggestedCommandIfNeeded()
        }
        .onChange(of: appState.selectedProject?.path) { _, _ in
            refreshTranscriptItems(force: true)
        }
        .sheet(item: $selectedSubagentDetail) { request in
            SubagentTranscriptSheet(request: request)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            appIdentity
            Button(action: copyProjectPath) {
                Text(projectPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: startNewChat) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("新对话")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(appState.selectedProject == nil)
            .opacity(appState.selectedProject == nil ? 0.45 : 1)
            .help("新建对话")
        }
        .frame(maxWidth: .infinity, minHeight: 37, alignment: .leading)
        .padding(.horizontal, 14)
    }

    private var appIdentity: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(appDisplayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .layoutPriority(1)
    }

    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Acode"
    }

    private var transcript: some View {
        let items = cachedTranscriptItems
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if appState.selectedProject == nil {
                        emptyProjectState
                    } else if items.isEmpty {
                        emptyChatState
                    } else {
                        ForEach(items) { item in
                            transcriptItemRow(item)
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(transcriptBottomID)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    TranscriptScrollObserver { isAtBottom in
                        shouldFollowTranscriptBottom = isAtBottom
                    }
                )
            }
            .scrollIndicators(.hidden)
            .background(Color.white)
            .onAppear {
                refreshTranscriptItems()
                scrollTranscriptToBottom(proxy, force: true)
            }
            .onChange(of: chatState.transcriptRevision) { _, _ in scrollTranscriptToBottom(proxy, animated: false) }
            .onChange(of: chatState.isAwaitingFirstModelOutput) { _, _ in scrollTranscriptToBottom(proxy) }
            .onChange(of: chatState.queuedRequests.count) { _, _ in scrollTranscriptToBottom(proxy) }
        }
    }

    private func refreshTranscriptItems(force: Bool = false) {
        let projectKey = appState.selectedProject?.path ?? appState.selectedHistoryProjectPath ?? ""
        guard force || cachedTranscriptRevision != chatState.transcriptRevision || cachedTranscriptProjectKey != projectKey else { return }
        cachedTranscriptRevision = chatState.transcriptRevision
        cachedTranscriptProjectKey = projectKey
        cachedTranscriptItems = buildTranscriptItems()
    }

    private func buildTranscriptItems() -> [ChatTranscriptItem] {
        var items: [ChatTranscriptItem] = []
        items.reserveCapacity(chatState.messages.count + 1)
        var seenErrorMessages = Set<String>()
        var groupedMessageIDs = Set<UUID>()
        for index in chatState.messages.indices {
            let message = chatState.messages[index]
            guard shouldShowInTranscript(message), !groupedMessageIDs.contains(message.id) else { continue }
            if message.kind == .error {
                let key = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard seenErrorMessages.insert(key).inserted else { continue }
            }
            if let group = toolInvocationGroup(startingAt: index, groupedMessageIDs: groupedMessageIDs) {
                groupedMessageIDs.formUnion(group.responses.map(\.id))
                items.append(.toolGroup(group))
            } else {
                items.append(.message(message))
            }
        }
        if chatState.isAwaitingFirstModelOutput && appState.selectedProject != nil {
            items.append(.loading)
        }
        return items
    }

    private func toolInvocationGroup(startingAt index: Int, groupedMessageIDs: Set<UUID>) -> ToolInvocationGroup? {
        let primary = chatState.messages[index]
        guard primary.isToolInvocationStart else { return nil }
        var responses: [ChatMessage] = []
        for candidate in chatState.messages.dropFirst(index + 1) {
            guard shouldShowInTranscript(candidate), !groupedMessageIDs.contains(candidate.id) else { continue }
            if candidate.isToolInvocationFeedback(for: primary) {
                responses.append(candidate)
                continue
            }
            if candidate.isToolInvocationBoundary || primary.toolCorrelationID == nil || !responses.isEmpty {
                break
            }
        }
        guard !responses.isEmpty else { return nil }
        return ToolInvocationGroup(primary: primary, responses: responses)
    }

    private func scrollTranscriptToBottom(_ proxy: ScrollViewProxy, animated: Bool = true, force: Bool = false) {
        guard force || shouldFollowTranscriptBottom else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastTranscriptScrollAt) < 0.25 { return }
        lastTranscriptScrollAt = now
        shouldFollowTranscriptBottom = true
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(transcriptBottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(transcriptBottomID, anchor: .bottom)
            }
        }
    }

    private func shouldShowInTranscript(_ message: ChatMessage) -> Bool {
        guard !message.isBackendLaunchCommand else { return false }
        guard message.kind.isVisibleInTranscript else { return false }
        switch message.kind {
        case .assistant, .reasoning, .error:
            return message.isStreaming || !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .toolCall, .toolResult, .command, .commandOutput, .diff:
            return message.isStreaming
                || !message.title.isEmpty
                || !message.subtitle.isEmpty
                || !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }

    private var emptyProjectState: some View {
        Text(appState.selectedHistoryProjectPath?.nonEmptyTrimmed == nil ? "先选择一个项目。" : "该历史会话属于未添加项目，请先添加项目目录以继续内嵌对话。")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyChatState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("发送消息开始真实 CLI 会话。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            Text(capabilityText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func transcriptItemRow(_ item: ChatTranscriptItem) -> some View {
        switch item {
        case .message(let message):
            messageRow(message)
        case .toolGroup(let group):
            toolInvocationRow(group)
        case .loading:
            loadingMessageRow
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        switch message.kind {
        case .user:
            userMessageRow(message)
        case .assistant:
            assistantMessageRow(message)
        case .reasoning:
            reasoningMessageRow(message)
        case .toolCall, .toolResult, .command, .commandOutput, .diff:
            toolInvocationRow(message)
        case .permissionRequest:
            permissionRequestRow(message)
        case .interactiveRequest:
            interactiveRequestRow(message)
        case .error:
            errorMessageRow(message)
        case .system, .result, .rawOutput:
            EmptyView()
        }
    }

    private func userMessageRow(_ message: ChatMessage) -> some View {
        HStack(alignment: .top) {
            Spacer(minLength: 34)

            VStack(alignment: .trailing, spacing: 5) {
                Text(message.text)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                messageActionBar(message, alignment: .trailing)
            }
        }
    }

    private func assistantMessageRow(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AssistantMessageContent(text: message.text, isStreaming: message.isStreaming, onOpenFile: openFileReference)

            messageActionBar(message, alignment: .leading)
        }
    }

    private func openFileReference(_ reference: FileReference) {
        appState.openFile(path: reference.path)
    }

    private var loadingMessageRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.55)
                .frame(width: 14, height: 14)
            Text("正在生成…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorMessageRow(_ message: ChatMessage) -> some View {
        Text(message.text)
            .font(.system(size: 12))
            .lineSpacing(2)
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toolInvocationRow(_ message: ChatMessage) -> some View {
        let isExpanded = expandedTranscriptMessageIDs.contains(message.id)
        return VStack(alignment: .leading, spacing: 6) {
            toolInvocationHeader(message, isExpanded: isExpanded)

            if isExpanded {
                toolDetailCard(message)
                    .padding(.leading, 12)
            }
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toolInvocationRow(_ group: ToolInvocationGroup) -> some View {
        let isExpanded = expandedTranscriptMessageIDs.contains(group.primary.id)
        return VStack(alignment: .leading, spacing: 6) {
            toolInvocationHeader(group.primary, isExpanded: isExpanded, feedbackCount: group.responses.count)

            if isExpanded {
                toolDetailCard(group)
                    .padding(.leading, 12)
            }
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toolInvocationHeader(_ message: ChatMessage, isExpanded: Bool, feedbackCount: Int = 0) -> some View {
        let summary = ToolInvocationSummaryCache.summary(for: message)
        return HStack(alignment: .center, spacing: 7) {
            Button {
                toggleTranscriptMessage(message.id)
            } label: {
                HStack(alignment: .center, spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)

                    Text(summary.primaryTitle)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let summaryText = summary.plainSummary {
                        Text(summaryText)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if feedbackCount > 0 {
                        Text("反馈 \(feedbackCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if summary.isAgentTool {
                subagentDetailButton(message, summary: summary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
    }

    private func subagentDetailButton(_ message: ChatMessage, summary: ToolInvocationSummary) -> some View {
        Button {
            guard let request = message.subagentDetailRequest(projectPath: appState.selectedProject?.path) else { return }
            selectedSubagentDetail = request
        } label: {
            Text("process")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .help("打开子代理过程")
    }

    private func toolFileButton(path: String) -> some View {
        let reference = FileReference(path: path)
        return FileReferenceButton(reference: reference, onOpenFile: openFileReference)
    }

    private func toolInfoPill(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .medium))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.08))
        .clipShape(Capsule())
    }

    private func toolStatusPill(_ message: ChatMessage) -> some View {
        Text(message.toolStatusLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(message.toolTint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(message.toolTint.opacity(0.1))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func toolDetailCard(_ message: ChatMessage) -> some View {
        let detailText = message.isTerminalTool ? message.terminalDetailText : message.toolDetailText
        if message.kind == .diff || !detailText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(message.toolDetailLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    if !detailText.isEmpty {
                        iconAction("doc.on.doc", help: "复制详情") {
                            copyText(detailText)
                        }
                    }
                }

                toolDetailSection(message, label: nil)
            }
            .padding(.leading, 2)
        }
    }

    @ViewBuilder
    private func toolDetailCard(_ group: ToolInvocationGroup) -> some View {
        let detailText = group.detailText
        if !detailText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(group.primary.isTerminalTool ? "terminal + feedback" : "tool + feedback")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    iconAction("doc.on.doc", help: "复制详情") {
                        copyText(detailText)
                    }
                }

                toolDetailSection(group.primary, label: "调用")
                ForEach(group.responses) { response in
                    toolDetailSection(response, label: "反馈")
                }
            }
            .padding(.leading, 2)
        }
    }

    @ViewBuilder
    private func toolDetailSection(_ message: ChatMessage, label: String?) -> some View {
        let detailText = message.isTerminalTool ? message.terminalDetailText : message.toolDetailText
        if message.kind == .diff || !detailText.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let label {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if message.isAgentTool {
                    subagentSummaryCard(message)
                }
                if let preview = message.toolCodePreview {
                    toolCodePreviewCard(preview)
                }
                toolDetailView(message)
            }
        }
    }

    private func subagentSummaryCard(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(message.subagentDisplayTitle)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let agentID = message.subagentID {
                    Text("agent-\(agentID.prefix(8))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            if let prompt = message.subagentPrompt {
                Text(prompt)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            } else if let summary = message.subagentResultSummary {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
        }
    }

    private func toolCodePreviewCard(_ preview: ToolCodePreview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(preview.title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(preview.stats)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(preview.lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 6) {
                        Text(line.marker)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 10, alignment: .center)
                        Text(line.text)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, 8)
        }
    }

    @ViewBuilder
    private func toolDetailView(_ message: ChatMessage) -> some View {
        if message.kind == .diff {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(message.diffLines.prefix(300).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(line.diffTint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if message.diffLines.count > 300 {
                        Text("…diff 过长，已显示前 300 行")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } else if message.isTerminalTool && !message.terminalDetailText.isEmpty {
            terminalDetailView(message)
        } else if !message.toolDetailText.isEmpty {
            ScrollView(.horizontal, showsIndicators: true) {
                FileReferenceText(
                    text: message.toolDetailPreviewText,
                    font: .system(size: 10, design: message.kind.isToolDetailMonospaced ? .monospaced : .default),
                    baseColor: .secondary,
                    lineSpacing: 2,
                    parseMarkdown: false,
                    onOpenFile: openFileReference
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func terminalDetailView(_ message: ChatMessage) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            FileReferenceText(
                text: message.terminalDetailPreviewText,
                font: .system(size: 10, design: .monospaced),
                baseColor: .primary.opacity(0.78),
                lineSpacing: 2,
                parseMarkdown: false,
                onOpenFile: openFileReference
            )
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.black.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func interactiveRequestRow(_ message: ChatMessage) -> some View {
        ChatInteractiveRequestCard(message: message, chatState: chatState)
    }

    private func reasoningMessageRow(_ message: ChatMessage) -> some View {
        let isThinking = message.isStreaming && lastVisibleTranscriptMessageID == message.id
        let isExpanded = isThinking || expandedTranscriptMessageIDs.contains(message.id)

        return VStack(alignment: .leading, spacing: 5) {
            Button {
                toggleTranscriptMessage(message.id)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 12)

                    Text("thinking")
                        .font(.system(size: 12, weight: .medium))

                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded && !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.leading, 19)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lastVisibleTranscriptMessageID: UUID? {
        chatState.messages.last(where: shouldShowInTranscript)?.id
    }

    private func toggleTranscriptMessage(_ id: UUID) {
        if expandedTranscriptMessageIDs.contains(id) {
            expandedTranscriptMessageIDs.remove(id)
        } else {
            expandedTranscriptMessageIDs.insert(id)
        }
    }

    private func fileEditRow(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("edit")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.green)
                    .frame(width: 54, alignment: .leading)

                Text(message.title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(message.status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(message.diffLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(line.diffTint)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, 60)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func permissionRequestRow(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(message.title.isEmpty ? "需要权限" : message.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(message.text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if message.status == "waiting" {
                HStack(spacing: 8) {
                    Button("拒绝") {
                        if let requestID = message.requestID {
                            chatState.respondToPermission(requestID: requestID, decision: .deny)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("允许") {
                        if let requestID = message.requestID {
                            chatState.respondToPermission(requestID: requestID, decision: .allow)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("本会话允许") {
                        if let requestID = message.requestID {
                            chatState.respondToPermission(requestID: requestID, decision: .allowForSession)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func processedHeader(_ message: ChatMessage) -> some View {
        HStack(spacing: 6) {
            Text(message.status.isEmpty ? "assistant" : message.status)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text("›")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    private func messageActionBar(_ message: ChatMessage, alignment: HorizontalAlignment) -> some View {
        HStack(spacing: 8) {
            if alignment == .trailing {
                Spacer(minLength: 0)
            }

            Text(message.timestampText)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            iconAction("doc.on.doc", help: "复制") {
                copyMessage(message)
            }

            if message.kind == .user {
                iconAction("pencil", help: "编辑") {
                    editMessage(message)
                }
                iconAction("arrow.uturn.backward", help: "撤销") {
                    undoMessage(message)
                }
            }

            if alignment == .leading {
                Spacer(minLength: 0)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if !chatState.queuedRequests.isEmpty {
                queuedRequestsView
            }

            composerCard
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 12)
        .background(Color.white)
    }

    private var queuedRequestsView: some View {
        let rowHeight: CGFloat = 28
        let rowSpacing: CGFloat = 4
        let visibleRows = min(chatState.queuedRequests.count, 3)
        let height = CGFloat(visibleRows) * rowHeight + CGFloat(max(visibleRows - 1, 0)) * rowSpacing

        return ScrollView {
            VStack(spacing: rowSpacing) {
                ForEach(Array(chatState.queuedRequests.enumerated()), id: \.element.id) { index, request in
                    HStack(spacing: 7) {
                        Text("#\(index + 1)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, alignment: .leading)
                        Text(request.text.components(separatedBy: .newlines).first ?? request.text)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button {
                            editQueuedRequest(request)
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .medium))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help("编辑队列消息")
                        Button {
                            chatState.cancelQueuedRequest(request.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help("删除队列消息")
                    }
                    .padding(.horizontal, 9)
                    .frame(height: rowHeight)
                    .background(Color.black.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
        .frame(height: height)
    }

    private var composerCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ChatComposerTextView(
                    text: $draftMessage,
                    hasMarkedText: $composerHasMarkedText,
                    suggestedCommand: $suggestedCommand,
                    measuredHeight: $composerTextHeight,
                    onSubmit: sendMessage
                )
                    .frame(height: composerTextHeight)
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                    .padding(.bottom, 1)

                if draftMessage.isEmpty && !composerHasMarkedText {
                    Text(editingMessageID == nil ? "输入你的需求" : "编辑上一条消息")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 18)
                        .padding(.top, 13)
                        .allowsHitTesting(false)
                }
            }

            if !attachedPaths.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachedPaths, id: \.self) { path in
                            Button {
                                attachedPaths.removeAll { $0 == path }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "paperclip")
                                        .font(.system(size: 9))
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .lineLimit(1)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .semibold))
                                }
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.04))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help(path)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
            }

            HStack(spacing: 4) {
                iconOnlyButton(systemImage: "plus", tint: .secondary, action: openFilesForComposer)

                selectorButton(title: appState.selectedCLI.displayName, systemImage: "terminal", tint: .primary, picker: .cli, maxTitleWidth: 78)
                selectorButton(title: permissionMode.shortTitle, systemImage: permissionMode.systemImage, tint: permissionMode.tint, picker: .permission, maxTitleWidth: 30)

                if editingMessageID != nil {
                    Button("取消") {
                        editingMessageID = nil
                        clearComposerText()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                selectorButton(title: selectedModelTitle, systemImage: "cpu", tint: .primary, picker: .model, maxTitleWidth: 118)
                contextIcon
                actionButton
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 9)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .onDrop(of: [UTType.fileURL.identifier, UTType.plainText.identifier], isTargeted: nil, perform: handleDroppedItems)
    }

    @State private var showContextPopover = false

    private var contextUsagePercent: Double {
        guard chatState.tokensTotal > 0 else { return 0 }
        return Double(chatState.tokensUsed) / Double(chatState.tokensTotal)
    }

    private var contextIcon: some View {
        let percent = contextUsagePercent
        return ZStack {
            Circle()
                .stroke(Color.black.opacity(0.08), lineWidth: 2)
            Circle()
                .trim(from: 0, to: percent)
                .stroke(Color.secondary.opacity(0.78), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
        .frame(width: 20, height: 20)
        .onHover { hovering in
            showContextPopover = hovering
        }
        .popover(isPresented: $showContextPopover, arrowEdge: .top) {
            let usedPercent = Int(percent * 100)
            let remainPercent = 100 - usedPercent
            VStack(alignment: .leading, spacing: 4) {
                Text("背景信息窗口：")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Text("\(usedPercent)% 已用（剩余 \(remainPercent)%）")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("已用 \(Self.formatTokens(chatState.tokensUsed)) 标记，共 \(Self.formatTokens(chatState.tokensTotal))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }

    private static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            let value = Double(count) / 1_000_000.0
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(value))m"
                : String(format: "%.1fm", value)
        } else {
            let value = Double(count) / 1000.0
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(value))k"
                : String(format: "%.1fk", value)
        }
    }

    private func globalPickerLayer(_ picker: ChatPicker) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { activePicker = nil }

            pickerOverlay(picker)
                .padding(.horizontal, 12)
                .padding(.bottom, pickerLayerBottomInset)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
        }
    }

    private var pickerLayerBottomInset: CGFloat {
        composerTextHeight + 64 + (attachedPaths.isEmpty ? 0 : 30)
    }

    @ViewBuilder
    private func pickerOverlay(_ picker: ChatPicker) -> some View {
        switch picker {
        case .cli:
            customPickerPanel(picker)
                .padding(.leading, 42)
        case .permission:
            customPickerPanel(picker)
                .padding(.leading, 128)
        case .model:
            HStack {
                Spacer(minLength: 0)
                customPickerPanel(picker)
                    .padding(.trailing, 52)
            }
        }
    }

    private func customPickerPanel(_ picker: ChatPicker) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch picker {
            case .cli:
                ForEach(CLIType.visibleCases) { cli in
                    pickerOption(title: cli.displayName, isSelected: appState.selectedCLI == cli) {
                        appState.selectedCLI = cli
                        selectedModelID = persistedModelID(for: cli)
                        normalizeSelectedModel()
                        persistChatSelection()
                        activePicker = nil
                    }
                }
            case .permission:
                ForEach(ChatPermissionMode.allCases) { mode in
                    pickerOption(title: mode.title, isSelected: permissionMode == mode) {
                        permissionMode = mode
                        persistChatSelection()
                        activePicker = nil
                    }
                }
            case .model:
                ForEach(modelService.options(for: appState.selectedCLI)) { model in
                    pickerOption(title: model.title, isSelected: selectedModelID == model.id) {
                        selectedModelID = model.id
                        syncSelectedContextWindow()
                        persistChatSelection()
                        activePicker = nil
                    }
                }
                Divider().opacity(0.28)
                HStack(spacing: 6) {
                    TextField("添加模型 ID", text: $customModelInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
                    Button("添加") {
                        addCustomModel()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
                    .disabled(customModelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: picker == .model ? 300 : 220, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }

    private func pickerOption(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(isSelected ? Color.black.opacity(0.055) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func selectorButton(
        title: String,
        systemImage: String,
        tint: Color,
        picker: ChatPicker,
        maxTitleWidth: CGFloat? = nil
    ) -> some View {
        Button {
            activePicker = activePicker == picker ? nil : picker
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 11)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: maxTitleWidth, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(tint)
            .frame(minHeight: 22)
            .padding(.vertical, 3)
            .padding(.horizontal, 1)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var actionButton: some View {
        Button(action: primaryAction) {
            Image(systemName: chatState.status.isRunning ? "pause.fill" : "arrow.up")
                .font(.system(size: chatState.status.isRunning ? 9 : 10, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(actionButtonBackground)
        .clipShape(Circle())
        .contentShape(Circle())
        .disabled(!chatState.status.isRunning && !canSend)
        .help(chatState.status.isRunning ? "停止当前任务" : "发送")
    }

    private var actionButtonBackground: Color {
        chatState.status.isRunning || canSend ? Color.accentColor : Color.secondary.opacity(0.58)
    }

    private func primaryAction() {
        if chatState.status.isRunning {
            chatState.interrupt()
        } else {
            sendMessage()
        }
    }

    private var projectName: String {
        if let project = appState.selectedProject { return project.name }
        if appState.selectedHistoryProjectPath?.nonEmptyTrimmed != nil { return "未添加项目历史" }
        return "未选择项目"
    }

    private var projectPath: String {
        if let project = appState.selectedProject { return project.path }
        if let historyPath = appState.selectedHistoryProjectPath?.nonEmptyTrimmed { return "请先添加项目：\(historyPath)" }
        return "请选择项目目录"
    }

    private var selectedModelTitle: String {
        modelService.title(for: selectedModelID, cli: appState.selectedCLI)
    }

    private var composerDraftKey: String {
        if let historyID = appState.selectedCLIHistoryID {
            return "history:\(historyID)"
        }
        let sessionID = appState.resumeSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        if appState.selectedMode == .resume, !sessionID.isEmpty {
            return "history:\(appState.selectedCLI.visibleValue.rawValue):\(sessionID)"
        }
        let projectPath = appState.selectedHistoryProjectPath ?? appState.selectedProject?.path ?? "none"
        return "new:\((projectPath as NSString).standardizingPath)"
    }

    private var canSend: Bool {
        appState.selectedProject != nil && !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var capabilityText: String {
        let cli = appState.selectedCLI.visibleValue
        guard let capability = chatState.capabilities[cli] else { return "正在检测 \(cli.displayName)…" }
        if let error = capability.errorMessage { return error }
        return "\(cli.displayName) · \(capability.version ?? "未知版本") · \(capability.executablePath ?? cli.executable)"
    }

    private func startNewChat() {
        appState.startNewChat(for: appState.selectedProject)
    }

    private func copyProjectPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(projectPath, forType: .string)
        withAnimation(.easeOut(duration: 0.12)) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.18)) {
                showCopiedToast = false
            }
        }
    }

    private func sendMessage() {
        guard canSend else { return }
        if let editingMessageID, !chatState.status.isRunning {
            chatState.removeMessageThread(editingMessageID)
            self.editingMessageID = nil
        }
        let didStart = chatState.send(
            text: composedPrompt,
            project: appState.selectedProject,
            cli: appState.selectedCLI,
            modelID: selectedModelID,
            contextModelID: selectedContextModelID,
            permissionMode: permissionMode,
            reasoningEffort: reasoningEffort,
            sessionMode: appState.selectedMode,
            resumeSessionID: appState.resumeSessionId
        )
        if didStart {
            clearComposerText()
            attachedPaths.removeAll()
        }
    }

    private func clearComposerText() {
        draftMessage = ""
        composerHasMarkedText = false
        composerTextHeight = composerMinimumTextHeight
        clearSuggestedCommand()
        persistComposerDraft("")
    }

    private func switchComposerDraft(from oldKey: String, to newKey: String) {
        persistComposerDraft(draftMessage, for: oldKey)
        activateComposerDraftKey(newKey)
    }

    private func activateComposerDraftKey(_ key: String) {
        activeComposerDraftKey = key
        draftMessage = ChatSessionStore.draft(for: key)
        composerHasMarkedText = false
        composerTextHeight = composerMinimumTextHeight
        clearSuggestedCommand()
    }

    private func persistComposerDraft(_ text: String, for key: String? = nil) {
        let draftKey = key ?? activeComposerDraftKey
        guard !draftKey.isEmpty else { return }
        try? ChatSessionStore.saveDraft(text, for: draftKey)
    }

    private var composedPrompt: String {
        var parts = [draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)]
        let paths = attachedPaths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !paths.isEmpty {
            parts.append("Attached paths:\n" + paths.joined(separator: "\n"))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private func installSuggestedCommandIfNeeded() {
        guard chatState.status == .completed,
              editingMessageID == nil,
              let message = chatState.messages.last(where: { $0.kind == .assistant && !$0.isStreaming }),
              lastSuggestedAssistantMessageID != message.id else { return }
        lastSuggestedAssistantMessageID = message.id
        guard !composerHasMarkedText,
              draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let command = Self.extractSuggestedCommand(from: message.text) else { return }
        draftMessage = command
        suggestedCommand = ComposerSuggestedCommand(text: command)
    }

    private func clearSuggestedCommand() {
        suggestedCommand = nil
    }

    private static func extractSuggestedCommand(from text: String) -> String? {
        for block in AssistantMessageBlock.parse(text) {
            if case .code(let language, let code) = block,
               isShellLanguage(language),
               let command = normalizedSuggestedCommand(code) {
                return command
            }
        }

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("$ "), let command = normalizedSuggestedCommand(String(trimmed.dropFirst(2))) {
                return command
            }
            if let command = commandAfterSuggestionLabel(trimmed) {
                return command
            }
        }
        return nil
    }

    private static func commandAfterSuggestionLabel(_ line: String) -> String? {
        let labels = ["建议指令：", "建议命令：", "推荐指令：", "推荐命令：", "指令：", "命令：", "运行：", "执行：", "Command:", "Suggested command:"]
        for label in labels where line.hasPrefix(label) {
            let value = String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedSuggestedCommand(strippingInlineCodeDelimiters(value))
        }
        return nil
    }

    private static func normalizedSuggestedCommand(_ raw: String) -> String? {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.hasPrefix("$ ") ? String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
            }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard (1...4).contains(lines.count) else { return nil }
        let command = lines.joined(separator: "\n")
        guard command.count <= 500,
              !command.contains("```"),
              isShellCommandStart(lines[0]) else { return nil }
        return command
    }

    private static func strippingInlineCodeDelimiters(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix("`") && result.hasSuffix("`") && result.count >= 2 {
            result = String(result.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func isShellLanguage(_ language: String) -> Bool {
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["bash", "sh", "shell", "zsh", "fish", "terminal", "console", "command", "cli"].contains(normalized)
    }

    private static func isShellCommandStart(_ line: String) -> Bool {
        let tokens = line.split { $0 == " " || $0 == "\t" }.map(String.init)
        guard let first = tokens.first else { return false }
        let wrappers = Set(["sudo", "env", "arch", "time", "nohup"])
        let token = wrappers.contains(first) && tokens.count > 1 ? tokens[1] : first
        if token.hasPrefix("./") || token.hasPrefix("../") { return true }
        let commands = Set([
            "brew", "bundle", "bun", "cargo", "cd", "chmod", "chown", "claude", "cmake", "codex", "cp", "curl",
            "deno", "defaults", "docker", "docker-compose", "find", "git", "gh", "go", "gradle", "grep", "hdiutil",
            "helm", "java", "make", "mkdir", "mvn", "node", "npm", "npx", "open", "pip", "pip3", "plutil",
            "pnpm", "poetry", "python", "python3", "rm", "rspec", "ruby", "sed", "security", "swift", "terraform",
            "tofu", "uv", "wget", "xcode-select", "xcodebuild", "xcrun", "yarn", "kubectl"
        ])
        return commands.contains(token)
    }

    private func openFilesForComposer() {
        activePicker = nil

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            panel.urls.forEach { appendDroppedPath($0.path) }
        }
    }

    private func handleDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let path = pathFromDroppedItem(item) {
                        appendDroppedPath(path)
                    }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                    if let path = item as? String {
                        appendDroppedPath(path)
                    }
                }
            }
        }
        return true
    }

    private func pathFromDroppedItem(_ item: NSSecureCoding?) -> String? {
        if let url = item as? URL {
            return url.path
        }
        if let data = item as? Data,
           let raw = String(data: data, encoding: .utf8),
           let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return url.path
        }
        if let raw = item as? String {
            return URL(string: raw)?.path ?? raw
        }
        return nil
    }

    private func appendDroppedPath(_ path: String) {
        DispatchQueue.main.async {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if !attachedPaths.contains(trimmed) {
                attachedPaths.append(trimmed)
            }
        }
    }

    private func copyMessage(_ message: ChatMessage) {
        copyText(message.text)
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func editQueuedRequest(_ request: QueuedChatRequest) {
        draftMessage = editableQueuedText(request.text)
        clearSuggestedCommand()
        attachedPaths.removeAll()
        chatState.cancelQueuedRequest(request.id)
    }

    private func editableQueuedText(_ text: String) -> String {
        var value = text.components(separatedBy: "\n\nAttached paths:\n").first ?? text
        value = value.components(separatedBy: "\n\nCurrent file:").first ?? value
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func editMessage(_ message: ChatMessage) {
        guard !chatState.status.isRunning else { return }
        editingMessageID = message.id
        draftMessage = message.text
        clearSuggestedCommand()
    }

    private func undoMessage(_ message: ChatMessage) {
        guard !chatState.status.isRunning else { return }
        chatState.removeMessageThread(message.id)
        if editingMessageID == message.id {
            editingMessageID = nil
            clearComposerText()
        }
    }

    private func addCustomModel() {
        let id = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        modelService.addCustomModel(id: id, cli: appState.selectedCLI)
        selectedModelID = id
        customModelInput = ""
        syncSelectedContextWindow()
        persistChatSelection()
        activePicker = nil
    }

    private func applyPersistedChatSelection() {
        permissionMode = appState.settings.chatPermissionMode
        selectedModelID = persistedModelID(for: appState.selectedCLI)
        normalizeSelectedModel()
    }

    private func persistedModelID(for cli: CLIType) -> String {
        cli.visibleValue == .codex ? appState.settings.selectedCodexModelID : appState.settings.selectedClaudeModelID
    }

    private func persistChatSelection() {
        appState.saveChatSelection(cli: appState.selectedCLI, permissionMode: permissionMode, modelID: selectedModelID)
    }

    private func normalizeSelectedModel() {
        let options = modelService.options(for: appState.selectedCLI)
        if !options.contains(where: { $0.id == selectedModelID }) {
            let executionModelID = ChatModelCatalog.executionModelID(for: selectedModelID)
            selectedModelID = options.first {
                ChatModelCatalog.executionModelID(for: $0.id) == executionModelID
            }?.id ?? modelService.defaultModelID(for: appState.selectedCLI)
        }
        syncSelectedContextWindow()
    }

    private func normalizeReasoningEffort() {
        let options = ChatReasoningEffort.options(for: appState.selectedCLI)
        if !options.contains(reasoningEffort) {
            reasoningEffort = options.contains(.xhigh) ? .xhigh : .high
        }
    }

    private func resetReasoningEffortToConfiguredDefault() {
        reasoningEffort = modelService.defaultReasoningEffort(for: appState.selectedCLI)
        normalizeReasoningEffort()
    }

    private var selectedContextModelID: String {
        modelService.contextModelID(for: selectedModelID, cli: appState.selectedCLI)
    }

    private func syncSelectedContextWindow() {
        chatState.syncContextWindow(modelID: selectedContextModelID)
    }

    private func iconOnlyButton(systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .regular))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .contentShape(Circle())
    }

    private func iconAction(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .medium))
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
        .contentShape(Rectangle())
        .help(help)
    }
}

private enum ChatTranscriptItem: Identifiable {
    case message(ChatMessage)
    case toolGroup(ToolInvocationGroup)
    case loading

    var id: String {
        switch self {
        case .message(let message):
            "message-\(message.id.uuidString)"
        case .toolGroup(let group):
            group.id
        case .loading:
            "loading"
        }
    }
}

private struct ToolInvocationGroup: Identifiable {
    let primary: ChatMessage
    let responses: [ChatMessage]

    var id: String { "tool-group-\(primary.id.uuidString)" }

    var detailText: String {
        ([primary] + responses)
            .map { message in
                message.isTerminalTool ? message.terminalDetailText : message.toolDetailText
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

private struct TranscriptScrollObserver: NSViewRepresentable {
    let onBottomStateChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onBottomStateChanged = onBottomStateChanged
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onBottomStateChanged = onBottomStateChanged
        nsView.attachIfNeeded()
    }

    final class ObserverView: NSView {
        var onBottomStateChanged: ((Bool) -> Void)?
        private weak var observedScrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var lastIsAtBottom: Bool?
        private let bottomTolerance: CGFloat = 16

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachIfNeeded()
            publishBottomState()
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func attachIfNeeded() {
            guard observedScrollView == nil else { return }
            guard let scrollView = nearestScrollView() else { return }
            observedScrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.publishBottomState()
            }
        }

        func publishBottomState() {
            guard let scrollView = observedScrollView ?? nearestScrollView() else { return }
            observedScrollView = scrollView
            guard let documentView = scrollView.documentView else { return }
            let visibleRect = documentView.visibleRect
            let documentBounds = documentView.bounds
            let distanceFromBottom: CGFloat
            if documentView.isFlipped {
                distanceFromBottom = documentBounds.maxY - visibleRect.maxY
            } else {
                distanceFromBottom = visibleRect.minY - documentBounds.minY
            }
            let isAtBottom = documentBounds.height <= visibleRect.height + bottomTolerance
                || distanceFromBottom <= bottomTolerance
            guard lastIsAtBottom != isAtBottom else { return }
            lastIsAtBottom = isAtBottom
            onBottomStateChanged?(isAtBottom)
        }

        private func nearestScrollView() -> NSScrollView? {
            if let enclosingScrollView {
                return enclosingScrollView
            }
            var current = superview
            while let view = current {
                if let scrollView = view as? NSScrollView {
                    return scrollView
                }
                current = view.superview
            }
            return nil
        }
    }
}

private struct ToolCodePreview {
    struct Line: Identifiable {
        let id = UUID()
        let marker: String
        let text: String
        let tint: Color
    }

    let title: String
    let path: String
    let stats: String
    let lines: [Line]
}

private struct FileReference: Identifiable, Hashable {
    let raw: String
    let path: String
    let line: Int?
    let column: Int?

    init(raw: String? = nil, path: String, line: Int? = nil, column: Int? = nil) {
        self.raw = raw ?? path
        self.path = path
        self.line = line
        self.column = column
    }

    var id: String { "\(path):\(line ?? 0):\(column ?? 0)" }

    var displayName: String {
        let fileName = (path as NSString).lastPathComponent
        guard let line else { return fileName }
        if let column { return "\(fileName):\(line):\(column)" }
        return "\(fileName):\(line)"
    }

    var openURL: URL? {
        var components = URLComponents()
        components.scheme = "acode-file"
        components.host = "open"
        var items = [URLQueryItem(name: "path", value: path)]
        if let line { items.append(URLQueryItem(name: "line", value: String(line))) }
        if let column { items.append(URLQueryItem(name: "column", value: String(column))) }
        components.queryItems = items
        return components.url
    }

    init?(openURL: URL) {
        guard openURL.scheme == "acode-file" else { return nil }
        let components = URLComponents(url: openURL, resolvingAgainstBaseURL: false)
        guard let path = components?.queryItems?.first(where: { $0.name == "path" })?.value, !path.isEmpty else { return nil }
        let line = components?.queryItems?.first(where: { $0.name == "line" })?.value.flatMap(Int.init)
        let column = components?.queryItems?.first(where: { $0.name == "column" })?.value.flatMap(Int.init)
        self.init(path: path, line: line, column: column)
    }
}

private struct FileLanguageStyle {
    let label: String
    let symbol: String
    let tint: Color

    static func forPath(_ path: String) -> FileLanguageStyle {
        let key = languageKey(for: path)
        switch key {
        case "swift", "xib", "storyboard", "xcconfig", "entitlements", "xcprivacy", "pbxproj":
            return FileLanguageStyle(label: "Swift", symbol: "chevron.left.forwardslash.chevron.right", tint: .orange)
        case "js", "jsx", "mjs", "cjs":
            return FileLanguageStyle(label: "JS", symbol: "curlybraces", tint: .yellow)
        case "ts", "tsx":
            return FileLanguageStyle(label: "TS", symbol: "curlybraces", tint: .blue)
        case "py", "pyw", "ipynb":
            return FileLanguageStyle(label: "Python", symbol: "chevron.left.forwardslash.chevron.right", tint: .blue)
        case "go":
            return FileLanguageStyle(label: "Go", symbol: "network", tint: .cyan)
        case "rs":
            return FileLanguageStyle(label: "Rust", symbol: "gearshape.2", tint: .brown)
        case "java", "kt", "kts", "scala", "gradle":
            return FileLanguageStyle(label: "JVM", symbol: "cup.and.saucer", tint: .red)
        case "c", "h", "m", "mm", "cc", "cpp", "cxx", "hpp", "cs", "fs", "vb":
            return FileLanguageStyle(label: "Native", symbol: "hammer", tint: .indigo)
        case "rb":
            return FileLanguageStyle(label: "Ruby", symbol: "diamond", tint: .red)
        case "php":
            return FileLanguageStyle(label: "PHP", symbol: "globe", tint: .indigo)
        case "r":
            return FileLanguageStyle(label: "R", symbol: "chart.xyaxis.line", tint: .blue)
        case "lua":
            return FileLanguageStyle(label: "Lua", symbol: "moon", tint: .blue)
        case "dart":
            return FileLanguageStyle(label: "Dart", symbol: "paperplane", tint: .cyan)
        case "ex", "exs":
            return FileLanguageStyle(label: "Elixir", symbol: "hexagon", tint: .purple)
        case "erl", "hrl":
            return FileLanguageStyle(label: "Erlang", symbol: "antenna.radiowaves.left.and.right", tint: .red)
        case "clj", "cljs":
            return FileLanguageStyle(label: "Clojure", symbol: "leaf", tint: .green)
        case "zig":
            return FileLanguageStyle(label: "Zig", symbol: "bolt", tint: .orange)
        case "html", "htm", "css", "scss", "sass", "less", "vue", "svelte":
            return FileLanguageStyle(label: "Web", symbol: "safari", tint: .pink)
        case "json", "jsonc", "plist", "xml", "yaml", "yml", "toml", "properties", "ini", "conf", "config", "gitignore", "editorconfig":
            return FileLanguageStyle(label: "Config", symbol: "slider.horizontal.3", tint: .purple)
        case "md", "markdown", "txt", "rtf":
            return FileLanguageStyle(label: "Doc", symbol: "doc.richtext", tint: .blue)
        case "sh", "bash", "zsh", "fish", "ps1", "makefile", "dockerfile", "env":
            return FileLanguageStyle(label: "Shell", symbol: "terminal", tint: .green)
        case "sql", "graphql", "gql", "proto", "csv", "tsv":
            return FileLanguageStyle(label: "Data", symbol: "tablecells", tint: .mint)
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "pdf":
            return FileLanguageStyle(label: "Asset", symbol: "photo", tint: .teal)
        case "diff", "patch":
            return FileLanguageStyle(label: "Diff", symbol: "plus.forwardslash.minus", tint: .orange)
        case "lock", "log":
            return FileLanguageStyle(label: "Log", symbol: "doc.text.magnifyingglass", tint: .secondary)
        default:
            return FileLanguageStyle(label: "File", symbol: "doc.text", tint: .secondary)
        }
    }

    private static func languageKey(for path: String) -> String {
        let name = (path as NSString).lastPathComponent.lowercased()
        let ext = (path as NSString).pathExtension.lowercased()
        if !ext.isEmpty { return ext }
        if name == "dockerfile" || name.hasPrefix("dockerfile.") { return "dockerfile" }
        if name == "makefile" || name.hasPrefix("makefile.") { return "makefile" }
        if name.hasPrefix(".env") { return "env" }
        return name
    }
}

private struct FileReferenceText: View {
    let text: String
    let font: Font
    let baseColor: Color
    let lineSpacing: CGFloat
    let parseMarkdown: Bool
    let onOpenFile: (FileReference) -> Void

    var body: some View {
        Text(FileReferenceDetector.attributedString(from: text, parseMarkdown: parseMarkdown, baseColor: baseColor))
            .font(font)
            .lineSpacing(lineSpacing)
            .environment(\.openURL, OpenURLAction { url in
                guard let reference = FileReference(openURL: url) else { return .systemAction }
                onOpenFile(reference)
                return .handled
            })
    }
}

private struct FileReferenceChips: View {
    let text: String
    let onOpenFile: (FileReference) -> Void

    private var references: [FileReference] {
        FileReferenceDetector.references(in: text)
    }

    var body: some View {
        let visibleReferences = Array(references.prefix(8))
        if !visibleReferences.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(visibleReferences) { reference in
                    FileReferenceButton(reference: reference, onOpenFile: onOpenFile)
                }
                if references.count > visibleReferences.count {
                    Text("+\(references.count - visibleReferences.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.035))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

private struct FileReferenceButton: View {
    let reference: FileReference
    let onOpenFile: (FileReference) -> Void

    private var style: FileLanguageStyle { .forPath(reference.path) }

    var body: some View {
        Button {
            onOpenFile(reference)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: style.symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(reference.displayName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(style.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(style.tint.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(reference.path)
    }
}

private final class FileReferenceListBox {
    let references: [FileReference]

    init(_ references: [FileReference]) {
        self.references = references
    }
}

private final class AttributedStringBox {
    let value: AttributedString

    init(_ value: AttributedString) {
        self.value = value
    }
}

private enum FileReferenceDetector {
    private static let maxScanLength = 40_000
    private static let maxReferences = 24
    private static let referenceCache: NSCache<NSString, FileReferenceListBox> = {
        let cache = NSCache<NSString, FileReferenceListBox>()
        cache.countLimit = 400
        return cache
    }()
    private static let attributedCache: NSCache<NSString, AttributedStringBox> = {
        let cache = NSCache<NSString, AttributedStringBox>()
        cache.countLimit = 240
        return cache
    }()
    private static let pathPattern = #"(?:(?:file://)?/(?:[^\s`\"'<>|])+|(?:[A-Za-z0-9_@.+~%-]+/)+(?:[A-Za-z0-9_@.+~%-]+)|[A-Za-z0-9_@.+~%-]+\.[A-Za-z0-9]{1,12})(?::\d+){0,2}"#
    private static let knownKeys: Set<String> = [
        "swift", "xib", "storyboard", "xcconfig", "entitlements", "xcprivacy", "pbxproj",
        "js", "jsx", "mjs", "cjs", "ts", "tsx", "py", "pyw", "ipynb", "go", "rs",
        "java", "kt", "kts", "scala", "gradle", "c", "h", "m", "mm", "cc", "cpp", "cxx", "hpp", "cs", "fs", "vb",
        "rb", "php", "r", "lua", "dart", "ex", "exs", "erl", "hrl", "clj", "cljs", "zig",
        "html", "htm", "css", "scss", "sass", "less", "vue", "svelte",
        "json", "jsonc", "plist", "xml", "yaml", "yml", "toml", "properties", "ini", "conf", "config", "md", "markdown", "txt", "rtf",
        "sh", "bash", "zsh", "fish", "ps1", "makefile", "dockerfile", "env",
        "sql", "graphql", "gql", "proto", "csv", "tsv", "png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "pdf",
        "diff", "patch", "lock", "log", "gitignore", "editorconfig"
    ]

    static func references(in text: String) -> [FileReference] {
        let key = cacheKey(prefix: "refs", text: text)
        if let cached = referenceCache.object(forKey: key) {
            return cached.references
        }
        let scanText = String(text.prefix(maxScanLength))
        guard let regex = try? NSRegularExpression(pattern: pathPattern) else { return [] }
        let range = NSRange(scanText.startIndex..<scanText.endIndex, in: scanText)
        var references: [FileReference] = []
        var seen: Set<String> = []

        for match in regex.matches(in: scanText, range: range) {
            guard references.count < maxReferences,
                  let swiftRange = Range(match.range, in: scanText),
                  let reference = reference(from: String(scanText[swiftRange])),
                  seen.insert(reference.id).inserted else { continue }
            references.append(reference)
        }
        referenceCache.setObject(FileReferenceListBox(references), forKey: key)
        return references
    }

    static func attributedString(from text: String, parseMarkdown: Bool, baseColor: Color) -> AttributedString {
        var attributed = baseAttributedString(from: text, parseMarkdown: parseMarkdown)
        attributed.foregroundColor = baseColor

        for reference in references(in: text) {
            guard let url = reference.openURL, let range = attributed.range(of: reference.raw) else { continue }
            attributed[range].link = url
            attributed[range].foregroundColor = FileLanguageStyle.forPath(reference.path).tint
        }
        return attributed
    }

    private static func baseAttributedString(from text: String, parseMarkdown: Bool) -> AttributedString {
        let key = cacheKey(prefix: parseMarkdown ? "md" : "text", text: text)
        if let cached = attributedCache.object(forKey: key) {
            return cached.value
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let attributed = parseMarkdown
            ? ((try? AttributedString(markdown: text, options: options)) ?? AttributedString(text))
            : AttributedString(text)
        attributedCache.setObject(AttributedStringBox(attributed), forKey: key)
        return attributed
    }

    private static func cacheKey(prefix: String, text: String) -> NSString {
        "\(prefix):\(text.count):\(text.hashValue)" as NSString
    }

    private static func reference(from rawValue: String) -> FileReference? {
        let raw = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "`\"'()[]{}<>，。；；、,.;"))
        guard !raw.isEmpty else { return nil }
        if raw.contains("://"), !raw.hasPrefix("file://") { return nil }

        var parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        var line: Int?
        var column: Int?
        if let last = parts.last, let value = Int(last) {
            column = value
            parts.removeLast()
        }
        if let last = parts.last, let value = Int(last) {
            line = value
            parts.removeLast()
        }
        if line == nil, let columnValue = column {
            line = columnValue
            column = nil
        }

        var path = parts.joined(separator: ":")
        if path.hasPrefix("file://"), let url = URL(string: path) {
            path = url.path
        }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path = String(path.dropFirst(2))
        }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "`\"'()[]{}<>，。；；、,.;"))
        guard !path.isEmpty, path != "/dev/null", isKnownFilePath(path) else { return nil }
        return FileReference(raw: raw, path: path, line: line, column: column)
    }

    private static func isKnownFilePath(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        let ext = (path as NSString).pathExtension.lowercased()
        if !ext.isEmpty { return knownKeys.contains(ext) }
        if name == "dockerfile" || name.hasPrefix("dockerfile.") { return true }
        if name == "makefile" || name.hasPrefix("makefile.") { return true }
        if name.hasPrefix(".env") { return true }
        return knownKeys.contains(name)
    }
}

private final class AssistantMessageBlockBox {
    let blocks: [AssistantMessageBlock]

    init(_ blocks: [AssistantMessageBlock]) {
        self.blocks = blocks
    }
}

private struct AssistantMessageContent: View {
    private static let blockCache = NSCache<NSString, AssistantMessageBlockBox>()

    let text: String
    let isStreaming: Bool
    let onOpenFile: (FileReference) -> Void

    private let lightweightThreshold = 12_000
    private let previewLimit = 20_000

    private var shouldUseLightweightRender: Bool {
        isStreaming || text.count > lightweightThreshold
    }

    private var previewText: String {
        guard text.count > previewLimit else { return text }
        return String(text.prefix(previewLimit)) + "\n\n…输出过长，已暂停完整渲染；复制消息可获取完整内容。"
    }

    private var blocks: [AssistantMessageBlock] {
        guard !isStreaming else { return AssistantMessageBlock.parse(text) }
        let key = "\(text.count):\(text.hashValue)" as NSString
        if let cached = Self.blockCache.object(forKey: key) {
            return cached.blocks
        }
        let parsed = AssistantMessageBlock.parse(text)
        Self.blockCache.setObject(AssistantMessageBlockBox(parsed), forKey: key)
        return parsed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isStreaming {
                Text(previewText)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if shouldUseLightweightRender {
                FileReferenceText(
                    text: previewText,
                    font: .system(size: 12),
                    baseColor: .primary,
                    lineSpacing: 3,
                    parseMarkdown: false,
                    onOpenFile: onOpenFile
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: AssistantMessageBlock) -> some View {
        switch block {
        case .text(let value):
            FileReferenceText(
                text: value,
                font: .system(size: 12),
                baseColor: .primary,
                lineSpacing: 3,
                parseMarkdown: true,
                onOpenFile: onOpenFile
            )
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            FileReferenceChips(text: value, onOpenFile: onOpenFile)
        case .code(let language, let code):
            AssistantCodeBlockView(language: language, code: code)
        case .table(let value):
            ScrollView(.horizontal, showsIndicators: true) {
                Text(String(value.prefix(12_000)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
        }
    }

    private func inlineMarkdown(_ value: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: value, options: options)) ?? AttributedString(value)
    }
}

private struct AssistantCodeBlockView: View {
    let language: String
    let code: String

    private let previewLimit = 16_000

    private var previewCode: String {
        guard code.count > previewLimit else { return code }
        return String(code.prefix(previewLimit)) + "\n\n…代码过长，已暂停完整渲染；点击 copy 可复制完整代码。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                        Text("copy")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("复制代码")
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.035))

            ScrollView(.horizontal, showsIndicators: true) {
                Text(previewCode)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.black.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }
}

private enum AssistantMessageBlock {
    case text(String)
    case code(language: String, code: String)
    case table(String)

    static func parse(_ text: String) -> [AssistantMessageBlock] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [AssistantMessageBlock] = []
        var textBuffer: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage = ""
        var isInCodeBlock = false

        func flushText() {
            let value = textBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            textBuffer.removeAll()
            guard !value.isEmpty else { return }
            appendTextOrTable(value, to: &blocks)
        }

        for line in lines {
            if let language = fenceLanguage(from: line) {
                if isInCodeBlock {
                    blocks.append(.code(language: codeLanguage, code: codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll()
                    codeLanguage = ""
                    isInCodeBlock = false
                } else {
                    flushText()
                    codeLanguage = language
                    isInCodeBlock = true
                }
            } else if isInCodeBlock {
                codeBuffer.append(line)
            } else {
                textBuffer.append(line)
            }
        }

        if isInCodeBlock {
            blocks.append(.code(language: codeLanguage, code: codeBuffer.joined(separator: "\n")))
        }
        flushText()

        return blocks.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [.text(text)] : blocks
    }

    private static func appendTextOrTable(_ value: String, to blocks: inout [AssistantMessageBlock]) {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var buffer: [String] = []
        var tableBuffer: [String] = []

        func flushBuffer() {
            let text = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeAll()
            if !text.isEmpty { blocks.append(.text(text)) }
        }

        func flushTable() {
            let table = tableBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            tableBuffer.removeAll()
            if !table.isEmpty { blocks.append(.table(table)) }
        }

        var index = 0
        while index < lines.count {
            if let tableRange = tableRangeStart(in: lines, at: index) {
                flushBuffer()
                tableBuffer.append(contentsOf: lines[tableRange])
                flushTable()
                index = tableRange.upperBound
            } else {
                buffer.append(lines[index])
                index += 1
            }
        }
        flushTable()
        flushBuffer()
    }

    private static func fenceLanguage(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return nil }
        return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tableRangeStart(in lines: [String], at index: Int) -> Range<Int>? {
        guard index + 1 < lines.count,
              isPotentialTableRow(lines[index]),
              isTableSeparator(lines[index + 1]) else { return nil }
        var end = index + 2
        while end < lines.count && isPotentialTableRow(lines[end]) {
            end += 1
        }
        return index..<end
    }

    private static func isPotentialTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("|") else { return false }
        return trimmed.first == "|" || trimmed.last == "|" || trimmed.contains(" | ")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("|") else { return false }
        let allowed = CharacterSet(charactersIn: "|-: ")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
            && trimmed.contains("---")
    }
}

private struct ChatInteractiveRequestCard: View {
    let message: ChatMessage
    @ObservedObject var chatState: ChatPanelState
    @State private var selectedOptionIDs: Set<String> = []
    @State private var customText = ""

    private var request: ChatInteractiveRequest? { message.interactiveRequest }
    private var isWaiting: Bool { request?.status == .waiting || message.status == ChatInteractiveStatus.waiting.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(request?.title.nonEmptyTrimmed ?? message.title.nonEmptyTrimmed ?? "需要选择")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(request?.prompt.nonEmptyTrimmed ?? message.text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let request, isWaiting {
                switch request.mode {
                case .singleChoice:
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(request.options) { option in
                            Button {
                                submit(selectedIDs: [option.id], customText: nil)
                            } label: {
                                optionRow(option, selected: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                case .multipleChoice:
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(request.options) { option in
                            Button {
                                if selectedOptionIDs.contains(option.id) {
                                    selectedOptionIDs.remove(option.id)
                                } else {
                                    selectedOptionIDs.insert(option.id)
                                }
                            } label: {
                                optionRow(option, selected: selectedOptionIDs.contains(option.id))
                            }
                            .buttonStyle(.plain)
                        }
                        Button("提交选择") {
                            submit(selectedIDs: Array(selectedOptionIDs), customText: nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(selectedOptionIDs.isEmpty)
                    }
                case .text:
                    textInput(request)
                }

                if request.allowCustomInput && request.mode != .text {
                    textInput(request)
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionRow(_ option: ChatInteractiveOption, selected: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? Color.primary : Color.secondary.opacity(0.45))
            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                if !option.detail.isEmpty {
                    Text(option.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func textInput(_ request: ChatInteractiveRequest) -> some View {
        HStack(spacing: 6) {
            TextField(request.placeholder.isEmpty ? "输入回复" : request.placeholder, text: $customText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            Button("发送") {
                submit(selectedIDs: [], customText: customText)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submit(selectedIDs: [String], customText: String?) {
        guard let request else { return }
        chatState.respondToInteractiveRequest(ChatInteractiveResponse(
            requestID: request.id,
            selectedOptionIDs: selectedIDs,
            customText: customText?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyTrimmed
        ))
    }
}

private struct ComposerSuggestedCommand: Equatable {
    let text: String
}

private struct SubagentDetailRequest: Identifiable, Equatable {
    let agentID: String?
    let agentType: String
    let description: String
    let projectPath: String?

    var id: String { agentID ?? "pending-\(agentType)-\(description)" }
}

private struct SubagentTranscriptSheet: View {
    let request: SubagentDetailRequest
    @Environment(\.dismiss) private var dismiss
    @State private var transcript: SubagentTranscript?
    @State private var isPaused = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent process")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text(headerSubtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(isPaused ? "resume" : "pause") {
                    isPaused.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                Button("refresh") { refreshTranscript() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("close") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(14)

            Divider().opacity(0.28)

            if let transcript {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(transcript.messages) { message in
                            SubagentTranscriptMessageRow(message: message)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("waiting for agent transcript")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("日志写入后会自动刷新；这里只读展示，不会影响后台运行。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(18)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear { refreshTranscript() }
        .onReceive(Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()) { _ in
            guard !isPaused else { return }
            refreshTranscript()
        }
    }

    private var headerSubtitle: String {
        let transcriptType = transcript?.agentType.nonEmptyTrimmed
        let type = transcriptType ?? request.agentType
        let description = transcript?.description.nonEmptyTrimmed ?? request.description
        let idText = request.agentID.map { "agent-\($0.prefix(8))" } ?? "pending"
        return "\(type) · \(description) · \(idText)"
    }

    private func refreshTranscript() {
        let nextTranscript: SubagentTranscript?
        if let agentID = request.agentID {
            nextTranscript = SubagentTranscriptStore.load(agentID: agentID, projectPath: request.projectPath)
        } else {
            nextTranscript = SubagentTranscriptStore.find(agentType: request.agentType, description: request.description, projectPath: request.projectPath)
        }
        if transcript != nextTranscript {
            transcript = nextTranscript
        }
    }
}

private struct SubagentTranscriptMessageRow: View {
    let message: SubagentTranscriptMessage

    var body: some View {
        switch message.kind {
        case .user:
            HStack(alignment: .top) {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        case .assistant:
            AssistantMessageContent(text: message.text, isStreaming: false, onOpenFile: { _ in })
                .frame(maxWidth: .infinity, alignment: .leading)
        case .reasoning:
            SubagentSmallCard(message: message)
        case .toolCall:
            SubagentSmallCard(message: message)
        case .toolResult:
            SubagentSmallCard(message: message)
        case .raw:
            SubagentSmallCard(message: message)
        }
    }
}

private struct SubagentSmallCard: View {
    let message: SubagentTranscriptMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(message.title.isEmpty ? message.kind.rawValue : message.title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !message.subtitle.isEmpty {
                    Text(message.subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(statusText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if !message.text.isEmpty {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(previewText)
                        .font(.system(size: 10, design: message.kind == .toolCall || message.kind == .toolResult ? .monospaced : .default))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.leading, 12)
    }

    private var previewText: String {
        guard message.text.count > 18_000 else { return message.text }
        return String(message.text.prefix(18_000)) + "\n\n…内容过长，已暂停完整渲染。"
    }

    private var statusText: String {
        message.status == "failed" ? "失败" : "完成"
    }
}

private struct ChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var hasMarkedText: Bool
    @Binding var suggestedCommand: ComposerSuggestedCommand?
    @Binding var measuredHeight: CGFloat
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            hasMarkedText: $hasMarkedText,
            suggestedCommand: $suggestedCommand,
            measuredHeight: $measuredHeight,
            onSubmit: onSubmit
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = SubmitTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onMarkedTextChanged = { context.coordinator.hasMarkedText = $0 }
        textView.onSuggestedCommandCleared = { context.coordinator.suggestedCommand = nil }
        textView.suggestedCommand = suggestedCommand
        textView.string = text
        textView.font = .systemFont(ofSize: 12)
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        context.coordinator.updateMeasuredHeight(for: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmitTextView else { return }
        textView.onSubmit = onSubmit
        textView.onMarkedTextChanged = { context.coordinator.hasMarkedText = $0 }
        textView.onSuggestedCommandCleared = { context.coordinator.suggestedCommand = nil }
        textView.isEditable = true
        textView.isSelectable = true
        if textView.hasMarkedText() {
            context.coordinator.hasMarkedText = true
            return
        }
        textView.suggestedCommand = suggestedCommand
        if textView.string != text {
            let isFocused = textView.window?.firstResponder === textView
            let isProgrammaticReplacement = text.isEmpty || suggestedCommand?.text == text
            if !isFocused || isProgrammaticReplacement {
                textView.string = text
                if suggestedCommand?.text == text {
                    textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
                }
            }
        }
        textView.refreshSuggestedCommandHighlight()
        context.coordinator.updateMeasuredHeight(for: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var hasMarkedText: Bool
        @Binding var suggestedCommand: ComposerSuggestedCommand?
        @Binding var measuredHeight: CGFloat
        let onSubmit: () -> Void

        init(
            text: Binding<String>,
            hasMarkedText: Binding<Bool>,
            suggestedCommand: Binding<ComposerSuggestedCommand?>,
            measuredHeight: Binding<CGFloat>,
            onSubmit: @escaping () -> Void
        ) {
            _text = text
            _hasMarkedText = hasMarkedText
            _suggestedCommand = suggestedCommand
            _measuredHeight = measuredHeight
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? SubmitTextView else { return }
            let isComposing = textView.hasMarkedText()
            hasMarkedText = isComposing
            guard !isComposing else { return }
            text = textView.string
            if let suggestedCommand, textView.string != suggestedCommand.text {
                self.suggestedCommand = nil
                textView.suggestedCommand = nil
            }
            textView.refreshSuggestedCommandHighlight()
            updateMeasuredHeight(for: textView)
        }

        func updateMeasuredHeight(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
            textContainer.containerSize = NSSize(width: max(textView.bounds.width, 1), height: CGFloat.greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)
            let contentHeight = ceil(layoutManager.usedRect(for: textContainer).height)
            measuredHeight = min(160, max(42, contentHeight + 10))
        }
    }

    final class SubmitTextView: NSTextView {
        var onSubmit: (() -> Void)?
        var onMarkedTextChanged: ((Bool) -> Void)?
        var onSuggestedCommandCleared: (() -> Void)?
        var suggestedCommand: ComposerSuggestedCommand?

        override func keyDown(with event: NSEvent) {
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            let isBackspace = event.keyCode == 51
            let isForwardDelete = event.keyCode == 117
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasSubmitModifier = flags.contains(.shift) || flags.contains(.option) || flags.contains(.control) || flags.contains(.command)
            if isReturn, hasMarkedText() {
                super.keyDown(with: event)
                onMarkedTextChanged?(hasMarkedText())
                return
            }
            if isReturn && !hasSubmitModifier {
                onSubmit?()
                return
            }
            if !hasMarkedText(), isSuggestedCommandDeletion(backspace: isBackspace, forwardDelete: isForwardDelete), deleteSuggestedCommand(backspace: isBackspace) {
                return
            }
            super.keyDown(with: event)
        }

        func refreshSuggestedCommandHighlight() {
            guard !hasMarkedText() else { return }
            let fullRange = NSRange(location: 0, length: (string as NSString).length)
            layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
            layoutManager?.removeTemporaryAttribute(.font, forCharacterRange: fullRange)
            guard let suggestedCommand, string == suggestedCommand.text, fullRange.length > 0 else { return }
            layoutManager?.addTemporaryAttributes([
                .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.12),
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            ], forCharacterRange: fullRange)
        }

        private func isSuggestedCommandDeletion(backspace: Bool, forwardDelete: Bool) -> Bool {
            backspace || forwardDelete
        }

        private func deleteSuggestedCommand(backspace: Bool) -> Bool {
            guard let suggestedCommand, string == suggestedCommand.text else { return false }
            let fullRange = NSRange(location: 0, length: (string as NSString).length)
            guard fullRange.length > 0 else { return false }
            let selection = selectedRange()
            let shouldDelete: Bool
            if selection.length > 0 {
                shouldDelete = NSIntersectionRange(selection, fullRange).length > 0
            } else if backspace {
                shouldDelete = selection.location > 0 && selection.location <= NSMaxRange(fullRange)
            } else {
                shouldDelete = selection.location >= fullRange.location && selection.location < NSMaxRange(fullRange)
            }
            guard shouldDelete, shouldChangeText(in: fullRange, replacementString: "") else { return false }
            textStorage?.replaceCharacters(in: fullRange, with: "")
            didChangeText()
            self.suggestedCommand = nil
            onSuggestedCommandCleared?()
            refreshSuggestedCommandHighlight()
            return true
        }

        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            publishMarkedTextState()
        }

        override func unmarkText() {
            super.unmarkText()
            publishMarkedTextState()
        }

        private func publishMarkedTextState() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onMarkedTextChanged?(self.hasMarkedText())
            }
        }
    }
}

private struct ToolInvocationSummary {
    let primaryTitle: String
    let plainSummary: String?
    let isAgentTool: Bool
    let subagentID: String?
}

private final class ToolInvocationSummaryBox {
    let value: ToolInvocationSummary

    init(_ value: ToolInvocationSummary) {
        self.value = value
    }
}

private enum ToolInvocationSummaryCache {
    private static let cache: NSCache<NSString, ToolInvocationSummaryBox> = {
        let cache = NSCache<NSString, ToolInvocationSummaryBox>()
        cache.countLimit = 800
        return cache
    }()

    static func summary(for message: ChatMessage) -> ToolInvocationSummary {
        let key = "\(message.id.uuidString):\(message.status):\(message.isStreaming):\(message.text.count):\(message.text.hashValue)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached.value
        }
        let summary = ToolInvocationSummary(
            primaryTitle: message.toolPrimaryTitle,
            plainSummary: message.toolPlainSummary,
            isAgentTool: message.isAgentTool,
            subagentID: message.subagentID
        )
        cache.setObject(ToolInvocationSummaryBox(summary), forKey: key)
        return summary
    }
}

private extension ChatMessageKind {
    var isToolDetailMonospaced: Bool {
        switch self {
        case .toolCall, .toolResult, .command, .commandOutput:
            true
        case .user, .assistant, .reasoning, .permissionRequest, .interactiveRequest, .diff, .error, .system, .result, .rawOutput:
            false
        }
    }

    var isVisibleInTranscript: Bool {
        switch self {
        case .system, .result, .rawOutput:
            false
        case .user, .assistant, .reasoning, .toolCall, .toolResult, .command, .commandOutput, .permissionRequest, .interactiveRequest, .diff, .error:
            true
        }
    }
}

private extension ChatMessage {
    var isToolInvocationStart: Bool {
        kind == .toolCall || kind == .command
    }

    var isToolInvocationBoundary: Bool {
        switch kind {
        case .user, .assistant, .reasoning, .permissionRequest, .interactiveRequest, .error:
            true
        case .toolCall, .command:
            true
        case .toolResult, .commandOutput, .diff, .system, .result, .rawOutput:
            false
        }
    }

    func isToolInvocationFeedback(for primary: ChatMessage) -> Bool {
        switch (primary.kind, kind) {
        case (.command, .commandOutput), (.toolCall, .toolResult):
            if let primaryID = primary.toolCorrelationID, let feedbackID = toolCorrelationID {
                return primaryID == feedbackID
            }
            return primary.requestID == nil && requestID == nil
        default:
            return false
        }
    }

    var toolCorrelationID: String? {
        requestID?.nonEmptyTrimmed
            ?? firstToolStringValue(keys: ["tool_use_id", "toolUseId", "tool_use", "call_id", "callId", "item_id", "itemId", "command_id", "commandId", "id"], in: text)
    }

    var toolDisplayTitle: String {
        toolPrimaryTitle
    }

    var toolPrimaryTitle: String {
        if let name = normalizedToolName(title) ?? normalizedToolName(subtitle) {
            return displayToolName(name)
        }
        switch kind {
        case .toolCall, .toolResult:
            return "tool"
        case .command:
            return "command"
        case .commandOutput:
            return "output"
        case .diff:
            return "diff"
        default:
            return "tool"
        }
    }

    var toolDetailLabel: String {
        if kind == .diff { return "diff" }
        if isTerminalTool { return "terminal" }
        return "details"
    }

    var toolActionSummary: String {
        switch toolName.lowercased() {
        case "read": return "读取文件内容"
        case "grep": return "搜索代码匹配"
        case "glob": return "匹配文件列表"
        case "edit": return "修改已有文件"
        case "write": return "写入文件内容"
        case "bash": return "执行终端命令"
        default:
            if kind == .diff { return "代码变更预览" }
            if isTerminalTool { return "执行终端任务" }
            if kind == .toolResult { return "工具返回结果" }
            return "调用工具"
        }
    }

    var toolSystemImage: String {
        switch toolName.lowercased() {
        case "read": return "doc.text.magnifyingglass"
        case "grep": return "magnifyingglass"
        case "glob": return "folder"
        case "edit": return "pencil.line"
        case "write": return "square.and.pencil"
        case "bash": return "terminal"
        default:
            if kind == .diff { return "plus.forwardslash.minus" }
            if isTerminalTool { return "terminal" }
            if kind == .toolResult { return "checkmark.seal" }
            return "hammer"
        }
    }

    var toolTint: Color {
        let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedStatus.contains("fail") || normalizedStatus.contains("error") { return .red }
        if normalizedStatus == "stopped" { return .secondary }
        switch toolName.lowercased() {
        case "read", "grep", "glob": return .blue
        case "edit": return .orange
        case "write": return .green
        case "bash": return .purple
        default:
            if kind == .diff { return .orange }
            if kind == .toolResult { return .green }
            return .secondary
        }
    }

    var toolStatusLabel: String {
        if isStreaming { return "运行中" }
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("fail") || normalized.contains("error") { return "失败" }
        if normalized == "stopped" { return "已停止" }
        if normalized == "done" || normalized == "success" || normalized == "completed" { return "完成" }
        return normalized.isEmpty ? "完成" : status
    }

    var isAgentTool: Bool {
        toolName.lowercased() == "agent" || subagentID != nil
    }

    var subagentID: String? {
        if let value = firstToolStringValue(keys: ["agentId", "agent_id"], in: text) {
            return Self.normalizedAgentID(value)
        }
        return Self.agentID(from: text)
    }

    var subagentDisplayTitle: String {
        let type = subagentType ?? "Agent"
        if let description = subagentDescription {
            return "\(type) · \(description)"
        }
        return type
    }

    var subagentPrompt: String? {
        firstToolStringValue(keys: ["prompt", "instruction", "instructions"], in: text).map { Self.previewSnippet($0, limit: 420) }
    }

    var subagentResultSummary: String? {
        Self.firstUsefulLine(toolDetailText).map { Self.previewSnippet($0, limit: 420) }
    }

    func subagentDetailRequest(projectPath: String?) -> SubagentDetailRequest? {
        guard isAgentTool else { return nil }
        return SubagentDetailRequest(
            agentID: subagentID,
            agentType: subagentType ?? "Agent",
            description: subagentDescription ?? subagentResultSummary ?? "子代理",
            projectPath: projectPath
        )
    }

    private var subagentType: String? {
        firstToolStringValue(keys: ["subagent_type", "subagentType", "agentType", "agent_type"], in: text)
    }

    private var subagentDescription: String? {
        firstToolStringValue(keys: ["description", "summary", "title"], in: text)
    }

    var toolPlainSummary: String? {
        switch toolName.lowercased() {
        case "read", "edit", "write":
            return toolFilePath.map(Self.displayFileName)
        case "grep":
            if let path = toolFilePath { return Self.displayFileName(path) }
            return firstToolStringValue(keys: ["pattern", "query", "regex"], in: text).map { Self.previewSnippet($0, limit: 56) }
        case "glob":
            return firstToolStringValue(keys: ["pattern", "glob", "path"], in: text).map { Self.previewSnippet($0, limit: 56) }
        case "bash":
            return toolExecutedCommand.map { Self.previewSnippet($0, limit: 72) }
        default:
            if isAgentTool { return subagentDisplayTitle }
            if kind == .diff { return toolFilePath.map(Self.displayFileName) }
            if let path = toolFilePath { return Self.displayFileName(path) }
            if let command = toolExecutedCommand { return Self.previewSnippet(command, limit: 72) }
            return Self.firstUsefulLine(toolDetailText).map { Self.previewSnippet($0, limit: 72) }
        }
    }

    var toolExecutionSummary: String? {
        switch toolName.lowercased() {
        case "read":
            if let path = toolFilePath { return "读取 \(Self.displayFileName(path))" }
            return "读取文件内容"
        case "grep":
            if let pattern = firstToolStringValue(keys: ["pattern", "query", "regex"], in: text) {
                return "搜索 \(Self.previewSnippet(pattern))"
            }
            return "搜索代码匹配"
        case "glob":
            if let pattern = firstToolStringValue(keys: ["pattern", "glob", "path"], in: text) {
                return "匹配 \(Self.previewSnippet(pattern))"
            }
            return "匹配文件列表"
        case "edit":
            if let path = toolFilePath { return "编辑 \(Self.displayFileName(path))" }
            if let replacement = firstToolStringValue(keys: ["new_string", "newString", "replacement"], in: text) {
                return "替换为 \(Self.previewSnippet(replacement))"
            }
            return "编辑文件"
        case "write":
            if let path = toolFilePath { return "写入 \(Self.displayFileName(path))" }
            return "写入文件"
        case "bash":
            if let command = toolExecutedCommand { return "$ \(Self.previewSnippet(command, limit: 86))" }
            return "执行终端命令"
        default:
            if kind == .diff, let path = toolFilePath { return "变更 \(Self.displayFileName(path))" }
            if let command = toolExecutedCommand { return "$ \(Self.previewSnippet(command, limit: 86))" }
            if let path = toolFilePath { return Self.displayFileName(path) }
            return Self.firstUsefulLine(toolDetailText).map { Self.previewSnippet($0) }
        }
    }

    var toolExecutionSystemImage: String {
        switch toolName.lowercased() {
        case "read": return "doc.text.magnifyingglass"
        case "grep": return "magnifyingglass"
        case "glob": return "folder.badge.gearshape"
        case "edit": return "text.cursor"
        case "write": return "square.and.pencil"
        case "bash": return "terminal"
        default:
            if kind == .diff { return "plus.forwardslash.minus" }
            if isTerminalTool { return "terminal" }
            return "info.circle"
        }
    }

    var toolMetricsSummary: String? {
        if kind == .diff, let stats = diffStatsSummary { return stats }
        let detail = toolDetailText
        let byteCount = text.utf8.count
        let lineCount = detail.split(separator: "\n", omittingEmptySubsequences: false).count
        if lineCount > 1 {
            return "返回 \(lineCount) 行 · \(Self.formattedByteCount(byteCount))"
        }
        if byteCount > 0 {
            return "返回 \(Self.formattedByteCount(byteCount))"
        }
        return nil
    }

    private var diffStatsSummary: String? {
        let added = diffLines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
        let removed = diffLines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
        guard added > 0 || removed > 0 else { return nil }
        return "变更 +\(added) / -\(removed)"
    }

    var toolCodePreview: ToolCodePreview? {
        if kind == .diff {
            return diffCodePreview
        }
        switch toolName.lowercased() {
        case "edit":
            return editCodePreview
        case "write":
            return writeCodePreview
        default:
            return nil
        }
    }

    private var diffCodePreview: ToolCodePreview? {
        let path = toolFilePath ?? "changes.diff"
        let lines = diffLines
            .filter { !$0.hasPrefix("diff --git") && !$0.hasPrefix("+++") && !$0.hasPrefix("---") && !$0.hasPrefix("@@") }
            .prefix(10)
            .map(Self.previewLine(from:))
        guard !lines.isEmpty else { return nil }
        return ToolCodePreview(title: Self.displayFileName(path), path: path, stats: diffStatsSummary ?? "代码变更", lines: lines)
    }

    private var editCodePreview: ToolCodePreview? {
        guard let path = toolFilePath else { return nil }
        var lines: [ToolCodePreview.Line] = []
        if let oldValue = firstToolStringValue(keys: ["old_string", "oldString", "old", "before"], in: text) {
            lines.append(contentsOf: Self.previewContentLines(oldValue, marker: "-", tint: .red, limit: 3))
        }
        if let newValue = firstToolStringValue(keys: ["new_string", "newString", "replacement", "after"], in: text) {
            lines.append(contentsOf: Self.previewContentLines(newValue, marker: "+", tint: .green, limit: 5))
        }
        guard !lines.isEmpty else { return nil }
        return ToolCodePreview(title: Self.displayFileName(path), path: path, stats: diffStatsSummary ?? "编辑预览", lines: Array(lines.prefix(8)))
    }

    private var writeCodePreview: ToolCodePreview? {
        guard let path = toolFilePath,
              let content = firstToolStringValue(keys: ["content", "text", "source", "new_string", "newString"], in: text) else { return nil }
        let lines = Self.previewContentLines(content, marker: "+", tint: .green, limit: 8)
        guard !lines.isEmpty else { return nil }
        let lineCount = content.split(separator: "\n", omittingEmptySubsequences: false).count
        return ToolCodePreview(title: Self.displayFileName(path), path: path, stats: "写入 \(lineCount) 行", lines: lines)
    }

    var isTerminalTool: Bool {
        if kind == .command || kind == .commandOutput { return true }
        let values = [title, subtitle, toolPrimaryTitle].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return values.contains { value in
            value == "bash" || value == "shell" || value == "command" || value == "exec" || value.contains("commandexecution")
        }
    }

    var toolExecutedCommand: String? {
        guard !isBackendLaunchCommand else { return nil }
        if let value = firstToolStringValue(keys: ["command", "cmd", "shell_command", "shellCommand"], in: text) {
            return value
        }
        return textCommandValue(from: text)
    }

    var terminalOutputText: String {
        if let value = firstToolStringValue(keys: ["stderr", "stdout", "output", "result", "error", "message", "text"], in: text) {
            return value
        }
        guard kind == .commandOutput || kind == .toolResult else { return "" }
        return toolDetailText
    }

    var terminalDetailText: String {
        var parts: [String] = []
        let commandText = toolExecutedCommand
        if let commandText {
            parts.append("$ \(commandText)")
        }
        let output = terminalOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty {
            if let commandText, output == commandText {
                return parts.joined(separator: "\n\n")
            }
            parts.append(output)
        }
        return parts.joined(separator: "\n\n")
    }

    var terminalDetailPreviewText: String {
        let detail = terminalDetailText
        guard detail.count > 16_000 else { return detail }
        return String(detail.prefix(16_000)) + "\n\n…终端输出过长，已暂停完整渲染；复制详情可获取完整内容。"
    }

    var toolDetailText: String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "" }
        if let visual = visualFormattedJSONObject(body) {
            return visual
        }
        let filtered = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isInternalToolNoiseLine }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return filtered
    }

    var toolDetailPreviewText: String {
        let detail = toolDetailText
        guard detail.count > 16_000 else { return detail }
        return String(detail.prefix(16_000)) + "\n\n…详情过长，已暂停完整渲染；复制详情可获取完整内容。"
    }

    var toolFilePath: String? {
        if let path = jsonToolFilePath(from: text) {
            return path
        }
        if let loosePath = firstToolStringValue(keys: ["file_path", "filePath", "filepath", "path", "filename", "notebook_path"], in: text),
           let path = normalizedToolPath(loosePath) {
            return path
        }
        for value in [title, subtitle, text] {
            if let path = textToolFilePath(from: value) {
                return path
            }
        }
        return nil
    }

    var isBackendLaunchCommand: Bool {
        guard kind == .command else { return false }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedTitle == "claude" || normalizedTitle == "codex" else { return false }
        let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedStatus == "start"
            || body.contains(" --output-format stream-json")
            || body.contains(" app-server")
    }

    private var toolName: String {
        (normalizedToolName(title) ?? normalizedToolName(subtitle)) ?? ""
    }

    private func normalizedToolName(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("{"), !value.contains("}") else { return nil }
        let normalized = value.lowercased().replacingOccurrences(of: "_", with: " ")
        let blocked = Set([
            "tool use", "tool result", "input json delta", "json delta", "content block", "content block delta",
            "item started", "item completed", "message start", "message stop", "raw", "done"
        ])
        guard !blocked.contains(normalized), !normalized.contains("json delta") else { return nil }
        if value.contains("/") && value.lowercased().contains("item/") { return nil }
        return value
    }

    private func displayToolName(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "bash": return "Bash"
        case "read": return "Read"
        case "edit": return "Edit"
        case "write": return "Write"
        default: return value
        }
    }

    private func firstToolStringValue(keys: [String], in body: String) -> String? {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let value = firstToolStringValue(in: object, keySet: Set(keys.map { $0.lowercased() })) {
            return value
        }
        return looseToolStringValue(keys: keys, in: body)
    }

    private func firstToolStringValue(in object: Any, keySet: Set<String>) -> String? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary where keySet.contains(key.lowercased()) {
                if let text = readableToolValue(value) {
                    return text
                }
            }
            for value in dictionary.values {
                if let text = firstToolStringValue(in: value, keySet: keySet) {
                    return text
                }
            }
        }
        if let array = object as? [Any] {
            for value in array {
                if let text = firstToolStringValue(in: value, keySet: keySet) {
                    return text
                }
            }
        }
        return nil
    }

    private func looseToolStringValue(keys: [String], in body: String) -> String? {
        for key in keys {
            let quotedMarkers = ["\"\(key)\":\"", "\"\(key)\": \""]
            for marker in quotedMarkers {
                guard let range = body.range(of: marker) else { continue }
                let tail = body[range.upperBound...]
                var value = ""
                var isEscaped = false
                for character in tail {
                    if isEscaped {
                        value.append(character)
                        isEscaped = false
                    } else if character == "\\" {
                        isEscaped = true
                    } else if character == "\"" {
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { return trimmed }
                        break
                    } else {
                        value.append(character)
                    }
                }
            }
        }
        return nil
    }

    private func textCommandValue(from value: String) -> String? {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("$ ") {
                let command = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !command.isEmpty { return command }
            }
            let prefixes = ["command:", "cmd:"]
            for prefix in prefixes where trimmed.lowercased().hasPrefix(prefix) {
                let command = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !command.isEmpty { return command }
            }
        }
        return nil
    }

    private func jsonToolFilePath(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return firstToolPath(in: object)
    }

    private func firstToolPath(in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            let keys = ["filePath", "file_path", "filepath", "path", "filename", "file"]
            for key in keys {
                if let value = dictionary[key] {
                    if let string = value as? String, let path = normalizedToolPath(string) {
                        return path
                    }
                    if let nested = firstToolPath(in: value) {
                        return nested
                    }
                }
            }
            for value in dictionary.values {
                if let path = firstToolPath(in: value) {
                    return path
                }
            }
        }
        if let array = object as? [Any] {
            for value in array {
                if let path = firstToolPath(in: value) {
                    return path
                }
            }
        }
        return nil
    }

    private func textToolFilePath(from value: String) -> String? {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("diff --git a/"), let range = trimmed.range(of: " b/") {
                let path = String(trimmed[range.upperBound...])
                if let normalized = normalizedToolPath(path) { return normalized }
            }
            if trimmed.hasPrefix("+++ ") || trimmed.hasPrefix("--- ") {
                let path = trimmed.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
                if let normalized = normalizedToolPath(path) { return normalized }
            }
            let prefixes = ["path:", "file:", "filePath:", "file_path:"]
            for prefix in prefixes where trimmed.hasPrefix(prefix) {
                let path = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                if let normalized = normalizedToolPath(String(path)) { return normalized }
            }
        }
        return nil
    }

    private func normalizedToolPath(_ rawPath: String) -> String? {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if path.hasPrefix("file://"), let url = URL(string: path) {
            path = url.path
        }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path = String(path.dropFirst(2))
        }
        guard !path.isEmpty, path != "/dev/null", !path.contains("\n") else { return nil }
        guard path.contains("/") || path.contains(".") else { return nil }
        return path
    }

    private func visualFormattedJSONObject(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let pairs = visibleToolPairs(from: object)
        guard !pairs.isEmpty else { return "" }
        return pairs
            .map { "\($0.key):\n\($0.value)" }
            .joined(separator: "\n\n")
    }

    private func visibleToolPairs(from object: Any) -> [(key: String, value: String)] {
        if let dictionary = object as? [String: Any] {
            return visibleToolPairs(from: dictionary)
        }
        if let array = object as? [Any] {
            return array.enumerated().flatMap { index, value in
                visibleToolPairs(from: value).map { ("item \(index + 1) · \($0.key)", $0.value) }
            }
        }
        return []
    }

    private func visibleToolPairs(from dictionary: [String: Any]) -> [(key: String, value: String)] {
        let priorityKeys = [
            "toolName", "tool_name", "name", "tool",
            "command", "cmd", "cwd", "path", "file", "filePath", "file_path",
            "input", "args", "arguments", "params",
            "stdout", "stderr", "output", "result", "error", "message", "text", "is_error", "diff", "patch"
        ]
        var pairs: [(key: String, value: String)] = []
        for key in priorityKeys {
            guard let value = dictionary[key],
                  let text = readableToolValue(value),
                  !text.isEmpty else { continue }
            pairs.append((displayToolKey(key), text))
        }
        if !pairs.isEmpty { return pairs.removingDuplicateKeys() }

        let envelopeKeys = ["message", "content", "event", "delta", "item", "params", "data"]
        for key in envelopeKeys {
            guard let value = dictionary[key] else { continue }
            pairs.append(contentsOf: visibleToolPairs(from: value))
        }
        return pairs.removingDuplicateKeys()
    }

    private func readableToolValue(_ value: Any) -> String? {
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let string = value as? String {
            let filtered = string
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { !$0.isInternalToolNoiseLine }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return filtered.isEmpty ? nil : filtered
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return nil }
        let filtered = string
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isInternalToolNoiseLine }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return filtered.isEmpty ? nil : filtered
    }

    private func displayToolKey(_ key: String) -> String {
        switch key {
        case "toolName", "tool_name": return "tool"
        case "filePath", "file_path": return "path"
        default: return key
        }
    }

    private static func displayFileName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    private static func firstUsefulLine(_ value: String) -> String? {
        value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.isInternalToolNoiseLine }
    }

    private static func normalizedAgentID(_ value: String) -> String? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "agent-", with: "")
        let id = trimmed.prefix { character in
            character.isLetter || character.isNumber || character == "_" || character == "-"
        }
        return id.isEmpty ? nil : String(id)
    }

    private static func agentID(from body: String) -> String? {
        let patterns = [
            #"agentId:\s*([A-Za-z0-9_-]+)"#,
            #"agent_id:\s*([A-Za-z0-9_-]+)"#,
            #"\"agentId\"\s*:\s*\"([^\"]+)\""#,
            #"\"agent_id\"\s*:\s*\"([^\"]+)\""#
        ]
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            guard let match = regex.firstMatch(in: body, range: range), match.numberOfRanges > 1 else { continue }
            guard let valueRange = Range(match.range(at: 1), in: body) else { continue }
            if let id = normalizedAgentID(String(body[valueRange])) {
                return id
            }
        }
        return nil
    }

    private static func previewSnippet(_ value: String, limit: Int = 72) -> String {
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)) + "…"
    }

    private static func previewContentLines(_ value: String, marker: String, tint: Color, limit: Int) -> [ToolCodePreview.Line] {
        value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .prefix(limit)
            .map { line in
                ToolCodePreview.Line(marker: marker, text: line.isEmpty ? " " : line, tint: tint)
            }
    }

    private static func previewLine(from rawLine: String) -> ToolCodePreview.Line {
        if rawLine.hasPrefix("+") {
            return ToolCodePreview.Line(marker: "+", text: String(rawLine.dropFirst()), tint: .green)
        }
        if rawLine.hasPrefix("-") {
            return ToolCodePreview.Line(marker: "-", text: String(rawLine.dropFirst()), tint: .red)
        }
        let text = rawLine.hasPrefix(" ") ? String(rawLine.dropFirst()) : rawLine
        return ToolCodePreview.Line(marker: " ", text: text.isEmpty ? " " : text, tint: .secondary)
    }

    private static func formattedByteCount(_ bytes: Int) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
        if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        }
        return "\(bytes) B"
    }
}

private extension ChatRunStatus {
    var statusTint: Color {
        switch self {
        case .idle, .completed: .secondary
        case .starting, .streaming: Color.accentColor
        case .waitingPermission, .waitingInput, .stopping: .orange
        case .failed, .unsupportedVersion: .red
        }
    }
}

private extension ChatPermissionMode {
    var systemImage: String {
        switch self {
        case .ask: "hand.raised"
        case .autoEdit: "pencil.and.scribble"
        case .fullAccess: "shield.lefthalf.filled.badge.checkmark"
        }
    }

    var tint: Color {
        switch self {
        case .ask: .secondary
        case .autoEdit: Color.accentColor
        case .fullAccess: .orange
        }
    }
}

private extension Array where Element == (key: String, value: String) {
    func removingDuplicateKeys() -> [(key: String, value: String)] {
        var seen = Set<String>()
        var result: [(key: String, value: String)] = []
        for item in self where !seen.contains(item.key) {
            seen.insert(item.key)
            result.append(item)
        }
        return result
    }
}

private extension String {
    var diffTint: Color {
        if hasPrefix("+") { return .green }
        if hasPrefix("-") { return .red }
        return .secondary
    }

    var isInternalToolNoiseLine: Bool {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if normalized == "done" || normalized == "null" { return true }
        let noisyPrefixes = [
            "\"id\"", "\"type\"", "\"role\"", "\"index\"", "\"model\"",
            "\"usage\"", "\"session_id\"", "\"request_id\"", "\"parent_id\"",
            "\"message_start\"", "\"message_stop\"", "\"stop_reason\"",
            "\"created_at\"", "\"timestamp\"", "\"uuid\""
        ]
        return noisyPrefixes.contains { normalized.hasPrefix($0) }
    }
}

private enum ChatPicker {
    case cli
    case permission
    case model
}
