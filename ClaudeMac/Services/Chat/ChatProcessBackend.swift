import Darwin
import Foundation

protocol ChatProcessBackend: AnyObject {
    func start(prompt: String, options: ChatRunOptions, session: ChatSessionRecord?) -> AsyncThrowingStream<ChatBackendEvent, Error>
    func interrupt()
    func respondToPermission(requestID: String, decision: ChatPermissionDecision)
    func sendCompact()
}

struct ChatProcessOutput: Equatable {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum ChatProcessError: LocalizedError {
    case executableMissing(String)
    case launchFailed(String)
    case unsupported(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing(let executable): "未找到可执行文件：\(executable)"
        case .launchFailed(let message): "启动 CLI 失败：\(message)"
        case .unsupported(let message): message
        case .processFailed(let message): message
        }
    }
}

enum ChatPipeWriter {
    @discardableResult
    static func writeJSONObject(_ object: [String: Any], to pipe: Pipe?) -> Bool {
        guard let pipe,
              JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object) else { return false }
        data.append(Data("\n".utf8))
        do {
            try pipe.fileHandleForWriting.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }
}

enum ChatCLIEnvironment {
    static var realHomeDirectory: String {
        if let passwd = getpwuid(getuid()),
           let directory = passwd.pointee.pw_dir {
            return String(cString: directory)
        }
        return ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    }

    static var defaultPath: String {
        defaultPathComponents.joined(separator: ":")
    }

    static var defaultPathComponents: [String] {
        let home = realHomeDirectory
        return [
            "\(home)/.local/bin",
            "\(home)/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.bun/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
    }

    static func executableCandidatePaths(named name: String) -> [String] {
        defaultPathComponents
            .map { "\($0)/\(name)" }
            .reduce(into: [String]()) { result, item in
                if !result.contains(item) { result.append(item) }
            }
    }

    static var processEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? ""
        sanitizeInheritedAgentEnvironment(&environment)
        mergePersistedClaudeEnvironment(into: &environment)
        normalizeProxyValues(&environment)
        mirrorProxyValues(&environment)
        environment["HOME"] = realHomeDirectory
        environment.removeValue(forKey: "CLAUDE_CONFIG_DIR")
        environment["PATH"] = mergePath(existingPath)
        return environment
    }

    private static func sanitizeInheritedAgentEnvironment(_ environment: inout [String: String]) {
        let runtimeKeys = [
            "CODEX_CI",
            "CODEX_SANDBOX",
            "CODEX_THREAD_ID",
            "CODEX_INTERNAL_ORIGINATOR_OVERRIDE",
            "CODEX_SHELL",
            "__CFBundleIdentifier"
        ]
        runtimeKeys.forEach { environment.removeValue(forKey: $0) }
        normalizeProxyValues(&environment)
    }

    private static let proxyURLKeys = [
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "http_proxy",
        "https_proxy",
        "all_proxy"
    ]

    private static let proxyBypassKeys = [
        "NO_PROXY",
        "no_proxy"
    ]

    private static var proxyKeys: [String] {
        proxyURLKeys + proxyBypassKeys
    }

    private static func mergePersistedClaudeEnvironment(into environment: inout [String: String]) {
        for (key, value) in persistedClaudeEnvironment() {
            environment[key] = value
        }
    }

    private static func persistedClaudeEnvironment() -> [String: String] {
        let settingsURL = URL(fileURLWithPath: realHomeDirectory, isDirectory: true)
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = json["env"] as? [String: Any] else {
            return [:]
        }

        return env.reduce(into: [String: String]()) { result, item in
            guard isSupportedPersistedEnvironmentKey(item.key),
                  let value = item.value as? String,
                  let trimmed = value.nonEmptyTrimmed else { return }
            result[item.key] = trimmed
        }
    }

    private static func isSupportedPersistedEnvironmentKey(_ key: String) -> Bool {
        proxyKeys.contains(key)
            || key.hasPrefix("ANTHROPIC_")
            || key.hasPrefix("CLAUDE_CODE_")
    }

    private static func normalizeProxyValues(_ environment: inout [String: String]) {
        for key in proxyURLKeys {
            guard let rawValue = environment[key] else { continue }
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty || proxyURLHasMissingHost(value) {
                environment.removeValue(forKey: key)
                continue
            }
            environment[key] = value.replacingOccurrences(of: "127.0.01", with: "127.0.0.1")
        }

        for key in proxyBypassKeys {
            guard let rawValue = environment[key] else { continue }
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                environment.removeValue(forKey: key)
            } else {
                environment[key] = value
            }
        }
    }

    private static func mirrorProxyValues(_ environment: inout [String: String]) {
        mirrorProxyValue(upper: "HTTP_PROXY", lower: "http_proxy", environment: &environment)
        mirrorProxyValue(upper: "HTTPS_PROXY", lower: "https_proxy", environment: &environment)
        mirrorProxyValue(upper: "ALL_PROXY", lower: "all_proxy", environment: &environment)
        mirrorProxyValue(upper: "NO_PROXY", lower: "no_proxy", environment: &environment)
    }

    private static func mirrorProxyValue(upper: String, lower: String, environment: inout [String: String]) {
        if let upperValue = environment[upper], environment[lower] == nil {
            environment[lower] = upperValue
        } else if let lowerValue = environment[lower], environment[upper] == nil {
            environment[upper] = lowerValue
        }
    }

    private static func proxyURLHasMissingHost(_ value: String) -> Bool {
        guard value.contains("://") else { return false }
        guard let components = URLComponents(string: value) else { return true }
        return components.host?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    static func mergePath(_ path: String) -> String {
        let current = path.split(separator: ":").map(String.init)
        let defaults = defaultPath.split(separator: ":").map(String.init)
        return (defaults + current).reduce(into: [String]()) { result, item in
            if !result.contains(item) { result.append(item) }
        }.joined(separator: ":")
    }
}

enum ChatProcessRunner {
    static func run(_ executable: String, arguments: [String], timeout: TimeInterval = 8) async -> ChatProcessOutput {
        await Task.detached(priority: .utility) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = ChatCLIEnvironment.processEnvironment
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                return ChatProcessOutput(status: 127, stdout: "", stderr: error.localizedDescription)
            }

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if process.isRunning {
                process.terminate()
                try? await Task.sleep(nanoseconds: 150_000_000)
                if process.isRunning { process.interrupt() }
            }

            let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            return ChatProcessOutput(
                status: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            )
        }.value
    }
}

extension String {
    var nonEmptyTrimmed: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
