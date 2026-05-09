import Foundation

final class ClaudeCodeProcessBackend: ChatProcessBackend {
    private struct ProcessRunResult {
        let terminationStatus: Int32
        let terminationReason: Process.TerminationReason
        let didReceiveVisibleOutput: Bool
        let stderrOutput: String

        var shouldRetryWithoutEffort: Bool {
            guard terminationStatus != 0, didReceiveVisibleOutput == false else { return false }
            let lowercasedStderr = stderrOutput.lowercased()
            return lowercasedStderr.contains("--effort")
                || lowercasedStderr.contains("unknown option 'effort'")
                || lowercasedStderr.contains("unknown option: effort")
                || lowercasedStderr.contains("unexpected argument '--effort'")
        }

        var shouldRetryWithoutPartialMessages: Bool {
            guard terminationStatus != 0, didReceiveVisibleOutput == false else { return false }
            let lowercasedStderr = stderrOutput.lowercased()
            return lowercasedStderr.contains("--include-partial-messages")
                || lowercasedStderr.contains("unknown option 'include-partial-messages'")
                || lowercasedStderr.contains("unknown option: include-partial-messages")
                || lowercasedStderr.contains("unexpected argument '--include-partial-messages'")
        }
    }

    private struct ClaudeContentBlock {
        let id: String?
        let type: String
        let name: String?
    }

    private struct ClaudeStreamState {
        var didReceiveAssistantTextDelta = false
        var activeBlocks: [Int: ClaudeContentBlock] = [:]
    }

    private var process: Process?
    private var inputPipe: Pipe?

    func start(prompt: String, options: ChatRunOptions, session: ChatSessionRecord?) -> AsyncThrowingStream<ChatBackendEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }

                var includeEffort = true
                var includePartialMessages = true
                let finalRun: ProcessRunResult

                while true {
                    guard let run = await self.runProcess(
                        prompt: prompt,
                        options: options,
                        session: session,
                        includeEffort: includeEffort,
                        includePartialMessages: includePartialMessages,
                        continuation: continuation
                    ) else {
                        continuation.finish()
                        return
                    }

                    if includePartialMessages, run.shouldRetryWithoutPartialMessages {
                        includePartialMessages = false
                        continuation.yield(.appendMessage(
                            kind: .system,
                            title: "Claude Code",
                            subtitle: "fallback",
                            text: "当前 Claude Code 没有接受 --include-partial-messages，本次已自动改用普通 stream-json 重试。",
                            status: "retry",
                            requestID: nil
                        ))
                        continue
                    }

                    if includeEffort, run.shouldRetryWithoutEffort {
                        includeEffort = false
                        continuation.yield(.appendMessage(
                            kind: .system,
                            title: "Claude Code",
                            subtitle: "fallback",
                            text: "当前 Claude Code 没有接受 --effort，本次已自动改用默认思考强度重试。",
                            status: "retry",
                            requestID: nil
                        ))
                        continue
                    }

                    finalRun = run
                    break
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
        includePartialMessages: Bool,
        continuation: AsyncThrowingStream<ChatBackendEvent, Error>.Continuation
    ) async -> ProcessRunResult? {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: options.executablePath)
        process.arguments = arguments(prompt: prompt, options: options, session: session, includeEffort: includeEffort, includePartialMessages: includePartialMessages)
        process.currentDirectoryURL = URL(fileURLWithPath: options.projectPath, isDirectory: true)
        process.environment = ChatCLIEnvironment.processEnvironment
        process.standardOutput = stdout
        process.standardError = stderr
        self.process = process
        inputPipe = nil

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
            var streamState = ClaudeStreamState()
            do {
                for try await line in JSONLStreamReader.lines(from: stdout) {
                    let events = Self.events(fromClaudeLine: line, streamState: &streamState)
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

        let stderrTask = Task { () -> String in
            var stderrLines: [String] = []
            do {
                for try await line in JSONLStreamReader.lines(from: stderr) {
                    stderrLines.append(line)
                    continuation.yield(.appendMessage(kind: .commandOutput, title: "stderr", subtitle: "Claude Code", text: line, status: "stream", requestID: nil))
                }
            } catch {
                continuation.yield(.failed(error.localizedDescription))
            }
            return stderrLines.joined(separator: "\n")
        }

        process.waitUntilExit()
        let didReceiveVisibleOutput = await stdoutTask.value
        let stderrOutput = await stderrTask.value
        inputPipe = nil
        self.process = nil

        return ProcessRunResult(
            terminationStatus: process.terminationStatus,
            terminationReason: process.terminationReason,
            didReceiveVisibleOutput: didReceiveVisibleOutput,
            stderrOutput: stderrOutput
        )
    }

    private func finish(
        _ result: ProcessRunResult,
        continuation: AsyncThrowingStream<ChatBackendEvent, Error>.Continuation
    ) {
        if result.terminationStatus == 0 {
            if result.didReceiveVisibleOutput || !result.stderrOutput.isEmpty {
                continuation.yield(.finished)
            } else {
                continuation.yield(.failed("Claude Code 没有输出任何对话内容。请检查认证配置或模型设置。"))
            }
        } else if result.terminationReason == .uncaughtSignal {
            continuation.yield(.failed("Claude Code 已停止。"))
        } else {
            let stderr = result.stderrOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = stderr.isEmpty
                ? "Claude Code 退出码：\(result.terminationStatus)"
                : "Claude Code 退出码：\(result.terminationStatus)\n\(stderr)"
            continuation.yield(.failed(message))
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

    func respondToPermission(requestID: String, decision: ChatPermissionDecision) -> Bool {
        var response: [String: Any] = ["allowed": decision.isAllowed]
        if decision == .allowForSession {
            response["scope"] = "session"
        }
        let object: [String: Any] = [
            "type": "control_response",
            "request_id": requestID,
            "response": response
        ]
        return ChatPipeWriter.writeJSONObject(object, to: inputPipe)
    }

    func sendCompact() -> Bool {
        false
    }

    private func displayCommand(executablePath: String, arguments: [String]) -> String {
        var displayArguments = arguments
        if let promptFlagIndex = displayArguments.firstIndex(of: "-p"), displayArguments.indices.contains(promptFlagIndex + 1) {
            displayArguments[promptFlagIndex + 1] = "<prompt>"
        }
        return ([executablePath] + displayArguments).joined(separator: " ")
    }

    private func arguments(prompt: String, options: ChatRunOptions, session: ChatSessionRecord?, includeEffort: Bool, includePartialMessages: Bool) -> [String] {
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
        if includePartialMessages {
            args.append("--include-partial-messages")
        }
        args.append(contentsOf: ["--permission-mode", options.permissionMode.claudePermissionMode])
        if includeEffort {
            args.append(contentsOf: ["--effort", options.reasoningEffort.claudeArgument])
        }
        let executionModelID = ChatModelCatalog.executionModelID(for: options.modelID)
        if isClaudeModelArgument(executionModelID) {
            args.append(contentsOf: ["--model", executionModelID])
        }
        return args
    }

    private func isClaudeModelArgument(_ modelID: String) -> Bool {
        let normalized = modelID.lowercased()
        return normalized != ChatModelCatalog.defaultClaudeModelID
            && normalized.hasPrefix("claude-")
    }

    private static func events(fromClaudeLine line: String, streamState: inout ClaudeStreamState) -> [ChatBackendEvent] {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [.appendMessage(kind: .rawOutput, title: "raw", subtitle: "Claude Code", text: line, status: "stream", requestID: nil)]
        }

        var events: [ChatBackendEvent] = []
        if let sessionID = object["session_id"] as? String ?? object["sessionId"] as? String {
            events.append(.sessionID(sessionID))
        }

        if let usageEvent = extractTokenUsage(from: object) {
            events.append(usageEvent)
        }

        let type = object["type"] as? String ?? object["event"] as? String ?? "raw"
        if type == "system" {
            if let subtype = object["subtype"] as? String, subtype == "init" {
                events.append(.appendMessage(kind: .rawOutput, title: "Claude init", subtitle: "tools", text: initSummary(from: object), status: "done", requestID: nil))
            } else if let subtype = object["subtype"] as? String {
                events.append(.appendMessage(kind: .system, title: "system", subtitle: subtype, text: compactText(from: object), status: "done", requestID: nil))
            }
            return events
        }

        if type == "stream_event" {
            events.append(contentsOf: streamEvents(from: object, streamState: &streamState))
            return events
        }

        if type == "assistant" {
            if !streamState.didReceiveAssistantTextDelta {
                events.append(contentsOf: assistantEvents(from: object))
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
            let kind: ChatMessageKind = type.contains("result") ? .toolResult : .toolCall
            events.append(.appendMessage(kind: kind, title: type, subtitle: stringValue(object["name"]) ?? "", text: compactText(from: object), status: "done", requestID: stringValue(object["id"])))
            return events
        }

        events.append(.appendMessage(kind: .rawOutput, title: type, subtitle: "Claude Code", text: compactText(from: object), status: "stream", requestID: nil))
        return events
    }

    private static func streamEvents(from object: [String: Any], streamState: inout ClaudeStreamState) -> [ChatBackendEvent] {
        guard let event = object["event"] as? [String: Any] else {
            return [.appendMessage(kind: .rawOutput, title: "stream_event", subtitle: "Claude Code", text: compactText(from: object), status: "stream", requestID: nil)]
        }
        let type = stringValue(event["type"]) ?? "stream_event"
        let blockIndex = intValue(event["index"])
        let activeBlock = blockIndex.flatMap { streamState.activeBlocks[$0] }

        if let usageEvent = extractTokenUsage(from: event) {
            return [usageEvent]
        }

        if type == "content_block_start", let contentBlock = event["content_block"] as? [String: Any] {
            let blockType = stringValue(contentBlock["type"]) ?? "content_block"
            let block = ClaudeContentBlock(
                id: stringValue(contentBlock["id"]),
                type: blockType,
                name: stringValue(contentBlock["name"])
            )
            if let blockIndex {
                streamState.activeBlocks[blockIndex] = block
            }
            guard blockType != "text" && blockType != "thinking" else { return [] }
            let kind = kindForClaudeBlockType(blockType)
            return [.appendMessage(
                kind: kind,
                title: blockType,
                subtitle: block.name ?? "",
                text: compactText(from: contentBlock),
                status: "streaming",
                requestID: block.id
            )]
        }

        if type == "content_block_delta", let delta = event["delta"] as? [String: Any] {
            let deltaType = stringValue(delta["type"]) ?? ""
            if deltaType == "text_delta", let text = stringValue(delta["text"]), !text.isEmpty {
                let kind = kindForClaudeDelta(block: activeBlock, defaultKind: .assistant)
                if kind == .assistant {
                    streamState.didReceiveAssistantTextDelta = true
                }
                return [.appendDelta(kind: kind, title: activeBlock?.type ?? "", subtitle: activeBlock?.name ?? "Claude Code", text: text, status: "streaming", requestID: activeBlock?.id)]
            }
            if deltaType == "thinking_delta", let text = stringValue(delta["thinking"]) ?? stringValue(delta["text"]), !text.isEmpty {
                return [.appendDelta(kind: .reasoning, title: "thinking", subtitle: "Claude Code", text: text, status: "streaming", requestID: activeBlock?.id)]
            }
            if deltaType == "input_json_delta", let text = stringValue(delta["partial_json"]), !text.isEmpty {
                return [.appendDelta(kind: .toolCall, title: activeBlock?.type ?? "tool_use", subtitle: activeBlock?.name ?? "", text: text, status: "streaming", requestID: activeBlock?.id)]
            }
            return [.appendMessage(kind: .rawOutput, title: deltaType.isEmpty ? "content_block_delta" : deltaType, subtitle: "Claude Code", text: compactText(from: delta), status: "stream", requestID: activeBlock?.id)]
        }

        if type == "content_block_stop" {
            if let blockIndex {
                streamState.activeBlocks.removeValue(forKey: blockIndex)
            }
            return []
        }

        if type == "message_delta" || type == "message_stop" {
            return [.appendMessage(kind: .rawOutput, title: type, subtitle: "Claude Code", text: compactText(from: event), status: type == "message_stop" ? "done" : "stream", requestID: activeBlock?.id)]
        }

        return [.appendMessage(kind: .rawOutput, title: type, subtitle: "Claude Code", text: compactText(from: event), status: "stream", requestID: activeBlock?.id)]
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

    private static func assistantEvents(from object: [String: Any]) -> [ChatBackendEvent] {
        if let message = object["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] {
            return content.flatMap { contentItemEvents(from: $0) }
        }
        if let text = assistantText(from: object), !text.isEmpty {
            return [.appendDelta(kind: .assistant, title: "assistant", subtitle: "Claude Code", text: text, status: "streaming", requestID: nil)]
        }
        return []
    }

    private static func contentItemEvents(from item: [String: Any]) -> [ChatBackendEvent] {
        let type = stringValue(item["type"]) ?? "content"
        let id = stringValue(item["id"])
        switch type {
        case "text":
            guard let text = stringValue(item["text"]), !text.isEmpty else { return [] }
            return [.appendDelta(kind: .assistant, title: "assistant", subtitle: "Claude Code", text: text, status: "streaming", requestID: nil)]
        case "thinking":
            guard let text = stringValue(item["thinking"]) ?? stringValue(item["text"]), !text.isEmpty else { return [] }
            return [.appendDelta(kind: .reasoning, title: "thinking", subtitle: "Claude Code", text: text, status: "streaming", requestID: id)]
        case "tool_result":
            return [.appendMessage(kind: .toolResult, title: type, subtitle: stringValue(item["name"]) ?? "", text: compactText(from: item), status: "done", requestID: id)]
        case "tool_use":
            return [.appendMessage(kind: .toolCall, title: type, subtitle: stringValue(item["name"]) ?? "", text: compactText(from: item), status: "done", requestID: id)]
        default:
            return [.appendMessage(kind: .rawOutput, title: type, subtitle: "Claude Code", text: compactText(from: item), status: "done", requestID: id)]
        }
    }

    private static func kindForClaudeBlockType(_ blockType: String) -> ChatMessageKind {
        let lowercased = blockType.lowercased()
        if lowercased.contains("result") { return .toolResult }
        if lowercased.contains("diff") || lowercased.contains("edit") || lowercased.contains("patch") { return .diff }
        if lowercased.contains("command") || lowercased.contains("bash") { return .command }
        if lowercased.contains("tool") || lowercased.contains("mcp") || lowercased.contains("server") { return .toolCall }
        return .rawOutput
    }

    private static func kindForClaudeDelta(block: ClaudeContentBlock?, defaultKind: ChatMessageKind) -> ChatMessageKind {
        guard let block else { return defaultKind }
        let lowercased = block.type.lowercased()
        if lowercased == "text" { return .assistant }
        if lowercased.contains("result") { return .toolResult }
        if lowercased.contains("diff") || lowercased.contains("edit") || lowercased.contains("patch") { return .diff }
        if lowercased.contains("command") || lowercased.contains("bash") { return .commandOutput }
        if lowercased.contains("tool") || lowercased.contains("mcp") || lowercased.contains("server") { return .toolCall }
        return .rawOutput
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

    private static func initSummary(from object: [String: Any]) -> String {
        var lines: [String] = []
        if let model = stringValue(object["model"]) {
            lines.append("model: \(model)")
        }
        if let permissionMode = stringValue(object["permissionMode"]) {
            lines.append("permission: \(permissionMode)")
        }
        if let tools = object["tools"] as? [Any] {
            lines.append("tools: \(tools.count)")
            let names = tools.compactMap { stringValue($0) }.prefix(12)
            if !names.isEmpty { lines.append("tool names: \(names.joined(separator: ", "))") }
        }
        if let servers = object["mcp_servers"] as? [[String: Any]] {
            lines.append("mcp servers: \(servers.count)")
            let serverLines = servers.prefix(12).map { server in
                let name = stringValue(server["name"]) ?? "unknown"
                let status = stringValue(server["status"]) ?? "unknown"
                return "- \(name): \(status)"
            }
            lines.append(contentsOf: serverLines)
        }
        if let commands = object["slash_commands"] as? [Any] {
            lines.append("slash commands: \(commands.count)")
        }
        return lines.isEmpty ? compactText(from: object) : lines.joined(separator: "\n")
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

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}
