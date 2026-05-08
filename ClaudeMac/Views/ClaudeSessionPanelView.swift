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
        return ScrollView {
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .scrollIndicators(.hidden)
        .background(Color.white)
    }

    private var transcriptItems: [ChatTranscriptItem] {
        var items: [ChatTranscriptItem] = []
        var activityMessages: [ChatMessage] = []

        func flushActivity() {
            guard !activityMessages.isEmpty else { return }
            let group = ChatActivityGroup(messages: activityMessages)
            if group.isMeaningful {
                items.append(.activity(group))
            }
            activityMessages.removeAll()
        }

        for message in chatState.messages where shouldShowInTranscript(message) {
            if message.kind.isGroupedActivityEvent {
                activityMessages.append(message)
            } else {
                flushActivity()
                items.append(.message(message))
            }
        }
        flushActivity()
        return items
    }

    private func shouldShowInTranscript(_ message: ChatMessage) -> Bool {
        guard message.kind.isVisibleInTranscript else { return false }
        guard message.kind.isGroupedActivityEvent else { return true }
        return message.isStreaming
            || !message.title.isEmpty
            || !message.subtitle.isEmpty
            || !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyProjectState: some View {
        Text("先选择一个项目。")
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
            if appState.settings.showCommandPreview {
                Text(appState.commandPreview)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func transcriptItemRow(_ item: ChatTranscriptItem) -> some View {
        switch item {
        case .message(let message):
            messageRow(message)
        case .activity(let group):
            activityGroupRow(group)
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
        case .diff:
            fileEditRow(message)
        case .permissionRequest:
            permissionRequestRow(message)
        case .error, .toolCall, .toolResult, .command, .commandOutput, .system, .result, .rawOutput:
            streamActivityRow(message)
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
            processedHeader(message)

            Text(message.text)
                .font(.system(size: 12))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            messageActionBar(message, alignment: .leading)
        }
    }

    private func streamActivityRow(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(message.kind.streamPrefix)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(message.kind.streamTint)
                    .frame(width: 54, alignment: .leading)

                Text(message.title.isEmpty ? message.kind.defaultTitle : message.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(message.kind == .error ? .red : .primary)
                    .lineLimit(1)

                if !message.subtitle.isEmpty {
                    Text(message.subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(message.status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(message.kind.streamTint)
            }

            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 10, design: message.kind.isMonospaced ? .monospaced : .default))
                    .foregroundStyle(message.kind == .error ? .red : .secondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(.leading, 60)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityGroupRow(_ group: ChatActivityGroup) -> some View {
        let isAutoExpanded = group.isStreaming
        let isExpanded = isAutoExpanded || expandedTranscriptMessageIDs.contains(group.id)

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                toggleTranscriptMessage(group.id)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 13)

                    Text(group.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    if let summary = group.summaryText {
                        Text(summary)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(group.detailMessages.prefix(8)) { message in
                        activityDetailRow(message)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityDetailRow(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: message.kind.activityIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)

                Text(message.activityTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !message.activityBody.isEmpty {
                Text(message.activityBody)
                    .font(.system(size: 10, design: message.kind.isMonospaced ? .monospaced : .default))
                    .foregroundStyle(.tertiary)
                    .lineSpacing(2)
                    .lineLimit(message.kind == .reasoning ? nil : 3)
                    .textSelection(.enabled)
                    .padding(.leading, 19)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

                    Text(isAutoExpanded ? "进行中" : (isExpanded ? "展开" : "已折叠"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
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
        guard !chatState.status.isRunning else { return }
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("allow")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.orange)
                    .frame(width: 54, alignment: .leading)

                Text(message.title)
                    .font(.system(size: 11, weight: .medium))

                Spacer(minLength: 0)

                Text(message.status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.orange)
            }

            Text(message.text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.leading, 60)
                .textSelection(.enabled)

            if message.status == "waiting" {
                HStack(spacing: 8) {
                    Spacer().frame(width: 52)

                    Button("拒绝") {
                        if let requestID = message.requestID {
                            chatState.respondToPermission(requestID: requestID, decision: .deny)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                    Button("允许") {
                        if let requestID = message.requestID {
                            chatState.respondToPermission(requestID: requestID, decision: .allow)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                    Button("本会话允许") {
                        if let requestID = message.requestID {
                            chatState.respondToPermission(requestID: requestID, decision: .allowForSession)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                }
            }
        }
        .padding(.vertical, 2)
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

            if message.kind == .assistant {
                iconAction("hand.thumbsup", help: "赞") {}
                iconAction("hand.thumbsdown", help: "踩") {}
            }

            if alignment == .leading {
                Spacer(minLength: 0)
            }
        }
    }

    private var composer: some View {
        ZStack(alignment: .bottomLeading) {
            composerCard

            if let activePicker {
                pickerOverlay(activePicker)
                    .padding(.bottom, 92)
                    .zIndex(10)
            }
        }
        .padding(12)
        .background(Color.white)
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

    private var sendButton: some View {
        Button(action: sendMessage) {
            Image(systemName: chatState.status.isRunning ? "stop.fill" : "arrow.up")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(canSend ? Color.accentColor : Color.secondary.opacity(0.58))
        .clipShape(Circle())
        .contentShape(Circle())
        .disabled(!canSend)
    }

    private var projectName: String {
        appState.selectedProject?.name ?? "未选择项目"
    }

    private var projectPath: String {
        appState.selectedProject?.path ?? "请选择项目目录"
    }

    private var selectedModelTitle: String {
        modelService.title(for: selectedModelID, cli: appState.selectedCLI)
    }

    private var canSend: Bool {
        if chatState.status.isRunning { return true }
        return appState.selectedProject != nil && !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        if chatState.status.isRunning {
            chatState.interrupt()
            return
        }
        if let editingMessageID {
            chatState.removeMessageThread(editingMessageID)
            self.editingMessageID = nil
        }
        chatState.send(
            text: draftMessage,
            project: appState.selectedProject,
            cli: appState.selectedCLI,
            modelID: selectedModelID,
            contextModelID: selectedContextModelID,
            permissionMode: permissionMode,
            reasoningEffort: reasoningEffort,
            sessionMode: appState.selectedMode,
            resumeSessionID: appState.resumeSessionId
        )
        draftMessage = ""
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
            if draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draftMessage = trimmed
            } else {
                draftMessage += "\n\(trimmed)"
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
    case activity(ChatActivityGroup)

    var id: String {
        switch self {
        case .message(let message):
            "message-\(message.id.uuidString)"
        case .activity(let group):
            "activity-\(group.id.uuidString)"
        }
    }
}

private struct ChatActivityGroup: Identifiable {
    let id: UUID
    let messages: [ChatMessage]

    init(messages: [ChatMessage]) {
        self.messages = messages
        id = messages.first?.id ?? UUID()
    }

    var isStreaming: Bool {
        messages.contains { $0.isStreaming }
    }

    var isMeaningful: Bool {
        messages.contains { message in
            switch message.kind {
            case .commandOutput, .rawOutput, .result:
                false
            default:
                true
            }
        }
    }

    var title: String {
        "\(isStreaming ? "处理中" : "已处理") \(durationText)"
    }

    var summaryText: String? {
        var parts: [String] = []
        let reasoningCount = messages.filter { $0.kind == .reasoning }.count
        let toolCount = messages.filter { $0.kind == .toolCall }.count
        let commandCount = messages.filter { $0.kind == .command }.count

        if reasoningCount > 0 {
            parts.append(isStreaming ? "正在思考" : "已思考")
        }
        if toolCount > 0 {
            parts.append("已调用 \(toolCount) 个工具")
        }
        if commandCount > 0 {
            parts.append("已运行 \(commandCount) 条命令")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "，")
    }

    var detailMessages: [ChatMessage] {
        messages.filter { message in
            switch message.kind {
            case .commandOutput, .rawOutput, .result:
                false
            default:
                true
            }
        }
    }

    private var durationText: String {
        guard let start = messages.first?.createdAt, let end = messages.last?.createdAt else {
            return "0s"
        }
        let seconds = max(1, Int(end.timeIntervalSince(start).rounded()))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let rest = seconds % 60
        return rest == 0 ? "\(minutes)m" : "\(minutes)m \(rest)s"
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
    var streamPrefix: String {
        switch self {
        case .reasoning: "think"
        case .toolCall: "tool"
        case .toolResult: "out"
        case .command: "cmd"
        case .commandOutput: "log"
        case .system: "sys"
        case .result: "done"
        case .error: "err"
        case .rawOutput: "raw"
        case .diff: "edit"
        case .permissionRequest: "allow"
        case .user, .assistant: ""
        }
    }

    var defaultTitle: String {
        switch self {
        case .reasoning: "思考"
        case .toolCall: "工具调用"
        case .toolResult: "工具结果"
        case .command: "命令"
        case .commandOutput: "命令输出"
        case .system: "系统"
        case .result: "结果"
        case .error: "错误"
        case .rawOutput: "原始输出"
        case .diff: "文件修改"
        case .permissionRequest: "权限请求"
        case .user: "用户"
        case .assistant: "助手"
        }
    }

    var streamTint: Color {
        switch self {
        case .reasoning: .purple
        case .toolCall, .toolResult: .blue
        case .command, .commandOutput: .orange
        case .system, .rawOutput: .secondary
        case .result: .green
        case .error: .red
        case .diff: .green
        case .permissionRequest: .orange
        case .user, .assistant: .secondary
        }
    }

    var isMonospaced: Bool {
        switch self {
        case .toolCall, .toolResult, .command, .commandOutput, .rawOutput, .system, .result: true
        case .user, .assistant, .reasoning, .permissionRequest, .diff, .error: false
        }
    }

    var isGroupedActivityEvent: Bool {
        switch self {
        case .reasoning, .toolCall, .toolResult, .command, .commandOutput, .result, .rawOutput:
            true
        case .user, .assistant, .permissionRequest, .diff, .error, .system:
            false
        }
    }

    var activityIcon: String {
        switch self {
        case .reasoning:
            "lightbulb"
        case .toolCall, .toolResult:
            "gearshape"
        case .command, .commandOutput:
            "terminal"
        case .result:
            "checkmark.circle"
        case .rawOutput:
            "doc.text"
        case .diff:
            "pencil"
        case .permissionRequest:
            "hand.raised"
        case .error:
            "exclamationmark.triangle"
        case .user, .assistant, .system:
            "circle"
        }
    }

    var isVisibleInTranscript: Bool {
        switch self {
        case .system:
            false
        case .user, .assistant, .reasoning, .toolCall, .toolResult, .command, .commandOutput, .permissionRequest, .diff, .error, .result, .rawOutput:
            true
        }
    }
}

private extension ChatMessage {
    var activityTitle: String {
        switch kind {
        case .reasoning:
            isStreaming ? "正在思考" : "思考"
        case .toolCall:
            compactActivityTitle(prefix: "已调用工具")
        case .toolResult:
            compactActivityTitle(prefix: "工具已完成")
        case .command:
            compactActivityTitle(prefix: "已运行命令")
        case .commandOutput:
            compactActivityTitle(prefix: "命令输出")
        case .result:
            compactActivityTitle(prefix: "结果")
        case .rawOutput:
            compactActivityTitle(prefix: "原始事件")
        default:
            title.isEmpty ? kind.defaultTitle : title
        }
    }

    var activityBody: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func compactActivityTitle(prefix: String) -> String {
        let titleText = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitleText = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = titleText.isEmpty ? subtitleText : titleText
        return detail.isEmpty ? prefix : "\(prefix) \(detail)"
    }
}

private extension ChatRunStatus {
    var statusTint: Color {
        switch self {
        case .idle, .completed: .secondary
        case .starting, .streaming: Color.accentColor
        case .waitingPermission, .stopping: .orange
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
