import SwiftUI

struct SettingsPageView: View {
    private enum SettingsCategory: String, CaseIterable, Identifiable {
        case general
        case claude
        case codex
        case update
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "通用"
            case .claude: "Claude Code"
            case .codex: "Codex"
            case .update: "版本"
            case .about: "关于"
            }
        }

        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .claude: "terminal"
            case .codex: "cpu"
            case .update: "arrow.triangle.2.circlepath"
            case .about: "info.circle"
            }
        }
    }

    private enum CodexAuthMode: String, CaseIterable, Identifiable, Hashable {
        case account
        case apiKey

        var id: String { rawValue }

        var title: String {
            switch self {
            case .account: "账号登录"
            case .apiKey: "API Key / 中转站"
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var modelService: ChatModelService
    private let showsBackButton: Bool

    init(showsBackButton: Bool = true) {
        self.showsBackButton = showsBackButton
    }

    @State private var selectedCategory: SettingsCategory = .general
    @State private var defaultCLI: CLIType = .claude
    @State private var defaultTerminal: TerminalType = .terminal
    @State private var showCommandPreview = true
    @State private var enableClaudeHistoryScan = true
    @State private var ignoredFoldersText = ""

    // 中转站配置（直接读写 ~/.claude/settings.json）
    @State private var anthropicBaseURL = ""
    @State private var anthropicAuthToken = ""
    @State private var anthropicModel = ""
    @State private var anthropicHaikuModel = ""
    @State private var anthropicSonnetModel = ""
    @State private var anthropicOpusModel = ""
    @State private var httpProxy = ""
    @State private var httpsProxy = ""
    @State private var relaySaveStatus = ""
    @State private var claudeModelList: [String] = []
    @State private var isFetchingClaudeModels = false
    @State private var configProfiles: ConfigProfileCollection = .empty
    @State private var selectedClaudeProfileID: UUID?
    @State private var newClaudeProfileName = ""

    // Codex 配置（读写 ~/.codex/config.toml + auth.json）
    @State private var codexModel = ""
    @State private var codexBaseURL = ""
    @State private var codexApiKey = ""
    @State private var codexWireApi = "responses"
    @State private var codexAuthMode: CodexAuthMode = .apiKey
    @State private var codexAccountStatus = ""
    @State private var codexSaveStatus = ""
    @State private var codexModelList: [String] = []
    @State private var isFetchingCodexModels = false
    @State private var selectedCodexProfileID: UUID?
    @State private var newCodexProfileName = ""

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    private static let realHomeDir: URL = {
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    private static let claudeSettingsURL: URL = {
        realHomeDir.appendingPathComponent(".claude/settings.json")
    }()

    private static let codexConfigURL: URL = {
        realHomeDir.appendingPathComponent(".codex/config.toml")
    }()

    private static let codexAuthURL: URL = {
        realHomeDir.appendingPathComponent(".codex/auth.json")
    }()

    private static let ccSwitchCodexOAuthURL: URL = {
        realHomeDir.appendingPathComponent(".cc-switch/codex_oauth_auth.json")
    }()

    private var codexAvailableModels: [String] {
        var models = ChatModelCatalog.options(for: .codex).map(\.id)
        models.append(contentsOf: codexModelList)
        if !codexModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            models.insert(codexModel, at: 0)
        }
        return uniqueStrings(models)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.18)
            HStack(alignment: .top, spacing: 18) {
                categoryTabs
                    .frame(width: 178)
                ScrollView {
                    selectedSettingsContent
                        .padding(.trailing, 28)
                        .padding(.vertical, 24)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .onAppear {
            loadSettings()
            loadClaudeSettings()
            loadCodexSettings()
            loadConfigProfiles()
        }
    }

    @ViewBuilder
    private var selectedSettingsContent: some View {
        switch selectedCategory {
        case .general:
            generalSection
        case .claude:
            relaySection
        case .codex:
            codexSection
        case .update:
            updateSection
        case .about:
            aboutSection
        }
    }

    private var categoryTabs: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(SettingsCategory.allCases) { category in
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        selectedCategory = category
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: category.systemImage)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 16)
                            .foregroundStyle(selectedCategory == category ? Color.accentColor : .secondary)
                        Text(category.title)
                            .font(.system(size: 13, weight: selectedCategory == category ? .semibold : .medium))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 38)
                    .foregroundStyle(selectedCategory == category ? .primary : .secondary)
                    .background(selectedCategory == category ? AppTheme.selectedSurface : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.weakHairline, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if showsBackButton {
                Button(action: { appState.showSettings = false }) {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("返回")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                Color.clear.frame(width: 76, height: 34)
            }

            Spacer()

            Text("设置")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            Color.clear.frame(width: 76, height: 34)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - General

    private var generalSection: some View {
        settingsCard(title: "通用") {
            settingsGrid {
                optionSelector(
                    title: "默认 CLI",
                    selection: $defaultCLI,
                    options: CLIType.visibleCases.map { ($0, $0.displayName) }
                )

                optionSelector(
                    title: "默认终端",
                    selection: $defaultTerminal,
                    options: TerminalType.allCases.map { ($0, $0.displayName) }
                )

                settingsToggle(title: "显示命令预览", isOn: $showCommandPreview)
                settingsToggle(title: "扫描 Claude / Codex 历史会话", isOn: $enableClaudeHistoryScan)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("忽略目录")
                    .font(.system(size: 13, weight: .semibold))
                TextEditor(text: $ignoredFoldersText)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 132)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
                Text("每行一个目录名")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("恢复默认") {
                    ignoredFoldersText = FileTreeScanner.defaultIgnoredNames.sorted().joined(separator: "\n")
                }
                .buttonStyle(SettingsSecondaryButtonStyle())
                Spacer()
                Button("保存") { saveAppSettings() }
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Relay / Proxy

    private var relaySection: some View {
        settingsCard(title: "中转站（Claude Code）") {
            claudeProfileSelector

            settingsGrid {
                envField(label: "ANTHROPIC_BASE_URL", placeholder: "https://api.anthropic.com", text: $anthropicBaseURL)
                envField(label: "ANTHROPIC_AUTH_TOKEN", placeholder: "sk-...", text: $anthropicAuthToken, secure: true)
            }

            Divider().opacity(0.3)

            Group {
                HStack {
                    Text("模型配置")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(action: fetchClaudeModels) {
                        HStack(spacing: 4) {
                            if isFetchingClaudeModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11))
                            }
                            Text("拉取模型")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(SettingsSecondaryButtonStyle(compact: true))
                    .disabled(isFetchingClaudeModels || anthropicBaseURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 4)

                if !claudeModelList.isEmpty {
                    settingsGrid {
                        modelPicker(label: "ANTHROPIC_MODEL", selection: $anthropicModel, models: claudeModelList)
                        modelPicker(label: "ANTHROPIC_DEFAULT_HAIKU_MODEL", selection: $anthropicHaikuModel, models: claudeModelList)
                        modelPicker(label: "ANTHROPIC_DEFAULT_SONNET_MODEL", selection: $anthropicSonnetModel, models: claudeModelList)
                        modelPicker(label: "ANTHROPIC_DEFAULT_OPUS_MODEL", selection: $anthropicOpusModel, models: claudeModelList)
                    }
                } else {
                    settingsGrid {
                        envField(label: "ANTHROPIC_MODEL", placeholder: "claude-sonnet-4-6", text: $anthropicModel)
                        envField(label: "ANTHROPIC_DEFAULT_HAIKU_MODEL", placeholder: "claude-haiku-4-5-20251001", text: $anthropicHaikuModel)
                        envField(label: "ANTHROPIC_DEFAULT_SONNET_MODEL", placeholder: "claude-sonnet-4-6", text: $anthropicSonnetModel)
                        envField(label: "ANTHROPIC_DEFAULT_OPUS_MODEL", placeholder: "claude-opus-4-7", text: $anthropicOpusModel)
                    }
                }
            }

            Divider().opacity(0.3)

            Group {
                Text("全局代理（Claude Code / Codex）")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 4)

                settingsGrid {
                    envField(label: "HTTP_PROXY", placeholder: "http://127.0.0.1:7890", text: $httpProxy)
                    envField(label: "HTTPS_PROXY", placeholder: "http://127.0.0.1:7890", text: $httpsProxy)
                }
            }

            HStack {
                if !relaySaveStatus.isEmpty {
                    Text(relaySaveStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(relaySaveStatus.contains("成功") ? .green : .red)
                }
                Spacer()
                Button("保存到 ~/.claude/settings.json") {
                    saveClaudeSettings()
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
            }

            Text("代理字段会从 ~/.claude/settings.json 注入到新启动的 Claude Code / Codex 子进程。留空的字段不会写入配置文件。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Update

    private var codexSection: some View {
        settingsCard(title: "Codex") {
            codexProfileSelector

            Group {
                settingsGrid {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("认证方式")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        inlineSegmentedPicker(
                            selection: $codexAuthMode,
                            options: CodexAuthMode.allCases.map { ($0, $0.title) }
                        )
                    }

                }

                HStack {
                    Text("模型")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if codexAuthMode == .apiKey {
                        Button(action: fetchCodexModels) {
                            HStack(spacing: 4) {
                                if isFetchingCodexModels {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11))
                                }
                                Text("拉取模型")
                                    .font(.system(size: 12))
                            }
                        }
                        .buttonStyle(SettingsSecondaryButtonStyle(compact: true))
                        .disabled(isFetchingCodexModels || codexBaseURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                settingsGrid {
                    if !codexAvailableModels.isEmpty {
                        modelPicker(label: "model", selection: $codexModel, models: codexAvailableModels)
                    } else {
                        envField(label: "model", placeholder: "gpt-5.5", text: $codexModel)
                    }

                    if codexAuthMode == .apiKey {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("wire_api")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            inlineSegmentedPicker(
                                selection: $codexWireApi,
                                options: [("responses", "responses"), ("chat", "chat")]
                            )
                        }
                    }
                }

                if codexAuthMode == .apiKey {
                    settingsGrid {
                        envField(label: "base_url", placeholder: "https://api.openai.com/v1", text: $codexBaseURL)
                        envField(label: "OPENAI_API_KEY", placeholder: "sk-...", text: $codexApiKey, secure: true)
                    }
                } else {
                    codexAccountLoginStatusView
                }
            }

            HStack {
                if !codexSaveStatus.isEmpty {
                    Text(codexSaveStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(codexSaveStatusColor)
                }
                Spacer()
                Button("保存到 ~/.codex/") {
                    saveCodexSettings()
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
            }

            Text(codexAuthMode == .apiKey
                 ? "修改 ~/.codex/config.toml 和 ~/.codex/auth.json。保存后新启动的 Codex 会话将使用新配置。"
                 : "账号登录模式只修改 ~/.codex/config.toml 的模型配置，认证复用 Codex CLI 的 OAuth 登录态。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var claudeProfileSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("配置列表")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("选中后会立即写入 ~/.claude/settings.json")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if configProfiles.claudeRelayProfiles.isEmpty {
                emptyProfileText("还没有中转站配置，可填写下方字段后添加。")
            } else {
                profileChips(
                    profiles: configProfiles.claudeRelayProfiles,
                    selectedID: selectedClaudeProfileID,
                    title: \.name,
                    select: selectClaudeProfile,
                    delete: deleteClaudeProfile
                )
            }

            addProfileRow(
                placeholder: "配置名称，例如 Anna Relay",
                text: $newClaudeProfileName,
                action: addClaudeProfile
            )
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
    }

    private var codexProfileSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("配置列表")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("选中后会立即写入 ~/.codex/")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if configProfiles.codexProfiles.isEmpty {
                emptyProfileText("还没有 Codex 配置，可填写下方字段后添加。")
            } else {
                profileChips(
                    profiles: configProfiles.codexProfiles,
                    selectedID: selectedCodexProfileID,
                    title: \.name,
                    select: selectCodexProfile,
                    delete: deleteCodexProfile
                )
            }

            addProfileRow(
                placeholder: "配置名称，例如 Codex OpenAI",
                text: $newCodexProfileName,
                action: addCodexProfile
            )
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
    }

    private var codexSaveStatusColor: Color {
        if codexSaveStatus.contains("成功") || codexSaveStatus.contains("已导入") { return .green }
        if codexSaveStatus.contains("请先") { return .orange }
        return .red
    }

    private var codexAccountLoginStatusView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: codexAccountStatus.contains("检测到") || codexAccountStatus.contains("已导入") ? "checkmark.circle" : "info.circle")
                    .foregroundStyle(codexAccountStatus.contains("检测到") || codexAccountStatus.contains("已导入") ? .green : .secondary)
                Text(codexAccountStatus.isEmpty ? "未检测到 Codex 账号登录态。请先在终端运行 codex login，或从 cc-switch 导入登录态。" : codexAccountStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("从 cc-switch 导入登录态") {
                    importCodexOAuthFromCCSwitch()
                }
                .buttonStyle(SettingsSecondaryButtonStyle())
                .disabled(!FileManager.default.fileExists(atPath: Self.ccSwitchCodexOAuthURL.path))

                Button("重新检测") {
                    loadCodexSettings()
                }
                .buttonStyle(SettingsSecondaryButtonStyle())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
    }

    private var updateSection: some View {
        settingsCard(title: "版本更新") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前版本：\(appVersion)（\(buildNumber)）")
                        .font(.system(size: 13))
                }
                Spacer()
                Button("检查更新") {
                    // TODO: Implement update check
                }
                .buttonStyle(SettingsSecondaryButtonStyle())
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        settingsCard(title: "关于") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Acode")
                    .font(.system(size: 15, weight: .semibold))
                Text("一个轻量级的 Claude Code / Codex 桌面客户端")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - UI Helpers

    @ViewBuilder
    private func envField(label: String, placeholder: String, text: Binding<String>, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(label)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .settingsTextFieldChrome()
        }
    }

    private func settingsGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .topLeading)
            ],
            alignment: .leading,
            spacing: 16
        ) {
            content()
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white)
            }
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
        }
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    private func settingsToggle(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isOn.wrappedValue ? Color.accentColor.opacity(0.82) : Color.black.opacity(0.08))
                        .frame(width: 46, height: 26)
                    Circle()
                        .fill(Color.white.opacity(0.96))
                        .frame(width: 20, height: 20)
                        .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
                        .padding(.horizontal, 3)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func optionSelector<Value: Hashable>(title: String, selection: Binding<Value>, options: [(Value, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            inlineSegmentedPicker(selection: selection, options: options)
        }
    }

    private func inlineSegmentedPicker<Value: Hashable>(selection: Binding<Value>, options: [(Value, String)]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = selection.wrappedValue == option.0
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        selection.wrappedValue = option.0
                    }
                } label: {
                    Text(option.1)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(isSelected ? AppTheme.selectedSurface : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
    }

    private func emptyProfileText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func profileChips<Profile: Identifiable>(
        profiles: [Profile],
        selectedID: UUID?,
        title: KeyPath<Profile, String>,
        select: @escaping (Profile) -> Void,
        delete: @escaping (Profile) -> Void
    ) -> some View where Profile.ID == UUID {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(profiles) { profile in
                    let isSelected = selectedID == profile.id
                    HStack(spacing: 6) {
                        Button {
                            select(profile)
                        } label: {
                            Text(profile[keyPath: title])
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .padding(.leading, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        Button {
                            delete(profile)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .frame(width: 18, height: 18)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 8)
                    }
                    .background(isSelected ? AppTheme.selectedSurface : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(isSelected ? AppTheme.hairline : AppTheme.weakHairline, lineWidth: 1))
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func addProfileRow(placeholder: String, text: Binding<String>, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: text)
                .settingsTextFieldChrome()
            Button("添加当前配置") { action() }
                .buttonStyle(SettingsSecondaryButtonStyle())
        }
    }

    // MARK: - App Settings

    private func loadSettings() {
        let s = appState.settings
        defaultCLI = s.defaultCLI.visibleValue
        defaultTerminal = s.defaultTerminal
        showCommandPreview = s.showCommandPreview
        enableClaudeHistoryScan = s.enableClaudeHistoryScan
        ignoredFoldersText = s.ignoredFolders.joined(separator: "\n")
    }

    private func saveAppSettings() {
        appState.saveSettings(
            defaultCLI: defaultCLI,
            defaultTerminal: defaultTerminal,
            showCommandPreview: showCommandPreview,
            enableClaudeHistoryScan: enableClaudeHistoryScan,
            ignoredFolders: ignoredFoldersText
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    // MARK: - Config Profiles

    private func loadConfigProfiles() {
        configProfiles = ProjectStore.loadConfigProfiles()
        selectedClaudeProfileID = configProfiles.activeClaudeRelayProfileID
        selectedCodexProfileID = configProfiles.activeCodexProfileID

        if let id = selectedClaudeProfileID,
           let profile = configProfiles.claudeRelayProfiles.first(where: { $0.id == id }) {
            applyClaudeProfile(profile)
        }
        if let id = selectedCodexProfileID,
           let profile = configProfiles.codexProfiles.first(where: { $0.id == id }) {
            applyCodexProfile(profile)
        }
    }

    private func persistConfigProfiles() throws {
        try ProjectStore.saveConfigProfiles(configProfiles)
    }

    private func addClaudeProfile() {
        let profile = currentClaudeProfile(named: nextProfileName(newClaudeProfileName, fallback: "Claude 中转站", count: configProfiles.claudeRelayProfiles.count))
        configProfiles.claudeRelayProfiles.insert(profile, at: 0)
        configProfiles.activeClaudeRelayProfileID = profile.id
        selectedClaudeProfileID = profile.id
        newClaudeProfileName = ""
        do {
            try persistConfigProfiles()
            try writeClaudeSettings(updateSelectedProfile: false)
            relaySaveStatus = "已添加并切换配置"
        } catch {
            relaySaveStatus = "保存失败：\(error.localizedDescription)"
        }
    }

    private func selectClaudeProfile(_ profile: ClaudeRelayProfile) {
        applyClaudeProfile(profile)
        selectedClaudeProfileID = profile.id
        configProfiles.activeClaudeRelayProfileID = profile.id
        do {
            try persistConfigProfiles()
            try writeClaudeSettings(updateSelectedProfile: false)
            relaySaveStatus = "已切换配置：\(profile.name)"
        } catch {
            relaySaveStatus = "切换失败：\(error.localizedDescription)"
        }
    }

    private func deleteClaudeProfile(_ profile: ClaudeRelayProfile) {
        let wasSelected = selectedClaudeProfileID == profile.id
        configProfiles.claudeRelayProfiles.removeAll { $0.id == profile.id }
        if wasSelected {
            selectedClaudeProfileID = configProfiles.claudeRelayProfiles.first?.id
            configProfiles.activeClaudeRelayProfileID = selectedClaudeProfileID
            if let selectedClaudeProfileID,
               let next = configProfiles.claudeRelayProfiles.first(where: { $0.id == selectedClaudeProfileID }) {
                applyClaudeProfile(next)
            }
        }
        do {
            try persistConfigProfiles()
            if wasSelected, selectedClaudeProfileID != nil {
                try writeClaudeSettings(updateSelectedProfile: false)
            }
            relaySaveStatus = "已删除配置"
        } catch {
            relaySaveStatus = "删除失败：\(error.localizedDescription)"
        }
    }

    private func addCodexProfile() {
        let profile = currentCodexProfile(named: nextProfileName(newCodexProfileName, fallback: "Codex 配置", count: configProfiles.codexProfiles.count))
        configProfiles.codexProfiles.insert(profile, at: 0)
        configProfiles.activeCodexProfileID = profile.id
        selectedCodexProfileID = profile.id
        newCodexProfileName = ""
        do {
            try persistConfigProfiles()
            try writeCodexSettings(updateSelectedProfile: false)
            codexSaveStatus = "已添加并切换配置"
        } catch {
            codexSaveStatus = "保存失败：\(error.localizedDescription)"
        }
    }

    private func selectCodexProfile(_ profile: CodexConfigProfile) {
        applyCodexProfile(profile)
        selectedCodexProfileID = profile.id
        configProfiles.activeCodexProfileID = profile.id
        do {
            try persistConfigProfiles()
            try writeCodexSettings(updateSelectedProfile: false)
            codexSaveStatus = "已切换配置：\(profile.name)"
        } catch {
            codexSaveStatus = "切换失败：\(error.localizedDescription)"
        }
    }

    private func deleteCodexProfile(_ profile: CodexConfigProfile) {
        let wasSelected = selectedCodexProfileID == profile.id
        configProfiles.codexProfiles.removeAll { $0.id == profile.id }
        if wasSelected {
            selectedCodexProfileID = configProfiles.codexProfiles.first?.id
            configProfiles.activeCodexProfileID = selectedCodexProfileID
            if let selectedCodexProfileID,
               let next = configProfiles.codexProfiles.first(where: { $0.id == selectedCodexProfileID }) {
                applyCodexProfile(next)
            }
        }
        do {
            try persistConfigProfiles()
            if wasSelected, selectedCodexProfileID != nil {
                try writeCodexSettings(updateSelectedProfile: false)
            }
            codexSaveStatus = "已删除配置"
        } catch {
            codexSaveStatus = "删除失败：\(error.localizedDescription)"
        }
    }

    private func applyClaudeProfile(_ profile: ClaudeRelayProfile) {
        anthropicBaseURL = profile.baseURL
        anthropicAuthToken = profile.authToken
        anthropicModel = profile.model
        anthropicHaikuModel = profile.haikuModel
        anthropicSonnetModel = profile.sonnetModel
        anthropicOpusModel = profile.opusModel
        httpProxy = profile.httpProxy
        httpsProxy = profile.httpsProxy
    }

    private func applyCodexProfile(_ profile: CodexConfigProfile) {
        codexAuthMode = profile.authMode == CodexAuthMode.account.rawValue ? .account : .apiKey
        codexModel = profile.model
        codexBaseURL = profile.baseURL
        codexApiKey = profile.apiKey
        codexWireApi = profile.wireApi.isEmpty ? "responses" : profile.wireApi
    }

    private func currentClaudeProfile(named name: String, id: UUID = UUID()) -> ClaudeRelayProfile {
        let now = Date()
        return ClaudeRelayProfile(
            id: id,
            name: name,
            baseURL: anthropicBaseURL,
            authToken: anthropicAuthToken,
            model: anthropicModel,
            haikuModel: anthropicHaikuModel,
            sonnetModel: anthropicSonnetModel,
            opusModel: anthropicOpusModel,
            httpProxy: httpProxy,
            httpsProxy: httpsProxy,
            createdAt: now,
            updatedAt: now
        )
    }

    private func currentCodexProfile(named name: String, id: UUID = UUID()) -> CodexConfigProfile {
        let now = Date()
        return CodexConfigProfile(
            id: id,
            name: name,
            authMode: codexAuthMode.rawValue,
            model: codexModel,
            baseURL: codexBaseURL,
            apiKey: codexApiKey,
            wireApi: codexWireApi,
            createdAt: now,
            updatedAt: now
        )
    }

    private func updateSelectedClaudeProfile() throws {
        guard let selectedClaudeProfileID,
              let index = configProfiles.claudeRelayProfiles.firstIndex(where: { $0.id == selectedClaudeProfileID }) else { return }
        var updated = currentClaudeProfile(named: configProfiles.claudeRelayProfiles[index].name, id: selectedClaudeProfileID)
        updated.createdAt = configProfiles.claudeRelayProfiles[index].createdAt
        updated.updatedAt = Date()
        configProfiles.claudeRelayProfiles[index] = updated
        configProfiles.activeClaudeRelayProfileID = selectedClaudeProfileID
        try persistConfigProfiles()
    }

    private func updateSelectedCodexProfile() throws {
        guard let selectedCodexProfileID,
              let index = configProfiles.codexProfiles.firstIndex(where: { $0.id == selectedCodexProfileID }) else { return }
        var updated = currentCodexProfile(named: configProfiles.codexProfiles[index].name, id: selectedCodexProfileID)
        updated.createdAt = configProfiles.codexProfiles[index].createdAt
        updated.updatedAt = Date()
        configProfiles.codexProfiles[index] = updated
        configProfiles.activeCodexProfileID = selectedCodexProfileID
        try persistConfigProfiles()
    }

    private func nextProfileName(_ rawName: String, fallback: String, count: Int) -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "\(fallback) \(count + 1)" : name
    }

    // MARK: - Claude Settings (relay)

    private func loadClaudeSettings() {
        guard let data = try? Data(contentsOf: Self.claudeSettingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = json["env"] as? [String: Any] else { return }

        anthropicBaseURL = env["ANTHROPIC_BASE_URL"] as? String ?? ""
        anthropicAuthToken = env["ANTHROPIC_AUTH_TOKEN"] as? String ?? ""
        anthropicModel = env["ANTHROPIC_MODEL"] as? String ?? ""
        anthropicHaikuModel = env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] as? String ?? ""
        anthropicSonnetModel = env["ANTHROPIC_DEFAULT_SONNET_MODEL"] as? String ?? ""
        anthropicOpusModel = env["ANTHROPIC_DEFAULT_OPUS_MODEL"] as? String ?? ""
        httpProxy = env["HTTP_PROXY"] as? String ?? ""
        httpsProxy = env["HTTPS_PROXY"] as? String ?? ""
    }

    private func saveClaudeSettings() {
        relaySaveStatus = ""

        do {
            try writeClaudeSettings(updateSelectedProfile: true)
            relaySaveStatus = "保存成功"
        } catch {
            relaySaveStatus = "保存失败：\(error.localizedDescription)"
        }
    }

    private func writeClaudeSettings(updateSelectedProfile: Bool) throws {
        let claudeDir = Self.claudeSettingsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: Self.claudeSettingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var env = (json["env"] as? [String: Any]) ?? [:]

        let fields: [(String, String)] = [
            ("ANTHROPIC_BASE_URL", anthropicBaseURL),
            ("ANTHROPIC_AUTH_TOKEN", anthropicAuthToken),
            ("ANTHROPIC_MODEL", anthropicModel),
            ("ANTHROPIC_DEFAULT_HAIKU_MODEL", anthropicHaikuModel),
            ("ANTHROPIC_DEFAULT_SONNET_MODEL", anthropicSonnetModel),
            ("ANTHROPIC_DEFAULT_OPUS_MODEL", anthropicOpusModel),
            ("HTTP_PROXY", httpProxy),
            ("HTTPS_PROXY", httpsProxy),
        ]

        for (key, value) in fields {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                env.removeValue(forKey: key)
            } else {
                env[key] = trimmed
            }
        }

        json["env"] = env

        let outputData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: Self.claudeSettingsURL, options: .atomic)
        if updateSelectedProfile {
            try updateSelectedClaudeProfile()
        }
        modelService.reloadConfiguredModels()
        modelService.fetchClaudeModels(baseURL: anthropicBaseURL, apiKey: anthropicAuthToken)
    }

    // MARK: - Codex Settings

    private func loadCodexSettings() {
        codexAccountStatus = ""
        codexApiKey = ""
        var configuredProvider = ""

        // 读取 config.toml
        if let text = try? String(contentsOf: Self.codexConfigURL, encoding: .utf8) {
            codexModel = parseTomlValue(text, key: "model") ?? ""
            configuredProvider = parseTomlValue(text, key: "model_provider") ?? ""

            let providerSection = configuredProvider.isEmpty ? "acode_custom" : configuredProvider
            if let customSection = extractTomlSection(text, section: "model_providers.\(providerSection)") {
                codexBaseURL = parseTomlValue(customSection, key: "base_url") ?? ""
                codexWireApi = parseTomlValue(customSection, key: "wire_api") ?? "responses"
            }
        }

        // 读取 auth.json
        if let data = try? Data(contentsOf: Self.codexAuthURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let key = json["OPENAI_API_KEY"] as? String {
                codexApiKey = key
            }
            if let status = codexOAuthStatus(from: json) {
                codexAccountStatus = status
            }
        }

        if codexAccountStatus.isEmpty {
            if FileManager.default.fileExists(atPath: Self.ccSwitchCodexOAuthURL.path) {
                codexAccountStatus = "未在 ~/.codex/auth.json 检测到账号登录态，但 cc-switch 有可导入的 Codex OAuth 登录态。"
            } else if !codexApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                codexAccountStatus = "~/.codex/auth.json 当前是 API Key。账号登录请运行 codex login，或从 cc-switch 导入 OAuth 登录态。"
            } else {
                codexAccountStatus = "未检测到账号登录态。可在终端运行 codex login。"
            }
        }

        if configuredProvider == "custom" || configuredProvider == "acode_custom" {
            codexAuthMode = .apiKey
        } else {
            codexAuthMode = .account
        }
    }

    private func saveCodexSettings() {
        codexSaveStatus = ""

        do {
            try writeCodexSettings(updateSelectedProfile: true)
            codexSaveStatus = codexAuthMode == .apiKey
                ? "保存成功（API Key）"
                : (codexAccountStatus.contains("检测到") || codexAccountStatus.contains("已导入") ? "保存成功（账号登录）" : "已保存模型；请先运行 codex login")
        } catch {
            codexSaveStatus = "保存失败：\(error.localizedDescription)"
        }
    }

    private func writeCodexSettings(updateSelectedProfile: Bool) throws {
        let codexDir = Self.codexConfigURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        let previousConfigData = try? Data(contentsOf: Self.codexConfigURL)
        let previousAuthData = try? Data(contentsOf: Self.codexAuthURL)

        do {
            let providerID = "acode_custom"
            var configText = (try? String(contentsOf: Self.codexConfigURL, encoding: .utf8)) ?? ""
            configText = updateTomlValue(configText, key: "model", value: codexModel.isEmpty ? "gpt-5.5" : codexModel)

            var authDataToWrite: Data?
            if codexAuthMode == .apiKey {
                configText = updateTomlValue(configText, key: "model_provider", value: providerID)
                configText = updateTomlSectionValue(configText, section: "model_providers.\(providerID)", key: "name", value: providerID)
                configText = updateTomlSectionValue(configText, section: "model_providers.\(providerID)", key: "base_url", value: codexBaseURL)
                configText = updateTomlSectionValue(configText, section: "model_providers.\(providerID)", key: "wire_api", value: codexWireApi)
                configText = updateTomlSectionRawValue(configText, section: "model_providers.\(providerID)", key: "requires_openai_auth", value: "true")

                var authJson: [String: Any] = [:]
                if let data = try? Data(contentsOf: Self.codexAuthURL),
                   let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    authJson = existing
                }

                let trimmedKey = codexApiKey.trimmingCharacters(in: .whitespaces)
                if trimmedKey.isEmpty {
                    authJson.removeValue(forKey: "OPENAI_API_KEY")
                } else {
                    authJson["OPENAI_API_KEY"] = trimmedKey
                }
                authDataToWrite = try JSONSerialization.data(withJSONObject: authJson, options: [.prettyPrinted, .sortedKeys])
            } else {
                configText = removeTopLevelTomlValue(configText, key: "model_provider")
            }

            try configText.write(to: Self.codexConfigURL, atomically: true, encoding: .utf8)
            if let authDataToWrite {
                try authDataToWrite.write(to: Self.codexAuthURL, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.codexAuthURL.path)
            } else {
                refreshCodexAccountStatus()
            }

            if updateSelectedProfile {
                try updateSelectedCodexProfile()
            }
            modelService.reloadConfiguredModels()
            modelService.fetchCodexModels(baseURL: codexBaseURL, apiKey: codexApiKey)
        } catch {
            restoreFile(at: Self.codexConfigURL, data: previousConfigData)
            restoreFile(at: Self.codexAuthURL, data: previousAuthData)
            throw error
        }
    }

    private func importCodexOAuthFromCCSwitch() {
        codexSaveStatus = ""

        do {
            let data = try Data(contentsOf: Self.ccSwitchCodexOAuthURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  codexOAuthStatus(from: json) != nil else {
                codexSaveStatus = "导入失败：cc-switch 登录态格式不符合 Codex OAuth"
                return
            }

            let codexDir = Self.codexAuthURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: Self.codexAuthURL.path) {
                let stamp = Self.backupTimestamp()
                let backupURL = codexDir.appendingPathComponent("auth.json.backup-\(stamp)")
                try? FileManager.default.copyItem(at: Self.codexAuthURL, to: backupURL)
            }

            try data.write(to: Self.codexAuthURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.codexAuthURL.path)

            codexAuthMode = .account
            codexApiKey = ""
            refreshCodexAccountStatus()
            codexSaveStatus = "已导入 cc-switch 登录态，请保存"
        } catch {
            codexSaveStatus = "导入失败：\(error.localizedDescription)"
        }
    }

    private func refreshCodexAccountStatus() {
        guard let data = try? Data(contentsOf: Self.codexAuthURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = codexOAuthStatus(from: json) else {
            codexAccountStatus = FileManager.default.fileExists(atPath: Self.ccSwitchCodexOAuthURL.path)
                ? "未在 ~/.codex/auth.json 检测到账号登录态，但 cc-switch 有可导入的 Codex OAuth 登录态。"
                : "未检测到账号登录态。可在终端运行 codex login。"
            return
        }
        codexAccountStatus = status
    }

    private func codexOAuthStatus(from json: [String: Any]) -> String? {
        guard let accounts = json["accounts"] as? [String: Any], !accounts.isEmpty else { return nil }
        let defaultID = json["default_account_id"] as? String

        if let defaultID,
           let account = accounts[defaultID] as? [String: Any],
           let refreshToken = account["refresh_token"] as? String,
           !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let email = account["email"] as? String, !email.isEmpty {
                return "检测到 Codex 账号登录态：\(email)"
            }
            return "检测到 Codex 账号登录态。"
        }

        for value in accounts.values {
            guard let account = value as? [String: Any],
                  let refreshToken = account["refresh_token"] as? String,
                  !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let email = account["email"] as? String, !email.isEmpty {
                return "检测到 Codex 账号登录态：\(email)"
            }
            return "检测到 Codex 账号登录态。"
        }

        return nil
    }

    // MARK: - TOML Helpers

    private func parseTomlValue(_ text: String, key: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        var isInsideSection = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && !trimmed.hasPrefix("[[") {
                isInsideSection = true
                continue
            }
            guard !isInsideSection else { continue }
            guard isTomlAssignment(trimmed, key: key) else { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let rawValue = parts[1].trimmingCharacters(in: .whitespaces)
            if rawValue.hasPrefix("\"") && rawValue.hasSuffix("\"") {
                return String(rawValue.dropFirst().dropLast())
            }
            return rawValue
        }
        return nil
    }

    private func extractTomlSection(_ text: String, section: String) -> String? {
        let header = "[\(section)]"
        let lines = text.components(separatedBy: .newlines)
        var inSection = false
        var result: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == header {
                inSection = true
                continue
            }
            if inSection {
                if trimmed.hasPrefix("[") && !trimmed.hasPrefix("[[") {
                    break
                }
                result.append(line)
            }
        }

        return inSection ? result.joined(separator: "\n") : nil
    }

    private func updateTomlValue(_ text: String, key: String, value: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var found = false
        var isInsideSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && !trimmed.hasPrefix("[[") {
                isInsideSection = true
                result.append(line)
                continue
            }

            if !isInsideSection && isTomlAssignment(trimmed, key: key) {
                result.append(tomlAssignment(key: key, value: value))
                found = true
            } else {
                result.append(line)
            }
        }

        if !found {
            let insertIndex = result.firstIndex { line in
                line.trimmingCharacters(in: .whitespaces).hasPrefix("[")
            } ?? result.count
            result.insert(tomlAssignment(key: key, value: value), at: insertIndex)
        }

        return result.joined(separator: "\n")
    }

    private func updateTomlSectionValue(_ text: String, section: String, key: String, value: String) -> String {
        updateTomlSectionRawValue(text, section: section, key: key, value: tomlQuoted(value))
    }

    private func updateTomlSectionRawValue(_ text: String, section: String, key: String, value: String) -> String {
        let header = "[\(section)]"
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var inSection = false
        var found = false
        var didFindSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == header {
                inSection = true
                didFindSection = true
                result.append(line)
                continue
            }
            if inSection {
                if trimmed.hasPrefix("[") && !trimmed.hasPrefix("[[") {
                    // Leaving section — insert if not found
                    if !found && !value.isEmpty {
                        result.append("\(key) = \(value)")
                    }
                    inSection = false
                    result.append(line)
                    continue
                }
                if isTomlAssignment(trimmed, key: key) {
                    if !value.isEmpty {
                        result.append("\(key) = \(value)")
                    }
                    found = true
                    continue
                }
            }
            result.append(line)
        }

        // If still in section at end of file
        if inSection && !found && !value.isEmpty {
            result.append("\(key) = \(value)")
        }

        if !didFindSection && !value.isEmpty {
            if !result.isEmpty && result.last?.isEmpty == false {
                result.append("")
            }
            result.append(header)
            result.append("\(key) = \(value)")
        }

        return result.joined(separator: "\n")
    }

    private func restoreFile(at url: URL, data: Data?) {
        if let data {
            try? data.write(to: url, options: .atomic)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func removeTopLevelTomlValue(_ text: String, key: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var isInsideSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && !trimmed.hasPrefix("[[") {
                isInsideSection = true
                result.append(line)
                continue
            }

            if !isInsideSection && isTomlAssignment(trimmed, key: key) {
                continue
            }
            result.append(line)
        }

        return result.joined(separator: "\n")
    }

    private func isTomlAssignment(_ line: String, key: String) -> Bool {
        line == key || line.hasPrefix("\(key) ") || line.hasPrefix("\(key)=")
    }

    private func tomlAssignment(key: String, value: String) -> String {
        "\(key) = \(tomlQuoted(value))"
    }

    private func tomlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { result, value in
            if !result.contains(value) { result.append(value) }
        }
    }

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: Date())
    }

    // MARK: - Model Picker UI

    private func modelPicker(label: String, selection: Binding<String>, models: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(label)
            HStack(spacing: 10) {
                TextField("模型 ID", text: selection)
                    .settingsTextFieldChrome()
                    .frame(maxWidth: .infinity)

                Menu {
                    Button("不设置") { selection.wrappedValue = "" }
                    Divider()
                    ForEach(models, id: \.self) { model in
                        Button(model) { selection.wrappedValue = model }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selection.wrappedValue.isEmpty ? "选择" : "切换")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    // MARK: - Fetch Models

    private func fetchClaudeModels() {
        let baseURL = anthropicBaseURL.trimmingCharacters(in: .whitespaces)
        guard !baseURL.isEmpty else { return }

        isFetchingClaudeModels = true
        claudeModelList = []

        // 尝试 /v1/models 和 /models 两个端点
        let candidates = [
            baseURL.hasSuffix("/") ? baseURL + "v1/models" : baseURL + "/v1/models",
            baseURL.hasSuffix("/") ? baseURL + "models" : baseURL + "/models",
        ]

        Task {
            for urlString in candidates {
                guard let url = URL(string: urlString) else { continue }
                var request = URLRequest(url: url, timeoutInterval: 15)
                request.httpMethod = "GET"
                let token = anthropicAuthToken.trimmingCharacters(in: .whitespaces)
                if !token.isEmpty {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue(token, forHTTPHeaderField: "x-api-key")
                }

                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { continue }
                    if let models = parseModelListResponse(data) {
                        await MainActor.run {
                            claudeModelList = models.sorted()
                            isFetchingClaudeModels = false
                        }
                        return
                    }
                } catch {
                    continue
                }
            }

            await MainActor.run {
                isFetchingClaudeModels = false
                relaySaveStatus = "拉取模型失败"
            }
        }
    }

    private func fetchCodexModels() {
        let baseURL = codexBaseURL.trimmingCharacters(in: .whitespaces)
        guard !baseURL.isEmpty else { return }

        isFetchingCodexModels = true
        codexModelList = []

        let candidates = [
            baseURL.hasSuffix("/") ? baseURL + "models" : baseURL + "/models",
        ]

        Task {
            for urlString in candidates {
                guard let url = URL(string: urlString) else { continue }
                var request = URLRequest(url: url, timeoutInterval: 15)
                request.httpMethod = "GET"
                let token = codexApiKey.trimmingCharacters(in: .whitespaces)
                if !token.isEmpty {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }

                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { continue }
                    if let models = parseModelListResponse(data) {
                        await MainActor.run {
                            codexModelList = models.sorted()
                            isFetchingCodexModels = false
                        }
                        return
                    }
                } catch {
                    continue
                }
            }

            await MainActor.run {
                isFetchingCodexModels = false
                codexSaveStatus = "拉取模型失败"
            }
        }
    }

    /// 解析 OpenAI 兼容的 /models 响应
    private func parseModelListResponse(_ data: Data) -> [String]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // OpenAI 格式: { "data": [{ "id": "model-name", ... }] }
        if let dataArray = json["data"] as? [[String: Any]] {
            let ids = dataArray.compactMap { $0["id"] as? String }
            return ids.isEmpty ? nil : ids
        }

        // 有些中转站直接返回数组
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let ids = arr.compactMap { $0["id"] as? String }
            return ids.isEmpty ? nil : ids
        }

        return nil
    }
}

private extension View {
    func settingsTextFieldChrome() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
    }
}

private struct SettingsPrimaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, compact ? 11 : 16)
            .frame(height: compact ? 32 : 40)
            .background(configuration.isPressed ? Color.black.opacity(0.035) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SettingsSecondaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, compact ? 10 : 14)
            .frame(height: compact ? 30 : 38)
            .background(configuration.isPressed ? Color.black.opacity(0.03) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 11 : 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: compact ? 11 : 14, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
