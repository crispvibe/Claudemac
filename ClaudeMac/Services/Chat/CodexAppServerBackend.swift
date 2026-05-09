import Foundation

final class CodexAppServerBackend: ChatProcessBackend {
    private enum PendingRequest {
        case initialize
        case openThread
        case startTurn
        case interrupt
    }

    private struct ApprovalRequest {
        let id: Any
        let method: String
        let requestedPermissions: [String: Any]?
    }

    private var process: Process?
    private var inputPipe: Pipe?
    private var nextID = 1
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var pendingApprovals: [String: ApprovalRequest] = [:]
    private var activeThreadID: String?
    private var activeTurnID: String?
    private var didFinishTurn = false

    func start(prompt: String, options: ChatRunOptions, session: ChatSessionRecord?) -> AsyncThrowingStream<ChatBackendEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                self.didFinishTurn = false
                self.pendingRequests = [:]
                self.pendingApprovals = [:]
                self.activeThreadID = nil
                self.activeTurnID = nil

                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()
                let stdin = Pipe()
                let configOverride = "model_reasoning_effort=\"\(options.reasoningEffort.codexConfigValue)\""
                process.executableURL = URL(fileURLWithPath: options.executablePath)
                process.arguments = ["app-server", "-c", configOverride, "--listen", "stdio://"]
                process.currentDirectoryURL = URL(fileURLWithPath: options.projectPath, isDirectory: true)
                process.environment = ChatCLIEnvironment.processEnvironment
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = stdin
                self.process = process
                self.inputPipe = stdin

                do {
                    continuation.yield(.appendMessage(
                        kind: .command,
                        title: "codex",
                        subtitle: options.projectPath,
                        text: "\(options.executablePath) app-server -c \(configOverride) --listen stdio://",
                        status: "start",
                        requestID: nil
                    ))
                    try process.run()
                    self.bootstrapCodex()
                } catch {
                    continuation.yield(.failed(ChatProcessError.launchFailed(error.localizedDescription).localizedDescription))
                    continuation.finish()
                    return
                }

                let stdoutTask = Task { () -> Bool in
                    var didReceiveVisibleOutput = false
                    do {
                        for try await line in JSONLStreamReader.lines(from: stdout) {
                            let events = self.events(
                                fromCodexLine: line,
                                prompt: prompt,
                                options: options,
                                session: session
                            )
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
                            guard let event = Self.stderrEvent(from: line) else { continue }
                            continuation.yield(event)
                        }
                    } catch {
                        continuation.yield(.failed(error.localizedDescription))
                    }
                    return stderrLines.joined(separator: "\n")
                }

                process.waitUntilExit()
                let didReceiveVisibleOutput = await stdoutTask.value
                let stderrOutput = await stderrTask.value
                let didEmitStderrOutput = !stderrOutput.isEmpty

                self.inputPipe = nil
                self.process = nil

                if !self.didFinishTurn {
                    if process.terminationStatus == 0 {
                        if didReceiveVisibleOutput || didEmitStderrOutput {
                            continuation.yield(.finished)
                        } else {
                            continuation.yield(.failed("Codex app-server 没有输出任何对话内容。请检查 ~/.codex 权限、账号登录状态（codex login）或模型设置。"))
                        }
                    } else if process.terminationReason == .uncaughtSignal {
                        continuation.yield(.failed("Codex 已停止。"))
                    } else {
                        let stderr = stderrOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                        let message = stderr.isEmpty
                            ? "Codex app-server 退出码：\(process.terminationStatus)"
                            : "Codex app-server 退出码：\(process.terminationStatus)\n\(stderr)"
                        continuation.yield(.failed(message))
                    }
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
        if let threadID = activeThreadID, let turnID = activeTurnID {
            let id = sendRequest(method: "turn/interrupt", params: [
                "threadId": threadID,
                "turnId": turnID
            ])
            pendingRequests[id] = .interrupt
        }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { [weak process] in
            guard let process, process.isRunning else { return }
            process.interrupt()
        }
    }

    func respondToPermission(requestID: String, decision: ChatPermissionDecision) {
        guard let approval = pendingApprovals.removeValue(forKey: requestID) else { return }

        let result: [String: Any]
        switch approval.method {
        case "item/commandExecution/requestApproval":
            result = ["decision": codexApprovalDecision(from: decision)]
        case "item/fileChange/requestApproval":
            result = ["decision": codexApprovalDecision(from: decision)]
        case "item/permissions/requestApproval":
            result = [
                "permissions": decision.isAllowed ? (approval.requestedPermissions ?? [:]) : [:],
                "scope": decision == .allowForSession ? "session" : "turn"
            ]
        case "applyPatchApproval", "execCommandApproval":
            result = ["decision": decision.isAllowed ? "approved" : "denied"]
        default:
            result = ["decision": codexApprovalDecision(from: decision)]
        }

        sendResponse(id: approval.id, result: result)
    }

    func sendCompact() {
        _ = sendRequest(method: "compact", params: [:])
    }

    private func codexApprovalDecision(from decision: ChatPermissionDecision) -> String {
        switch decision {
        case .deny: "decline"
        case .allow: "accept"
        case .allowForSession: "acceptForSession"
        }
    }

    private func bootstrapCodex() {
        let id = sendRequest(method: "initialize", params: [
            "clientInfo": [
                "name": "Acode",
                "title": "Acode",
                "version": "1.0"
            ],
            "capabilities": [
                "experimentalApi": true
            ]
        ])
        pendingRequests[id] = .initialize
    }

    private func requestThread(prompt: String, options: ChatRunOptions, session: ChatSessionRecord?) {
        let resumeID = options.resumeSessionID?.nonEmptyTrimmed ?? session?.externalSessionID?.nonEmptyTrimmed
        var params: [String: Any] = [
            "cwd": options.projectPath,
            "model": options.modelID,
            "approvalPolicy": options.permissionMode.codexApprovalPolicy,
            "sandbox": options.permissionMode.codexSandbox,
            "serviceName": "Acode"
        ]

        let method: String
        if let resumeID, options.sessionMode == .resume || session?.externalSessionID?.nonEmptyTrimmed != nil {
            method = "thread/resume"
            params["threadId"] = resumeID
        } else {
            method = "thread/start"
        }

        let id = sendRequest(method: method, params: params)
        pendingRequests[id] = .openThread
    }

    private func requestTurnStart(threadID: String, prompt: String, options: ChatRunOptions) {
        let params: [String: Any] = [
            "threadId": threadID,
            "input": [[
                "type": "text",
                "text": prompt,
                "text_elements": []
            ]],
            "cwd": options.projectPath,
            "approvalPolicy": options.permissionMode.codexApprovalPolicy,
            "model": options.modelID
        ]
        let id = sendRequest(method: "turn/start", params: params)
        pendingRequests[id] = .startTurn
    }

    private func events(
        fromCodexLine line: String,
        prompt: String,
        options: ChatRunOptions,
        session: ChatSessionRecord?
    ) -> [ChatBackendEvent] {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [.appendMessage(kind: .rawOutput, title: "raw", subtitle: "Codex", text: line, status: "stream", requestID: nil)]
        }

        if let error = object["error"] as? [String: Any] {
            return events(fromError: error, envelope: object)
        }

        if let id = Self.intRequestID(from: object["id"]), let pending = pendingRequests.removeValue(forKey: id) {
            return events(fromResponse: object, pending: pending, prompt: prompt, options: options, session: session)
        }

        guard let method = object["method"] as? String else {
            return [.appendMessage(kind: .rawOutput, title: "response", subtitle: "Codex", text: Self.compactText(from: object), status: "stream", requestID: nil)]
        }

        if let id = object["id"], Self.isApprovalRequest(method) {
            return events(fromServerRequest: object, id: id, method: method)
        }

        return events(fromNotification: object, method: method)
    }

    private func events(fromError error: [String: Any], envelope: [String: Any]) -> [ChatBackendEvent] {
        let message = Self.codexErrorText(from: error)
        if Self.boolValue(envelope["willRetry"]) == true {
            return [
                .updateStreamingStatus(Self.stringValue(error["message"]) ?? "reconnecting"),
                .appendMessage(kind: .commandOutput, title: "codex", subtitle: "retrying", text: message, status: "retry", requestID: nil)
            ]
        }
        didFinishTurn = true
        process?.terminate()
        return [.failed(message)]
    }

    private func events(
        fromResponse object: [String: Any],
        pending: PendingRequest,
        prompt: String,
        options: ChatRunOptions,
        session: ChatSessionRecord?
    ) -> [ChatBackendEvent] {
        switch pending {
        case .initialize:
            sendNotification(method: "initialized")
            requestThread(prompt: prompt, options: options, session: session)
            return [.updateStreamingStatus("initialized")]
        case .openThread:
            guard let result = object["result"] as? [String: Any],
                  let threadID = Self.threadID(from: result) else {
                didFinishTurn = true
                process?.terminate()
                return [.failed("Codex thread/start 未返回 thread id。")]
            }
            activeThreadID = threadID
            requestTurnStart(threadID: threadID, prompt: prompt, options: options)
            return [
                .sessionID(threadID),
                .updateStreamingStatus("thread ready")
            ]
        case .startTurn:
            if let result = object["result"] as? [String: Any],
               let turnID = Self.turnID(from: result) {
                activeTurnID = turnID
            }
            return [.updateStreamingStatus("turn started")]
        case .interrupt:
            didFinishTurn = true
            return [.finished]
        }
    }

    private func events(fromServerRequest object: [String: Any], id: Any, method: String) -> [ChatBackendEvent] {
        let requestID = Self.requestKey(from: id)
        let params = object["params"] as? [String: Any] ?? [:]
        pendingApprovals[requestID] = ApprovalRequest(
            id: id,
            method: method,
            requestedPermissions: params["permissions"] as? [String: Any]
        )
        return [.permissionRequest(
            id: requestID,
            title: Self.title(forApprovalMethod: method),
            text: Self.approvalText(method: method, params: params)
        )]
    }

    private func events(fromNotification object: [String: Any], method: String) -> [ChatBackendEvent] {
        let params = object["params"] as? [String: Any] ?? [:]

        switch method {
        case "thread/started":
            if let threadID = Self.threadID(from: params) {
                activeThreadID = threadID
                return [.sessionID(threadID)]
            }
        case "turn/started":
            if let turnID = Self.turnID(from: params) {
                activeTurnID = turnID
            }
            return [.updateStreamingStatus("streaming")]
        case "item/agentMessage/delta":
            return [.appendDelta(kind: .assistant, text: Self.deltaText(from: params))]
        case "item/reasoning/textDelta", "item/reasoning/summaryTextDelta":
            return [.appendDelta(kind: .reasoning, text: Self.deltaText(from: params))]
        case "item/plan/delta":
            return [.appendMessage(kind: .reasoning, title: "plan", subtitle: "Codex", text: Self.compactText(from: params), status: "stream", requestID: nil)]
        case "command/exec/outputDelta", "item/commandExecution/outputDelta":
            return [.appendDelta(kind: .commandOutput, text: Self.deltaText(from: params))]
        case "item/fileChange/outputDelta", "turn/diff/updated":
            return [.appendDelta(kind: .diff, text: Self.deltaText(from: params))]
        case "item/started":
            return [.appendMessage(kind: .toolCall, title: "item started", subtitle: "Codex", text: Self.compactText(from: params), status: "start", requestID: nil)]
        case "item/completed":
            return [.appendMessage(kind: .toolResult, title: "item completed", subtitle: "Codex", text: Self.compactText(from: params), status: "done", requestID: nil)]
        case "turn/completed":
            didFinishTurn = true
            process?.terminate()
            if let turn = params["turn"] as? [String: Any],
               let error = turn["error"], !(error is NSNull) {
                return [.failed(Self.codexErrorText(from: error))]
            }
            return [.finished]
        case "error":
            return events(fromError: params, envelope: object)
        default:
            break
        }

        return [.appendMessage(kind: .rawOutput, title: method, subtitle: "Codex", text: Self.compactText(from: object), status: "stream", requestID: nil)]
    }

    @discardableResult
    private func sendRequest(method: String, params: Any) -> Int {
        let id = nextID
        nextID += 1
        writeJSONObject(["id": id, "method": method, "params": params])
        return id
    }

    private func sendNotification(method: String, params: Any? = nil) {
        var object: [String: Any] = ["method": method]
        if let params {
            object["params"] = params
        }
        writeJSONObject(object)
    }

    private func sendResponse(id: Any, result: [String: Any]) {
        writeJSONObject(["id": id, "result": result])
    }

    private func writeJSONObject(_ object: [String: Any]) {
        ChatPipeWriter.writeJSONObject(object, to: inputPipe)
    }

    private static func isApprovalRequest(_ method: String) -> Bool {
        method == "item/commandExecution/requestApproval"
            || method == "item/fileChange/requestApproval"
            || method == "item/permissions/requestApproval"
            || method == "applyPatchApproval"
            || method == "execCommandApproval"
    }

    private static func title(forApprovalMethod method: String) -> String {
        switch method {
        case "item/commandExecution/requestApproval", "execCommandApproval": "命令执行权限"
        case "item/fileChange/requestApproval", "applyPatchApproval": "文件修改权限"
        case "item/permissions/requestApproval": "额外权限请求"
        default: method
        }
    }

    private static func stderrEvent(from line: String) -> ChatBackendEvent? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("could not update PATH") || text.contains("WARNING: proceeding") {
            return nil
        }
        if let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let fields = object["fields"] as? [String: Any] {
            let level = stringValue(object["level"]) ?? ""
            let message = stringValue(fields["message"]) ?? compactText(from: fields)
            guard level == "ERROR" else { return nil }
            let lowercased = message.lowercased()
            guard lowercased.contains("permission")
                || lowercased.contains("operation not permitted")
                || lowercased.contains("failed to create session")
                || lowercased.contains("readonly database")
            else {
                return nil
            }
            return .appendMessage(kind: .commandOutput, title: "stderr", subtitle: "Codex", text: message, status: "stream", requestID: nil)
        }
        return .appendMessage(kind: .commandOutput, title: "stderr", subtitle: "Codex", text: text, status: "stream", requestID: nil)
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

    private static func approvalText(method: String, params: [String: Any]) -> String {
        if method == "item/commandExecution/requestApproval" {
            let command = stringValue(params["command"]) ?? "未知命令"
            let cwd = stringValue(params["cwd"]) ?? ""
            let reason = stringValue(params["reason"]) ?? ""
            return [command, cwd.isEmpty ? nil : "cwd: \(cwd)", reason.isEmpty ? nil : reason]
                .compactMap { $0 }
                .joined(separator: "\n")
        }
        if method == "item/fileChange/requestApproval" {
            let root = stringValue(params["grantRoot"]) ?? ""
            let reason = stringValue(params["reason"]) ?? ""
            return [root.isEmpty ? "文件修改" : "root: \(root)", reason.isEmpty ? nil : reason]
                .compactMap { $0 }
                .joined(separator: "\n")
        }
        return compactText(from: params)
    }

    private static func threadID(from object: [String: Any]) -> String? {
        if let value = stringValue(object["threadId"]) ?? stringValue(object["thread_id"]) {
            return value
        }
        if let thread = object["thread"] as? [String: Any] {
            return stringValue(thread["id"]) ?? stringValue(thread["threadId"])
        }
        return nil
    }

    private static func turnID(from object: [String: Any]) -> String? {
        if let value = stringValue(object["turnId"]) ?? stringValue(object["turn_id"]) {
            return value
        }
        if let turn = object["turn"] as? [String: Any] {
            return stringValue(turn["id"]) ?? stringValue(turn["turnId"])
        }
        return nil
    }

    private static func intRequestID(from value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func requestKey(from value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return "\(value)"
    }

    private static func deltaText(from object: [String: Any]) -> String {
        stringValue(object["delta"])
            ?? stringValue(object["text"])
            ?? stringValue(object["content"])
            ?? compactText(from: object)
    }

    private static func compactText(from object: [String: Any]) -> String {
        if let text = stringValue(object["text"]) ?? stringValue(object["message"]) ?? stringValue(object["delta"]) {
            return text
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    private static func codexErrorText(from error: Any) -> String {
        if let text = stringValue(error)?.nonEmptyTrimmed {
            return friendlyCodexErrorText(raw: text, info: nil)
        }
        guard let object = error as? [String: Any] else { return "Codex 运行失败。" }

        let message = stringValue(object["message"])
        let additionalDetails = stringValue(object["additionalDetails"])
        let errorInfo = stringValue(object["codexErrorInfo"])

        if let friendly = friendlyCodexErrorText(raw: [message, additionalDetails].compactMap { $0 }.joined(separator: "\n"), info: errorInfo).nonEmptyTrimmed {
            return friendly
        }

        let parts = [
            message,
            additionalDetails
        ]
        .compactMap { $0?.nonEmptyTrimmed }

        if !parts.isEmpty {
            return parts.reduce(into: [String]()) { result, item in
                if !result.contains(item) { result.append(item) }
            }.joined(separator: "\n")
        }
        return compactText(from: object)
    }

    private static func friendlyCodexErrorText(raw: String, info: String?) -> String {
        let lowercased = ([raw, info].compactMap { $0 }.joined(separator: "\n")).lowercased()

        if lowercased.contains("unauthorized")
            || lowercased.contains("access token could not be refreshed")
            || lowercased.contains("please sign in again") {
            return """
            Codex 账号登录态已失效。

            Codex 无法刷新 OAuth access token，通常是你在别处退出登录、切换账号，或 ~/.codex/auth.json 里的登录态已经过期。

            处理方式：
            1. 在终端运行 codex login 重新登录。
            2. 如果你使用 cc-switch 管理账号，到设置页重新“从 cc-switch 导入登录态”。
            3. 回到这里新开一个 Codex 会话再试。
            """
        }

        if lowercased.contains("nodename nor servname provided")
            || lowercased.contains("failed to lookup address information")
            || lowercased.contains("timeout waiting for child process") {
            return """
            Codex 网络连接失败。

            这通常是代理没有生效、代理不可达，或当前账号服务地址无法解析。请确认设置页的 HTTP_PROXY / HTTPS_PROXY 已保存，并新开 Codex 会话重试。
            """
        }

        return raw
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
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
