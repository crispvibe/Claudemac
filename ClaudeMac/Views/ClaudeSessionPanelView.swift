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
            Text(message.text)
                .font(.system(size: 12))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

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
        return VStack(alignment: .leading, spacing: 7) {
            Button {
                toggleTranscriptMessage(message.id)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: message.kind.toolIcon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(message.kind.toolTint)
                        .frame(width: 14)
                    Text(message.toolDisplayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                toolDetailView(message)
                    .padding(.leading, 22)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func toolDetailView(_ message: ChatMessage) -> some View {
        if message.kind == .diff {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(message.diffLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(line.diffTint)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if !message.toolDetailText.isEmpty {
            Text(message.toolDetailText)
                .font(.system(size: 10, design: message.kind.isToolDetailMonospaced ? .monospaced : .default))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func interactiveRequestRow(_ message: ChatMessage) -> some View {
        ChatInteractiveRequestCard(message: message, chatState: chatState)
    }

    private func reasoningMessageRow(_ message: ChatMessage) -> some View {
        let isAutoExpanded = chatState.status.isRunning
        let isExpanded = isAutoExpanded || expandedTranscriptMessageIDs.contains(message.id)

        return VStack(alignment: .leading, spacing: 5) {
            Button {
                toggleTranscriptMessage(message.id)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 12)

                    Text(isAutoExpanded ? "正在思考" : "思考已完成")
                        .font(.system(size: 11, weight: .medium))

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
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(.leading, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(spacing: 8) {
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
        .padding(12)
        .background(Color.white)
    }

    private var queuedRequestsView: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(Array(chatState.queuedRequests.enumerated()), id: \.element.id) { index, request in
                    HStack(spacing: 8) {
                        Text("#\(index + 1)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("队列中")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                            Text(request.text.components(separatedBy: .newlines).first ?? request.text)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Button {
                            chatState.cancelQueuedRequest(request.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(Color.black.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .frame(maxHeight: 34 * 3 + 12)
    }

    private var composerCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ChatComposerTextView(text: $draftMessage, onSubmit: sendMessage)
                    .frame(minHeight: 42, maxHeight: 60)
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                    .padding(.bottom, 1)

                if draftMessage.isEmpty {
                    Text(editingMessageID == nil ? "要求后续变更" : "编辑上一条消息")
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
                if chatState.status.isRunning {
                    stopButton
                }
                sendButton
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
        .background(Color.orange)
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
        if let tab = appState.selectedTab {
            parts.append("Current file: \(tab.url.path)\nCursor: line \(appState.cursorLine), column \(appState.cursorColumn)")
        }
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
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
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
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
        textView.string = text
        textView.font = .systemFont(ofSize: 12)
        textView.drawsBackground = false
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
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }

    final class SubmitTextView: NSTextView {
        var onSubmit: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            if isReturn && !event.modifierFlags.contains(.shift) {
                onSubmit?()
                return
            }
            super.keyDown(with: event)
        }
    }
}

private extension ChatMessageKind {
    var toolIcon: String {
        switch self {
        case .toolCall, .toolResult:
            "gearshape"
        case .command:
            "play.circle"
        case .commandOutput:
            "doc.text"
        case .diff:
            "pencil"
        default:
            "circle"
        }
    }

    var toolTint: Color {
        switch self {
        case .toolCall, .toolResult:
            .blue
        case .command, .commandOutput:
            .orange
        case .diff:
            .green
        default:
            .secondary
        }
    }

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
        switch kind {
        case .toolCall:
            return namedToolTitle(prefix: isStreaming ? "正在调用工具" : "调用工具")
        case .toolResult:
            return namedToolTitle(prefix: "工具结果")
        case .command:
            return "执行命令"
        case .commandOutput:
            return "命令输出"
        case .diff:
            return "文件变更"
        default:
            return "工具调用"
        }
    }

    var toolDetailText: String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "" }
        if let formatted = compactFormattedJSONObject(body) {
            return formatted
        }
        return body
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

    private func namedToolTitle(prefix: String) -> String {
        let name = toolName
        return name.isEmpty ? prefix : "\(prefix)：\(name)"
    }

    private var toolName: String {
        let candidates = [title, subtitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return candidates.first { value in
            !value.contains("{") && !value.contains("}") && value != "tool_use" && !value.contains("json_delta")
        } ?? ""
    }

    private func compactFormattedJSONObject(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let formattedData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let formatted = String(data: formattedData, encoding: .utf8) else { return nil }
        return formatted
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

private extension String {
    var diffTint: Color {
        if hasPrefix("+") { return .green }
        if hasPrefix("-") { return .red }
        if hasPrefix("@@") { return .blue }
        return .secondary
    }
}

private enum ChatPicker {
    case cli
    case permission
    case model
}
