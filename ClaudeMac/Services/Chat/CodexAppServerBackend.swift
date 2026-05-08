import Foundation

final class CodexAppServerBackend: ChatProcessBackend {
    private var process: Process?
    private var inputPipe: Pipe?
    private var nextID = 1

    func start(prompt: String, options: ChatRunOptions, session: ChatSessionRecord?) -> AsyncThrowingStream<ChatBackendEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()
                let stdin = Pipe()
                process.executableURL = URL(fileURLWithPath: options.executablePath)
                process.arguments = ["app-server", "--listen", "stdio://"]
                process.environment = ChatCLIEnvironment.processEnvironment
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = stdin
                self.process = process
                self.inputPipe = stdin

                do {
                    continuation.yield(.appendMessage(kind: .command, title: "codex", subtitle: options.projectPath, text: "\(options.executablePath) app-server --listen stdio://", status: "start", requestID: nil))
                    try process.run()
                } catch {
                    continuation.yield(.failed(ChatProcessError.launchFailed(error.localizedDescription).localizedDescription))
                    continuation.finish()
                    return
                }

                self.send(method: "initialize", params: [:])
                let threadID = session?.externalSessionID ?? UUID().uuidString
                continuation.yield(.sessionID(threadID))
                self.send(method: "thread/start", params: [
                    "threadId": threadID,
                    "cwd": options.projectPath,
                    "model": options.modelID,
                    "approvalPolicy": options.permissionMode.codexApprovalPolicy,
                    "sandbox": options.permissionMode.codexSandbox
                ])
                self.send(method: "turn/start", params: [
                    "threadId": threadID,
                    "cwd": options.projectPath,
                    "input": [["type": "text", "text": prompt]],
                    "model": options.modelID,
                    "approvalPolicy": options.permissionMode.codexApprovalPolicy,
                    "sandbox": options.permissionMode.codexSandbox
                ])

                let stdoutTask = Task {
                    do {
                        for try await line in JSONLStreamReader.lines(from: stdout) {
                            for event in Self.events(fromCodexLine: line) {
                                continuation.yield(event)
                            }
                        }
                    } catch {
                        continuation.yield(.failed(error.localizedDescription))
                    }
                }

                let stderrTask = Task {
                    do {
                        for try await line in JSONLStreamReader.lines(from: stderr) {
                            continuation.yield(.appendMessage(kind: .commandOutput, title: "stderr", subtitle: "Codex", text: line, status: "stream", requestID: nil))
                        }
                    } catch {
                        continuation.yield(.failed(error.localizedDescription))
                    }
                }

                process.waitUntilExit()
                _ = await stdoutTask.result
                _ = await stderrTask.result

                if process.terminationStatus == 0 {
                    continuation.yield(.finished)
                } else if process.terminationReason == .uncaughtSignal {
                    continuation.yield(.failed("Codex 已停止。"))
                } else {
                    continuation.yield(.failed("Codex app-server 退出码：\(process.terminationStatus)"))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                self.interrupt()
            }
        }
    }

    func interrupt() {
        send(method: "turn/interrupt", params: [:])
        guard let process, process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { [weak process] in
            guard let process, process.isRunning else { return }
            process.interrupt()
        }
    }

    func respondToPermission(requestID: String, allowed: Bool) {
        send(method: "approval/respond", params: ["id": requestID, "approved": allowed])
    }

    private func send(method: String, params: [String: Any]) {
        guard let inputPipe else { return }
        let object: [String: Any] = ["id": nextID, "method": method, "params": params]
        nextID += 1
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        inputPipe.fileHandleForWriting.write(data)
        inputPipe.fileHandleForWriting.write(Data("\n".utf8))
    }

    private static func events(fromCodexLine line: String) -> [ChatBackendEvent] {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [.appendMessage(kind: .rawOutput, title: "raw", subtitle: "Codex", text: line, status: "stream", requestID: nil)]
        }

        let method = object["method"] as? String ?? object["type"] as? String ?? "response"
        if method.contains("agentMessage/delta"), let params = object["params"] as? [String: Any] {
            return [.appendDelta(kind: .assistant, text: stringValue(params["delta"]) ?? stringValue(params["text"]) ?? "")]
        }
        if method.contains("approval") || method.contains("permission") {
            let params = object["params"] as? [String: Any] ?? object
            let id = stringValue(params["id"]) ?? stringValue(params["requestId"]) ?? UUID().uuidString
            return [.permissionRequest(id: id, title: method, text: compactText(from: params))]
        }
        if method.contains("completed") || method.contains("turn/completed") {
            return [.finished]
        }
        if method.contains("failed") || method.contains("error") {
            return [.failed(compactText(from: object))]
        }
        if method.contains("tool") || method.contains("command") || method.contains("exec") {
            return [.appendMessage(kind: .toolCall, title: method, subtitle: "Codex", text: compactText(from: object), status: "done", requestID: nil)]
        }
        if let result = object["result"] as? [String: Any], let threadID = stringValue(result["threadId"]) ?? stringValue(result["id"]) {
            return [.sessionID(threadID)]
        }
        return [.appendMessage(kind: .rawOutput, title: method, subtitle: "Codex", text: compactText(from: object), status: "stream", requestID: nil)]
    }

    private static func compactText(from object: [String: Any]) -> String {
        if let text = stringValue(object["text"]) ?? stringValue(object["message"]) ?? stringValue(object["delta"]) {
            return text
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}
