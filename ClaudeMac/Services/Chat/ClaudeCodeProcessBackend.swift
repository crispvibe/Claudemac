import Foundation

final class ClaudeCodeProcessBackend: ChatProcessBackend {
    private struct ProcessRunResult {
        let terminationStatus: Int32
        let terminationReason: Process.TerminationReason
        let didReceiveVisibleOutput: Bool
        let didReceiveStderr: Bool

        var shouldRetryWithoutEffort: Bool {
            terminationStatus != 0 && didReceiveVisibleOutput == false
        }
    }

    private var process: Process?
    private var inputPipe: Pipe?

    func start(prompt: String, options: ChatRunOptions, session: ChatSessionRecord?) -> AsyncThrowingStream<ChatBackendEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }

                guard let firstRun = await self.runProcess(
                    prompt: prompt,
                    options: options,
                    session: session,
                    includeEffort: true,
                    continuation: continuation
                ) else {
                    continuation.finish()
                    return
                }

                let finalRun: ProcessRunResult
                if firstRun.shouldRetryWithoutEffort {
                    continuation.yield(.appendMessage(
                        kind: .system,
                        title: "Claude Code",
                        subtitle: "fallback",
                        text: "当前 Claude Code 没有接受 --effort，本次已自动改用默认思考强度重试。",
                        status: "retry",
                        requestID: nil
                    ))
                    guard let fallbackRun = await self.runProcess(
                        prompt: prompt,
                        options: options,
                        session: session,
                        includeEffort: false,
                        continuation: continuation
                    ) else {
                        continuation.finish()
                        return
                    }
                    finalRun = fallbackRun
                } else {
                    finalRun = firstRun
                }

                self.finish(finalRun, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                self.interrupt()
            }
        }
    }

    private func runProcess(
        prompt: String,
        options: ChatRunOptions,
        session: ChatSessionRecord?,
        includeEffort: Bool,
        continuation: AsyncThrowingStream<ChatBackendEvent, Error>.Continuation
    ) async -> ProcessRunResult? {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.executableURL = URL(fileURLWithPath: options.executablePath)
        process.arguments = arguments(prompt: prompt, options: options, session: session, includeEffort: includeEffort)
        process.currentDirectoryURL = URL(fileURLWithPath: options.projectPath, isDirectory: true)
        process.environment = ChatCLIEnvironment.processEnvironment
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin
        self.process = process
        inputPipe = stdin

        do {
            continuation.yield(.appendMessage(
                kind: .command,
                title: "claude",
                subtitle: options.projectPath,
                text: displayCommand(executablePath: options.executablePath, arguments: process.arguments ?? []),
                status: "start",
                requestID: nil
            ))
            try process.run()
        } catch {
            continuation.yield(.failed(ChatProcessError.launchFailed(error.localizedDescription).localizedDescription))
            return nil
        }

        let stdoutTask = Task { () -> Bool in
            var didReceiveVisibleOutput = false
            do {
                for try await line in JSONLStreamReader.lines(from: stdout) {
                    let events = Self.events(fromClaudeLine: line)
                    if events.contains(where: Self.isVisibleOutput) {
                        didReceiveVisibleOutput = true
                    }
                    for event in events {
                        continuation.yield(event)
                    }
                }
            } catch {
                continuation.yield(.failed(error.localizedDescription))
            }
            return didReceiveVisibleOutput
        }

        let stderrTask = Task { () -> Bool in
            var didReceiveStderr = false
            do {
                for try await line in JSONLStreamReader.lines(from: stderr) {
                    didReceiveStderr = true
                    continuation.yield(.appendMessage(kind: .commandOutput, title: "stderr", subtitle: "Claude Code", text: line, status: "stream", requestID: nil))
                }
            } catch {
                continuation.yield(.failed(error.localizedDescription))
            }
            return didReceiveStderr
        }

        process.waitUntilExit()
        let didReceiveVisibleOutput = await stdoutTask.value
        let didReceiveStderr = await stderrTask.value
        inputPipe?.fileHandleForWriting.closeFile()
        inputPipe = nil
        self.process = nil

        return ProcessRunResult(
            terminationStatus: process.terminationStatus,
            terminationReason: process.terminationReason,
            didReceiveVisibleOutput: didReceiveVisibleOutput,
            didReceiveStderr: didReceiveStderr
        )
    }

    private func finish(
        _ result: ProcessRunResult,
        continuation: AsyncThrowingStream<ChatBackendEvent, Error>.Continuation
    ) {
        if result.terminationStatus == 0 {
            if result.didReceiveVisibleOutput || result.didReceiveStderr {
                continuation.yield(.finished)
            } else {
                continuation.yield(.failed("Claude Code 没有输出任何对话内容。请检查 CLAUDE_CONFIG_DIR、认证配置或模型设置。"))
            }
        } else if result.terminationReason == .uncaughtSignal {
            continuation.yield(.failed("Claude Code 已停止。"))
        } else {
            continuation.yield(.failed("Claude Code 退出码：\(result.terminationStatus)"))
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

    func respondToPermission(requestID: String, decision: ChatPermissionDecision) {
        var response: [String: Any] = ["allowed": decision.isAllowed]
        if decision == .allowForSession {
            response["scope"] = "session"
        }
        let object: [String: Any] = [
            "type": "control_response",
            "request_id": requestID,
            "response": response
        ]
        ChatPipeWriter.writeJSONObject(object, to: inputPipe)
    }

    func sendCompact() {
        let object: [String: Any] = [
            "type": "command",
            "command": "/compact"
        ]
        ChatPipeWriter.writeJSONObject(object, to: inputPipe)
    }

    private func displayCommand(executablePath: String, arguments: [String]) -> String {
        var displayArguments = arguments
        if let promptFlagIndex = displayArguments.firstIndex(of: "-p"), displayArguments.indices.contains(promptFlagIndex + 1) {
            displayArguments[promptFlagIndex + 1] = "<prompt>"
        }
        return ([executablePath] + displayArguments).joined(separator: " ")
    }

    private func arguments(prompt: String, options: ChatRunOptions, session: ChatSessionRecord?, includeEffort: Bool) -> [String] {
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
        if includeEffort {
            args.append(contentsOf: ["--effort", options.reasoningEffort.claudeArgument])
        }
        let executionModelID = ChatModelCatalog.executionModelID(for: options.modelID)
        if executionModelID != ChatModelCatalog.defaultClaudeModelID {
            args.append(contentsOf: ["--model", executionModelID])
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

        // Extract token usage from any event that carries it
        if let usageEvent = extractTokenUsage(from: object) {
            events.append(usageEvent)
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

    private static func isVisibleOutput(_ event: ChatBackendEvent) -> Bool {
        switch event {
        case .appendDelta, .permissionRequest, .failed:
            true
        case .appendMessage(let kind, _, _, let text, _, _):
            kind != .system && !text.isEmpty
        case .sessionID, .updateStreamingStatus, .finished, .tokenUsage:
            false
        }
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

    private static func extractTokenUsage(from object: [String: Any]) -> ChatBackendEvent? {
        // Try top-level "usage" field
        if let usage = object["usage"] as? [String: Any] {
            let inputTokens = usage["input_tokens"] as? Int ?? 0
            let outputTokens = usage["output_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? usage["cache_creation_input_tokens"] as? Int ?? 0
            let used = inputTokens + outputTokens + cacheRead
            let total = usage["context_window"] as? Int ?? usage["max_tokens"] as? Int ?? 0
            if used > 0 || total > 0 {
                return .tokenUsage(used: used, total: total)
            }
        }
        // Try nested "message.usage"
        if let message = object["message"] as? [String: Any], let usage = message["usage"] as? [String: Any] {
            let inputTokens = usage["input_tokens"] as? Int ?? 0
            let outputTokens = usage["output_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? usage["cache_creation_input_tokens"] as? Int ?? 0
            let used = inputTokens + outputTokens + cacheRead
            let total = usage["context_window"] as? Int ?? usage["max_tokens"] as? Int ?? 0
            if used > 0 || total > 0 {
                return .tokenUsage(used: used, total: total)
            }
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}
