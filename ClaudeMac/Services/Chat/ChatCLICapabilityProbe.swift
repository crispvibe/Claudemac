import Foundation

struct ChatCLICapability: Codable, Equatable {
    let cli: CLIType
    let executablePath: String?
    let version: String?
    let supportsStreamJSON: Bool
    let supportsPermissionPromptTool: Bool
    let supportsResume: Bool
    let supportsContinue: Bool
    let supportsAppServer: Bool
    let errorMessage: String?

    var isAvailable: Bool { executablePath != nil && errorMessage == nil }
}

enum ChatCLICapabilityProbe {
    static func probeAll() async -> [CLIType: ChatCLICapability] {
        var result: [CLIType: ChatCLICapability] = [:]
        result[.claude] = await probe(.claude)
        result[.codex] = await probe(.codex)
        return result
    }

    static func probe(_ cli: CLIType) async -> ChatCLICapability {
        let visible = cli.visibleValue
        guard let executable = await locateExecutable(named: visible.executable) else {
            return ChatCLICapability(
                cli: visible,
                executablePath: nil,
                version: nil,
                supportsStreamJSON: false,
                supportsPermissionPromptTool: false,
                supportsResume: false,
                supportsContinue: false,
                supportsAppServer: false,
                errorMessage: "未找到 \(visible.executable)，请先安装或把它加入 PATH。"
            )
        }

        let versionOutput = await ChatProcessRunner.run(executable, arguments: ["--version"], timeout: 5)
        let helpOutput = await ChatProcessRunner.run(executable, arguments: ["--help"], timeout: 5)
        let help = helpOutput.stdout + "\n" + helpOutput.stderr
        let version = (versionOutput.stdout.nonEmptyTrimmed ?? versionOutput.stderr.nonEmptyTrimmed)

        switch visible {
        case .claude:
            return ChatCLICapability(
                cli: visible,
                executablePath: executable,
                version: version,
                supportsStreamJSON: help.contains("stream-json"),
                supportsPermissionPromptTool: help.contains("permission-prompt-tool"),
                supportsResume: help.contains("--resume"),
                supportsContinue: help.contains("--continue"),
                supportsAppServer: false,
                errorMessage: nil
            )
        case .codex:
            let appServerHelp = await ChatProcessRunner.run(executable, arguments: ["app-server", "--help"], timeout: 5)
            let appServerText = appServerHelp.stdout + "\n" + appServerHelp.stderr
            return ChatCLICapability(
                cli: visible,
                executablePath: executable,
                version: version,
                supportsStreamJSON: true,
                supportsPermissionPromptTool: false,
                supportsResume: help.contains("resume"),
                supportsContinue: help.contains("resume"),
                supportsAppServer: appServerHelp.status == 0 || appServerText.contains("listen") || appServerText.contains("app-server"),
                errorMessage: nil
            )
        case .gemini, .custom:
            return await probe(.claude)
        }
    }

    private static func locateExecutable(named name: String) async -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/opt/homebrew/sbin/\(name)",
            "/usr/local/sbin/\(name)"
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }

        let shellOutput = await ChatProcessRunner.run(
            "/bin/zsh",
            arguments: ["-lc", "PATH=\(ChatCLIEnvironment.defaultPath):$PATH; command -v \(name)"],
            timeout: 4
        )
        if shellOutput.status == 0, let path = shellOutput.stdout.nonEmptyTrimmed {
            return path.components(separatedBy: .newlines).first?.nonEmptyTrimmed
        }

        let output = await ChatProcessRunner.run("/usr/bin/env", arguments: ["which", name], timeout: 4)
        guard output.status == 0, let path = output.stdout.nonEmptyTrimmed else { return nil }
        return path.components(separatedBy: .newlines).first?.nonEmptyTrimmed
    }
}
