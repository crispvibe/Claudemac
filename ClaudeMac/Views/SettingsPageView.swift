import SwiftUI

struct SettingsPageView: View {
    private enum CodexAuthMode: String, CaseIterable, Identifiable {
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
            Divider().opacity(0.3)
            ScrollView {
                VStack(spacing: 22) {
                    generalSection
                    relaySection
                    codexSection
                    updateSection
                    aboutSection
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 28)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.editorSurface.opacity(0.86))
        .onAppear {
            loadSettings()
            loadClaudeSettings()
            loadCodexSettings()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { appState.showSettings = false }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("返回")
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Text("设置")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            // Balance spacer
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text("返回")
                    .font(.system(size: 14, weight: .medium))
            }
            .opacity(0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - General

    private var generalSection: some View {
        settingsCard(title: "通用") {
            settingsGrid {
                Picker("默认 CLI", selection: $defaultCLI) {
                    ForEach(CLIType.visibleCases) { cli in
                        Text(cli.displayName).tag(cli)
                    }
                }

                Picker("默认终端", selection: $defaultTerminal) {
                    ForEach(TerminalType.allCases) { terminal in
                        Text(terminal.displayName).tag(terminal)
                    }
                }

                Toggle("显示命令预览", isOn: $showCommandPreview)
                Toggle("扫描 Claude / Codex 历史会话", isOn: $enableClaudeHistoryScan)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("忽略目录")
                    .font(.system(size: 13, weight: .medium))
                TextEditor(text: $ignoredFoldersText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.hairline, lineWidth: 1))
                Text("每行一个目录名")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("恢复默认") {
                    ignoredFoldersText = FileTreeScanner.defaultIgnoredNames.sorted().joined(separator: "\n")
                }
                Spacer()
                Button("保存") { saveAppSettings() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Relay / Proxy

    private var relaySection: some View {
        settingsCard(title: "中转站（Claude Code）") {
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
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
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
            }

            Text("代理字段会从 ~/.claude/settings.json 注入到新启动的 Claude Code / Codex 子进程。留空的字段不会写入配置文件。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Update

    private var codexSection: some View {
        settingsCard(title: "Codex") {
            Group {
                settingsGrid {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("认证方式")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $codexAuthMode) {
                            ForEach(CodexAuthMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
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
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
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
                            Picker("", selection: $codexWireApi) {
                                Text("responses").tag("responses")
                                Text("chat").tag("chat")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
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
            }

            Text(codexAuthMode == .apiKey
                 ? "修改 ~/.codex/config.toml 和 ~/.codex/auth.json。保存后新启动的 Codex 会话将使用新配置。"
                 : "账号登录模式只修改 ~/.codex/config.toml 的模型配置，认证复用 Codex CLI 的 OAuth 登录态。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
                .disabled(!FileManager.default.fileExists(atPath: Self.ccSwitchCodexOAuthURL.path))

                Button("重新检测") {
                    loadCodexSettings()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.editorSurface.opacity(0.55))
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
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        settingsCard(title: "关于") {
            VStack(alignment: .leading, spacing: 8) {
                Text("ClaudeMac")
                    .font(.system(size: 15, weight: .semibold))
                Text("一个轻量级的 Claude Code / Codex 桌面客户端")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - UI Helpers

    private func envField(label: String, placeholder: String, text: Binding<String>, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            if secure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func settingsGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 280), spacing: 14, alignment: .topLeading)
            ],
            alignment: .leading,
            spacing: 12
        ) {
            content()
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.controlSurface.opacity(0.52))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
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

    // MARK: - Claude Settings (relay)

    private func loadClaudeSettings() {
        guard let data = try? Data(contentsOf: Self.claudeSettingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = json["env"] as? [String: String] else { return }

        anthropicBaseURL = env["ANTHROPIC_BASE_URL"] ?? ""
        anthropicAuthToken = env["ANTHROPIC_AUTH_TOKEN"] ?? ""
        anthropicModel = env["ANTHROPIC_MODEL"] ?? ""
        anthropicHaikuModel = env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] ?? ""
        anthropicSonnetModel = env["ANTHROPIC_DEFAULT_SONNET_MODEL"] ?? ""
        anthropicOpusModel = env["ANTHROPIC_DEFAULT_OPUS_MODEL"] ?? ""
        httpProxy = env["HTTP_PROXY"] ?? ""
        httpsProxy = env["HTTPS_PROXY"] ?? ""
    }

    private func saveClaudeSettings() {
        relaySaveStatus = ""

        do {
            // 确保目录存在
            let claudeDir = Self.claudeSettingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

            var json: [String: Any] = [:]
            if let data = try? Data(contentsOf: Self.claudeSettingsURL),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                json = existing
            }

            var env = (json["env"] as? [String: String]) ?? [:]

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
            modelService.reloadConfiguredModels()

            relaySaveStatus = "保存成功"
        } catch {
            relaySaveStatus = "保存失败：\(error.localizedDescription)"
        }
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

            // 从 [model_providers.custom] 段读取 base_url 和 wire_api
            if let customSection = extractTomlSection(text, section: "model_providers.custom") {
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

        if configuredProvider == "custom" {
            codexAuthMode = .apiKey
        } else {
            codexAuthMode = .account
        }
    }

    private func saveCodexSettings() {
        codexSaveStatus = ""

        do {
            // 确保目录存在
            let codexDir = Self.codexConfigURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

            // 读取现有 config.toml 并更新
            var existingText = (try? String(contentsOf: Self.codexConfigURL, encoding: .utf8)) ?? ""

            // 更新顶层字段
            existingText = updateTomlValue(existingText, key: "model", value: codexModel.isEmpty ? "gpt-5.5" : codexModel)

            if codexAuthMode == .apiKey {
                existingText = updateTomlValue(existingText, key: "model_provider", value: "custom")

                // 更新 [model_providers.custom] 段
                existingText = updateTomlSectionValue(existingText, section: "model_providers.custom", key: "name", value: "custom")
                existingText = updateTomlSectionValue(existingText, section: "model_providers.custom", key: "base_url", value: codexBaseURL)
                existingText = updateTomlSectionValue(existingText, section: "model_providers.custom", key: "wire_api", value: codexWireApi)
                existingText = updateTomlSectionRawValue(existingText, section: "model_providers.custom", key: "requires_openai_auth", value: "true")
            } else {
                // 账号登录走 Codex CLI 自己的 OAuth 登录态，不能继续强制 custom provider。
                existingText = removeTopLevelTomlValue(existingText, key: "model_provider")
            }

            try existingText.write(to: Self.codexConfigURL, atomically: true, encoding: .utf8)
            modelService.reloadConfiguredModels()

            if codexAuthMode == .apiKey {
                // 更新 auth.json — 只更新 OPENAI_API_KEY，保留其他字段。
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

                let authData = try JSONSerialization.data(withJSONObject: authJson, options: [.prettyPrinted, .sortedKeys])
                try authData.write(to: Self.codexAuthURL, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.codexAuthURL.path)
                codexSaveStatus = "保存成功（API Key）"
            } else {
                refreshCodexAccountStatus()
                codexSaveStatus = codexAccountStatus.contains("检测到") || codexAccountStatus.contains("已导入")
                    ? "保存成功（账号登录）"
                    : "已保存模型；请先运行 codex login"
            }
        } catch {
            codexSaveStatus = "保存失败：\(error.localizedDescription)"
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
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Picker("", selection: selection) {
                    Text("（不设置）").tag("")
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 120)
                // 也允许手动输入
                TextField("或手动输入", text: selection)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
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
