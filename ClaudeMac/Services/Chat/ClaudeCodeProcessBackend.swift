import Foundation

final class ClaudeCodeProcessBackend: ChatProcessBackend {
    private var process: Process?
    private var inputPipe: Pipe?

    func start(prompt: String, options: ChatRunOptions, session: ChatSessionRecord?) -> AsyncThrowingStream<ChatBackendEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()
                let stdin = Pipe()
                process.executableURL = URL(fileURLWithPath: options.executablePath)
                process.arguments = self.arguments(prompt: prompt, options: options, session: session)
                process.environment = ChatCLIEnvironment.processEnvironment
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = stdin
                self.process = process
                self.inputPipe = stdin

                do {
                    continuation.yield(.appendMessage(kind: .command, title: "claude", subtitle: options.projectPath, text: ([options.executablePath] + (process.arguments ?? [])).joined(separator: " "), status: "start", requestID: nil))
                    try process.run()
                } catch {
                    continuation.yield(.failed(ChatProcessError.launchFailed(error.localizedDescription).localizedDescription))
                    continuation.finish()
                    return
                }

                let stdoutTask = Task {
                    do {
                        for try await line in JSONLStreamReader.lines(from: stdout) {
                            for event in Self.events(fromClaudeLine: line) {
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
                            continuation.yield(.appendMessage(kind: .commandOutput, title: "stderr", subtitle: "Claude Code", text: line, status: "stream", requestID: nil))
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
                    continuation.yield(.failed("Claude Code 已停止。"))
                } else {
                    continuation.yield(.failed("Claude Code 退出码：\(process.terminationStatus)"))
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
        guard let process, process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { [weak process] in
            guard let process, process.isRunning else { return }
            process.interrupt()
        }
    }

    func respondToPermission(requestID: String, allowed: Bool) {
        let object: [String: Any] = [
            "type": "control_response",
            "request_id": requestID,
            "response": ["allowed": allowed]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object), let inputPipe else { return }
        inputPipe.fileHandleForWriting.write(data)
        inputPipe.fileHandleForWriting.write(Data("\n".utf8))
    }

    private func arguments(prompt: String, options: ChatRunOptions, session: ChatSessionRecord?) -> [String] {
        var args: [String] = []
        if options.sessionMode == .continueLast {
            args.append("--continue")
        } else if options.sessionMode == .resume, let resumeID = options.resumeSessionID?.nonEmptyTrimmed ?? session?.externalSessionID?.nonEmptyTrimmed {
            args.append(contentsOf: ["--resume", resumeID])
        } else if let externalSessionID = session?.externalSessionID?.nonEmptyTrimmed {
            args.append(contentsOf: ["--resume", externalSessionID])
        }
        args.append(contentsOf: ["-p", prompt])
        args.append(contentsOf: ["--output-format", "stream-json"])
        args.append("--verbose")
        args.append(contentsOf: ["--permission-mode", options.permissionMode.claudePermissionMode])
        if options.modelID != ChatModelCatalog.defaultClaudeModelID {
            args.append(contentsOf: ["--model", options.modelID])
        }
        return args
    }

    private static func events(fromClaudeLine line: String) -> [ChatBackendEvent] {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [.appendMessage(kind: .rawOutput, title: "raw", subtitle: "Claude Code", text: line, status: "stream", requestID: nil)]
        }

        var events: [ChatBackendEvent] = []
        if let sessionID = object["session_id"] as? String ?? object["sessionId"] as? String {
            events.append(.sessionID(sessionID))
        }

        let type = object["type"] as? String ?? object["event"] as? String ?? "raw"
        if type == "system" {
            if let subtype = object["subtype"] as? String, subtype != "init" {
                events.append(.appendMessage(kind: .system, title: "system", subtitle: subtype, text: compactText(from: object), status: "done", requestID: nil))
            }
            return events
        }

        if type == "assistant" {
            if let text = assistantText(from: object), !text.isEmpty {
                events.append(.appendDelta(kind: .assistant, text: text))
            }
            return events
        }

        if type == "result" {
            let resultText = stringValue(object["result"]) ?? stringValue(object["message"]) ?? compactText(from: object)
            events.append(.appendMessage(kind: .result, title: "result", subtitle: object["subtype"] as? String ?? "", text: resultText, status: "done", requestID: nil))
            return events
        }

        if type == "control_request" || type.contains("permission") || type.contains("approval") {
            let requestID = object["request_id"] as? String ?? object["id"] as? String ?? UUID().uuidString
            events.append(.permissionRequest(id: requestID, title: type, text: compactText(from: object)))
            return events
        }

        if type.contains("tool") {
            events.append(.appendMessage(kind: .toolCall, title: type, subtitle: stringValue(object["name"]) ?? "", text: compactText(from: object), status: "done", requestID: nil))
            return events
        }

        events.append(.appendMessage(kind: .rawOutput, title: type, subtitle: "Claude Code", text: compactText(from: object), status: "stream", requestID: nil))
        return events
    }

    private static func assistantText(from object: [String: Any]) -> String? {
        if let delta = object["delta"] as? [String: Any] {
            return stringValue(delta["text"]) ?? stringValue(delta["content"])
        }
        if let message = object["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] {
            return content.compactMap { item in
                if item["type"] as? String == "text" { return item["text"] as? String }
                return nil
            }.joined()
        }
        return stringValue(object["text"]) ?? stringValue(object["content"])
    }

    private static func compactText(from object: [String: Any]) -> String {
        if let text = stringValue(object["text"]) ?? stringValue(object["content"]) ?? stringValue(object["message"]) {
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
