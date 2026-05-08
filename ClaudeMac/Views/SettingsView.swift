import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var defaultCLI: CLIType = .claude
    @State private var defaultTerminal: TerminalType = .terminal
    @State private var showCommandPreview = true
    @State private var enableClaudeHistoryScan = true
    @State private var ignoredFoldersText = ""

    var body: some View {
        Form {
            Section("默认工具") {
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
            }

            Section("历史会话") {
                Toggle("扫描 Claude / Codex 历史会话（实验功能）", isOn: $enableClaudeHistoryScan)
            }

            Section("界面") {
                Toggle("显示命令预览", isOn: $showCommandPreview)
            }

            Section("忽略目录") {
                TextEditor(text: $ignoredFoldersText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                Text("每行一个目录名。保存后会刷新当前项目文件树。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("恢复默认忽略目录") {
                    ignoredFoldersText = FileTreeScanner.defaultIgnoredNames.sorted().joined(separator: "\n")
                }
                Button("保存设置") {
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
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 520)
        .onAppear {
            defaultCLI = appState.settings.defaultCLI.visibleValue
            defaultTerminal = appState.settings.defaultTerminal
            showCommandPreview = appState.settings.showCommandPreview
            enableClaudeHistoryScan = appState.settings.enableClaudeHistoryScan
            ignoredFoldersText = appState.settings.ignoredFolders.joined(separator: "\n")
        }
    }
}
