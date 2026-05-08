import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatPanelView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var chatState = ChatPanelState()
    @State private var draftMessage = ""
    @State private var editingMessageID: UUID?
    @State private var selectedModelID = ChatModelCatalog.defaultClaudeModelID
    @State private var permissionMode = ChatPermissionMode.ask
    @State private var activePicker: ChatPicker?
    @State private var showCopiedToast = false
    @State private var attachedPaths: [String] = []

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
        .background(AppTheme.editorSurface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .onAppear {
            normalizeSelectedModel()
            chatState.loadFromAppState(appState, modelID: selectedModelID, permissionMode: permissionMode)
        }
        .onChange(of: appState.chatConversationSerial) { _, _ in
            normalizeSelectedModel()
            chatState.loadFromAppState(appState, modelID: selectedModelID, permissionMode: permissionMode)
        }
        .onChange(of: appState.selectedCLI) { _, _ in
            normalizeSelectedModel()
            activePicker = nil
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

            Text(chatState.statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(chatState.status.statusTint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 37, alignment: .leading)
        .padding(.horizontal, 14)
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if appState.selectedProject == nil {
                    emptyProjectState
                } else if chatState.messages.isEmpty {
                    emptyChatState
                } else {
                    ForEach(chatState.messages) { message in
                        messageRow(message)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .scrollIndicators(.hidden)
        .background(Color.white.opacity(0.08))
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
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        switch message.kind {
        case .user:
            userMessageRow(message)
        case .assistant:
            assistantMessageRow(message)
        case .diff:
            fileEditRow(message)
        case .permissionRequest:
            permissionRequestRow(message)
        case .error, .reasoning, .toolCall, .toolResult, .command, .commandOutput, .system, .result, .rawOutput:
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

            HStack(spacing: 8) {
                Spacer().frame(width: 52)

                Button("拒绝") {
                    if let requestID = message.requestID {
                        chatState.respondToPermission(requestID: requestID, allowed: false)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

                Button("允许") {
                    if let requestID = message.requestID {
                        chatState.respondToPermission(requestID: requestID, allowed: true)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
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
        .background(Color.white.opacity(0.16))
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

            HStack(spacing: 7) {
                iconOnlyButton(systemImage: "plus", tint: .secondary, action: openFilesForComposer)

                selectorButton(title: appState.selectedCLI.displayName, systemImage: "terminal", tint: .primary, picker: .cli)
                selectorButton(title: permissionMode.shortTitle, systemImage: permissionMode.systemImage, tint: permissionMode.tint, picker: .permission)

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

                selectorButton(title: selectedModelTitle, systemImage: "chevron.down", tint: .primary, picker: .model)
                contextIcon
                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
        }
        .background(AppTheme.editorSurface.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .onDrop(of: [UTType.fileURL.identifier, UTType.plainText.identifier], isTargeted: nil, perform: handleDroppedItems)
    }

    private var contextIcon: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.08), lineWidth: 2)
            Circle()
                .trim(from: 0, to: 0.79)
                .stroke(Color.secondary.opacity(0.78), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
        .frame(width: 20, height: 20)
        .help(attachedPaths.isEmpty ? "上下文 79% · 203k / 258k 标记" : "上下文 79% · 已加入 \(attachedPaths.count) 个路径")
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
                        normalizeSelectedModel()
                        activePicker = nil
                    }
                }
            case .permission:
                ForEach(ChatPermissionMode.allCases) { mode in
                    pickerOption(title: mode.title, isSelected: permissionMode == mode) {
                        permissionMode = mode
                        activePicker = nil
                    }
                }
            case .model:
                ForEach(ChatModelCatalog.options(for: appState.selectedCLI)) { model in
                    pickerOption(title: model.title, isSelected: selectedModelID == model.id) {
                        selectedModelID = model.id
                        activePicker = nil
                    }
                }
            }
        }
        .padding(6)
        .frame(maxWidth: 220, alignment: .leading)
        .background(AppTheme.editorSurface.opacity(0.95))
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

    private func selectorButton(title: String, systemImage: String, tint: Color, picker: ChatPicker) -> some View {
        Button {
            activePicker = activePicker == picker ? nil : picker
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(tint)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 4)
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
        ChatModelCatalog.title(for: selectedModelID, cli: appState.selectedCLI)
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
            permissionMode: permissionMode,
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

    private func normalizeSelectedModel() {
        let options = ChatModelCatalog.options(for: appState.selectedCLI)
        if !options.contains(where: { $0.id == selectedModelID }) {
            selectedModelID = ChatModelCatalog.defaultModelID(for: appState.selectedCLI)
        }
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
        case .command, .commandOutput, .rawOutput, .system, .result: true
        case .user, .assistant, .reasoning, .toolCall, .toolResult, .permissionRequest, .diff, .error: false
        }
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
