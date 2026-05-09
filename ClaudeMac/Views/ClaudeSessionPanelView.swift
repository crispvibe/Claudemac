import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatPanelView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var modelService: ChatModelService
    @StateObject private var chatState = ChatPanelState()
    @State private var draftMessage = ""
    @State private var editingMessageID: UUID?
    @State private var selectedModelID = ChatModelCatalog.defaultClaudeModelID
    @State private var permissionMode = ChatPermissionMode.ask
    @State private var reasoningEffort = ChatReasoningEffort.high
    @State private var activePicker: ChatPicker?
    @State private var customModelInput = ""
    @State private var showCopiedToast = false
    @State private var attachedPaths: [String] = []
    @State private var showResumePopover = false
    @State private var resumeInput = ""
    @State private var expandedTranscriptMessageIDs: Set<UUID> = []
    @State private var composerHasMarkedText = false
    private let transcriptBottomID = "chat-transcript-bottom"

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
            chatState.loadFromAppState(appState, modelID: selectedModelID, permissionMode: permissionMode, reasoningEffort: reasoningEffort)
        }
        .onChange(of: appState.chatConversationSerial) { _, _ in
            applyPersistedChatSelection()
            normalizeReasoningEffort()
            syncSelectedContextWindow()
            chatState.loadFromAppState(appState, modelID: selectedModelID, permissionMode: permissionMode, reasoningEffort: reasoningEffort)
        }
        .onChange(of: appState.selectedCLI) { _, _ in
            selectedModelID = persistedModelID(for: appState.selectedCLI)
            normalizeSelectedModel()
            resetReasoningEffortToConfiguredDefault()
            syncSelectedContextWindow()
            persistChatSelection()
            activePicker = nil
        }
        .onChange(of: selectedModelID) { _, _ in
            syncSelectedContextWindow()
            persistChatSelection()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(projectName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Button(action: copyProjectPath) {
                Text(projectPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                showResumePopover = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("恢复历史会话")
            .popover(isPresented: $showResumePopover, arrowEdge: .bottom) {
                VStack(spacing: 8) {
                    Text("恢复会话")
                        .font(.system(size: 11, weight: .medium))
                    TextField("Session ID", text: $resumeInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 200)
                    Button("恢复") {
                        let trimmed = resumeInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        appState.selectedMode = .resume
                        appState.resumeSessionId = trimmed
                        appState.chatConversationSerial = UUID()
                        showResumePopover = false
                        resumeInput = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(resumeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
            }

            Text(chatState.statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(chatState.status.statusTint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 37, alignment: .leading)
        .padding(.horizontal, 14)
    }

    private var transcript: some View {
        let items = transcriptItems
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
                .textSelection(.enabled)
            }
            .scrollIndicators(.hidden)
            .background(Color.white)
            .onAppear { scrollTranscriptToBottom(proxy) }
            .onChange(of: chatState.transcriptRevision) { _, _ in scrollTranscriptToBottom(proxy) }
            .onChange(of: chatState.isAwaitingFirstModelOutput) { _, _ in scrollTranscriptToBottom(proxy) }
            .onChange(of: chatState.queuedRequests.count) { _, _ in scrollTranscriptToBottom(proxy) }
        }
    }

    private var transcriptItems: [ChatTranscriptItem] {
        var items: [ChatTranscriptItem] = []
        var seenErrorMessages = Set<String>()
        for message in chatState.messages {
            guard shouldShowInTranscript(message) else { continue }
            if message.kind == .error {
                let key = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard seenErrorMessages.insert(key).inserted else { continue }
            }
            items.append(.message(message))
        }
        if chatState.isAwaitingFirstModelOutput && appState.selectedProject != nil {
            items.append(.loading)
        }
        return items
    }

    private func scrollTranscriptToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) {
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
            AssistantMessageContent(text: message.text, isStreaming: message.isStreaming)

            messageActionBar(message, alignment: .leading)
        }
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
        let filePath = message.toolFilePath
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    toggleTranscriptMessage(message.id)
                } label: {
                    HStack(spacing: 6) {
                        Text(message.toolDisplayTitle)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.secondary.opacity(0.45))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let filePath {
                    Button {
                        appState.openFile(path: filePath)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 9, weight: .medium))
                            Text(URL(fileURLWithPath: filePath).lastPathComponent)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.035))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(filePath)
                }

                Spacer(minLength: 0)
            }

            if isExpanded {
                toolDetailCard(message)
                    .padding(.leading, 12)
            }
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func toolDetailCard(_ message: ChatMessage) -> some View {
        let detailText = message.toolDetailText
        if message.kind == .diff || !detailText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(message.kind == .diff ? "diff" : "details")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    if !detailText.isEmpty {
                        iconAction("doc.on.doc", help: "复制详情") {
                            copyText(detailText)
                        }
                    }
                }

                toolDetailView(message)
            }
            .padding(9)
            .background(Color.black.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
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
        } else if !message.toolDetailText.isEmpty {
            ScrollView(.horizontal, showsIndicators: true) {
                Text(message.toolDetailPreviewText)
                    .font(.system(size: 10, design: message.kind.isToolDetailMonospaced ? .monospaced : .default))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
                    .foregroundStyle(.orange)
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
        .background(Color.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

            ZStack(alignment: .bottomLeading) {
                composerCard

                if let activePicker {
                    pickerOverlay(activePicker)
                        .padding(.bottom, 92)
                        .zIndex(10)
                }
            }
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
                ChatComposerTextView(text: $draftMessage, hasMarkedText: $composerHasMarkedText, onSubmit: sendMessage)
                    .frame(minHeight: 42, maxHeight: 60)
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
                        draftMessage = ""
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

    @ViewBuilder
    private var actionButton: some View {
        if chatState.status.isRunning && draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stopButton
        } else {
            sendButton
        }
    }

    private var stopButton: some View {
        Button {
            chatState.interrupt()
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Color.accentColor)
        .clipShape(Circle())
        .contentShape(Circle())
        .help("停止当前任务")
    }

    private var sendButton: some View {
        Button(action: sendMessage) {
            Image(systemName: "arrow.up")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(canSend ? Color.accentColor : Color.secondary.opacity(0.58))
        .clipShape(Circle())
        .contentShape(Circle())
        .disabled(!canSend)
        .help(chatState.status.isRunning ? "加入队列" : "发送")
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

    private var canSend: Bool {
        appState.selectedProject != nil && !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var capabilityText: String {
        let cli = appState.selectedCLI.visibleValue
        guard let capability = chatState.capabilities[cli] else { return "正在检测 \(cli.displayName)…" }
        if let error = capability.errorMessage { return error }
        return "\(cli.displayName) · \(capability.version ?? "未知版本") · \(capability.executablePath ?? cli.executable)"
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
            draftMessage = ""
            attachedPaths.removeAll()
        }
    }

    private var composedPrompt: String {
        var parts = [draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)]
        let paths = attachedPaths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !paths.isEmpty {
            parts.append("Attached paths:\n" + paths.joined(separator: "\n"))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
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
    }

    private func undoMessage(_ message: ChatMessage) {
        guard !chatState.status.isRunning else { return }
        chatState.removeMessageThread(message.id)
        if editingMessageID == message.id {
            editingMessageID = nil
            draftMessage = ""
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
    case loading

    var id: String {
        switch self {
        case .message(let message):
            "message-\(message.id.uuidString)"
        case .loading:
            "loading"
        }
    }
}

private struct AssistantMessageContent: View {
    let text: String
    let isStreaming: Bool

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
        AssistantMessageBlock.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldUseLightweightRender {
                Text(previewText)
                    .font(.system(size: 12))
                    .lineSpacing(3)
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
            Text(inlineMarkdown(value))
                .font(.system(size: 12))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    .foregroundStyle(Color.accentColor)
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
        .background(Color.accentColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionRow(_ option: ChatInteractiveOption, selected: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.45))
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

private struct ChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var hasMarkedText: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, hasMarkedText: $hasMarkedText, onSubmit: onSubmit)
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
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmitTextView else { return }
        textView.onSubmit = onSubmit
        textView.onMarkedTextChanged = { context.coordinator.hasMarkedText = $0 }
        textView.isEditable = true
        textView.isSelectable = true
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var hasMarkedText: Bool
        let onSubmit: () -> Void

        init(text: Binding<String>, hasMarkedText: Binding<Bool>, onSubmit: @escaping () -> Void) {
            _text = text
            _hasMarkedText = hasMarkedText
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            hasMarkedText = textView.hasMarkedText()
        }
    }

    final class SubmitTextView: NSTextView {
        var onSubmit: (() -> Void)?
        var onMarkedTextChanged: ((Bool) -> Void)?

        override func keyDown(with event: NSEvent) {
            let isReturn = event.keyCode == 36 || event.keyCode == 76
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
            super.keyDown(with: event)
        }

        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            onMarkedTextChanged?(hasMarkedText())
        }

        override func unmarkText() {
            super.unmarkText()
            onMarkedTextChanged?(hasMarkedText())
        }
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
    var toolDisplayTitle: String {
        if !toolName.isEmpty { return toolName }
        switch kind {
        case .toolCall, .toolResult:
            return "tool"
        case .command:
            return "command"
        case .commandOutput:
            return "command output"
        case .diff:
            return "diff"
        default:
            return "tool"
        }
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
        let candidates = [title, subtitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return candidates.first { value in
            !value.contains("{") && !value.contains("}") && value != "tool_use" && !value.contains("json_delta")
        } ?? ""
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
