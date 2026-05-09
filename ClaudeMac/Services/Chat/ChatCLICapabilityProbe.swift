import Foundation

struct ChatCLICapability: Codable, Equatable {
    let cli: CLIType
    let executablePath: String?
    let version: String?
    let supportsStreamJSON: Bool
    let supportsStreamJSONInput: Bool
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
                supportsStreamJSONInput: false,
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
        let launchError = launchErrorMessage(
            cli: visible,
            executable: executable,
            versionOutput: versionOutput,
            helpOutput: helpOutput
        )

        switch visible {
        case .claude:
            return ChatCLICapability(
                cli: visible,
                executablePath: executable,
                version: version,
                supportsStreamJSON: launchError == nil && help.contains("stream-json"),
                supportsStreamJSONInput: launchError == nil && help.contains("--input-format") && help.contains("stream-json"),
                supportsPermissionPromptTool: help.contains("permission-prompt-tool"),
                supportsResume: launchError == nil && help.contains("--resume"),
                supportsContinue: launchError == nil && help.contains("--continue"),
                supportsAppServer: false,
                errorMessage: launchError
            )
        case .codex:
            let appServerHelp = await ChatProcessRunner.run(executable, arguments: ["app-server", "--help"], timeout: 5)
            let appServerText = appServerHelp.stdout + "\n" + appServerHelp.stderr
            return ChatCLICapability(
                cli: visible,
                executablePath: executable,
                version: version,
                supportsStreamJSON: launchError == nil,
                supportsStreamJSONInput: false,
                supportsPermissionPromptTool: false,
                supportsResume: launchError == nil && help.contains("resume"),
                supportsContinue: launchError == nil && help.contains("resume"),
                supportsAppServer: launchError == nil && (appServerHelp.status == 0 || appServerText.contains("listen") || appServerText.contains("app-server")),
                errorMessage: launchError
            )
        case .gemini, .custom:
            return await probe(.claude)
        }
    }

    private static func locateExecutable(named name: String) async -> String? {
        for candidate in ChatCLIEnvironment.executableCandidatePaths(named: name) where FileManager.default.fileExists(atPath: candidate) {
            return canonicalExecutablePath(candidate)
        }

        let shellOutput = await ChatProcessRunner.run(
            "/bin/zsh",
            arguments: ["-lc", "PATH=\(ChatCLIEnvironment.defaultPath):$PATH; command -v \(name)"],
            timeout: 4
        )
        if shellOutput.status == 0, let path = shellOutput.stdout.nonEmptyTrimmed {
            return path.components(separatedBy: .newlines).first?.nonEmptyTrimmed.map(canonicalExecutablePath)
        }

        let output = await ChatProcessRunner.run("/usr/bin/env", arguments: ["which", name], timeout: 4)
        guard output.status == 0, let path = output.stdout.nonEmptyTrimmed else { return nil }
        return path.components(separatedBy: .newlines).first?.nonEmptyTrimmed.map(canonicalExecutablePath)
    }

    private static func canonicalExecutablePath(_ path: String) -> String {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return FileManager.default.fileExists(atPath: resolved) ? resolved : path
    }

    private static func launchErrorMessage(
        cli: CLIType,
        executable: String,
        versionOutput: ChatProcessOutput,
        helpOutput: ChatProcessOutput
    ) -> String? {
        guard versionOutput.status == 127 || helpOutput.status == 127 else { return nil }
        let message = versionOutput.stderr.nonEmptyTrimmed
            ?? helpOutput.stderr.nonEmptyTrimmed
            ?? "未知启动错误"
        return "已找到 \(cli.displayName)：\(executable)，但无法启动：\(message)"
    }
}
