import Foundation

protocol ChatProcessBackend: AnyObject {
    func start(prompt: String, options: ChatRunOptions, session: ChatSessionRecord?) -> AsyncThrowingStream<ChatBackendEvent, Error>
    func interrupt()
    func respondToPermission(requestID: String, allowed: Bool)
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

enum ChatCLIEnvironment {
    static let defaultPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

    static var processEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = mergePath(existingPath)
        return environment
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
