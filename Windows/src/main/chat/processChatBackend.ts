import { randomUUID } from "node:crypto";
import { execFile, spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import type {
  ChatBackendEvent,
  ChatInteractiveResponse,
  ChatMessageAttachment,
  ChatMessageKind,
  ChatPermissionDecision,
  ChatRunOptions,
  ChatStartRequest
} from "../../shared/chat.js";
import { readJSONLLines } from "./jsonlReader.js";

type JSONRecord = Record<string, unknown>;
type EmitChatEvent = (event: ChatBackendEvent) => void;
type PendingCodexRequest = "initialize" | "openThread" | "startTurn" | "interrupt" | "compact";

interface PendingApproval {
  id: unknown;
  method: string;
  requestedPermissions: JSONRecord | null;
}

interface PendingInteractive {
  id: unknown;
  method: string;
}

interface ProcessResult {
  code: number | null;
  signal: NodeJS.Signals | null;
}

export class ChatProcessRun {
  private child: ChildProcessWithoutNullStreams | null = null;
  private didEmitTerminalEvent = false;
  private didReceiveVisibleOutput = false;
  private didReceiveStderr = false;
  private didInterrupt = false;
  private nextCodexID = 1;
  private pendingCodexRequests = new Map<string, PendingCodexRequest>();
  private pendingApprovals = new Map<string, PendingApproval>();
  private pendingInteractiveRequests = new Map<string, PendingInteractive>();
  private activeThreadID: string | null = null;
  private activeTurnID: string | null = null;

  constructor(
    private readonly request: ChatStartRequest,
    private readonly emit: EmitChatEvent
  ) {}

  get runID(): string {
    return this.request.runID;
  }

  async start(): Promise<void> {
    this.emit({ type: "updateStreamingStatus", status: `启动 ${this.request.options.cli}` });
    try {
      if (this.request.options.cli === "codex") {
        await this.startCodex();
      } else {
        await this.startClaude();
      }
    } catch (error) {
      this.emitTerminal({
        type: "failed",
        message: error instanceof Error ? error.message : String(error)
      });
    } finally {
      this.closeStdin();
      this.child = null;
      this.pendingCodexRequests.clear();
      this.pendingApprovals.clear();
      this.pendingInteractiveRequests.clear();
    }
  }

  interrupt(): void {
    if (this.didEmitTerminalEvent) {
      return;
    }
    this.didInterrupt = true;
    if (this.request.options.cli === "codex" && this.activeThreadID && this.activeTurnID) {
      const id = this.sendCodexRequest("turn/interrupt", {
        threadId: this.activeThreadID,
        turnId: this.activeTurnID
      });
      this.pendingCodexRequests.set(String(id), "interrupt");
    }
    this.emitTerminal({ type: "failed", message: `${this.request.options.cli} 已停止。` });
    this.stopProcess();
  }

  respondToPermission(requestID: string, decision: ChatPermissionDecision): boolean {
    if (this.request.options.cli === "codex") {
      const approval = this.pendingApprovals.get(requestID);
      if (!approval) {
        return false;
      }
      this.pendingApprovals.delete(requestID);
      return this.sendCodexResponse(approval.id, this.codexApprovalResult(approval, decision));
    }

    const response: JSONRecord = { allowed: decision !== "deny" };
    if (decision === "allowForSession") {
      response.scope = "session";
    }
    return this.writeJSONObject({
      type: "control_response",
      request_id: requestID,
      response
    });
  }

  respondToInteractiveRequest(response: ChatInteractiveResponse): boolean {
    if (this.request.options.cli === "codex") {
      const pending = this.pendingInteractiveRequests.get(response.requestID);
      if (!pending) {
        return false;
      }
      this.pendingInteractiveRequests.delete(response.requestID);
      const answer = response.customText?.trim() || response.selectedOptionIDs.join(", ");
      return this.sendCodexResponse(pending.id, {
        selectedOptionIds: response.selectedOptionIDs,
        selected_option_ids: response.selectedOptionIDs,
        answer,
        text: answer,
        value: answer,
        method: pending.method
      });
    }

    const answer = response.customText?.trim() || response.selectedOptionIDs.join(", ");
    if (!answer.trim()) {
      return false;
    }
    return this.writeClaudeUserMessage(answer, response.requestID, {
      selectedOptionIds: response.selectedOptionIDs,
      selected_option_ids: response.selectedOptionIDs,
      answer,
      text: answer,
      value: answer
    });
  }

  sendCompact(): boolean {
    if (this.request.options.cli !== "codex") {
      return false;
    }
    const id = this.sendCodexRequest("compact", {});
    this.pendingCodexRequests.set(String(id), "compact");
    return true;
  }

  private async startClaude(): Promise<void> {
    const options = this.request.options;
    const child = this.spawnCLI("claude", this.claudeArguments(options, this.request.session));
    this.child = child;

    if (options.supportsStreamJSONInput) {
      const didWrite = this.writeClaudeUserMessage(this.request.prompt, null, null, this.request.attachments);
      if (!didWrite) {
        this.emitTerminal({ type: "failed", message: "Claude Code stream-json 输入写入失败。" });
        this.stopProcess();
      }
    }

    await this.consumeChildStreams(child, (line) => {
      for (const event of this.eventsFromClaudeLine(line)) {
        this.emitAndMark(event);
      }
      if (line.includes("\"type\":\"result\"")) {
        this.closeStdin();
      }
    }, "Claude Code");
  }

  private async startCodex(): Promise<void> {
    const effort = this.request.options.reasoningEffort === "max" ? "xhigh" : this.request.options.reasoningEffort;
    const child = this.spawnCLI("codex", ["app-server", "-c", `model_reasoning_effort="${effort}"`, "--listen", "stdio://"]);
    this.child = child;
    const initializeID = this.sendCodexRequest("initialize", {
      clientInfo: {
        name: "Acode",
        title: "Acode",
        version: "0.1.0"
      },
      capabilities: {
        experimentalApi: true
      }
    });
    this.pendingCodexRequests.set(String(initializeID), "initialize");

    await this.consumeChildStreams(child, (line) => {
      for (const event of this.eventsFromCodexLine(line)) {
        this.emitAndMark(event);
      }
    }, "Codex");
  }

  private spawnCLI(command: "claude" | "codex", args: string[]): ChildProcessWithoutNullStreams {
    const executablePath = this.request.options.executablePath.trim() || command;
    return spawn(executablePath, args, {
      cwd: this.request.options.workingDirectory?.trim() || this.request.options.projectPath,
      env: this.processEnvironment(),
      shell: false,
      windowsHide: true
    });
  }

  private async consumeChildStreams(
    child: ChildProcessWithoutNullStreams,
    onStdoutLine: (line: string) => void,
    stderrTitle: string
  ): Promise<void> {
    const closePromise = this.waitForClose(child);
    const stdoutPromise = (async () => {
      for await (const line of readJSONLLines(child.stdout)) {
        onStdoutLine(line);
      }
    })();
    const stderrPromise = (async () => {
      for await (const line of readJSONLLines(child.stderr, { maxLineBytes: 256 * 1024 })) {
        const text = line.trim();
        if (!text) {
          continue;
        }
        this.didReceiveStderr = true;
        this.emit({
          type: "appendMessage",
          kind: "commandOutput",
          title: "stderr",
          subtitle: stderrTitle,
          text,
          status: "stream"
        });
      }
    })();

    const result = await closePromise;
    await Promise.allSettled([stdoutPromise, stderrPromise]);
    this.finishFromProcessResult(result, stderrTitle);
  }

  private waitForClose(child: ChildProcessWithoutNullStreams): Promise<ProcessResult> {
    return new Promise((resolve) => {
      child.once("error", (error) => {
        this.emitTerminal({ type: "failed", message: `启动 CLI 失败：${error.message}` });
      });
      child.once("close", (code, signal) => resolve({ code, signal }));
    });
  }

  private finishFromProcessResult(result: ProcessResult, title: string): void {
    if (this.didEmitTerminalEvent) {
      return;
    }
    if (this.didInterrupt || result.signal) {
      this.emitTerminal({ type: "failed", message: `${title} 已停止。` });
      return;
    }
    if (result.code === 0) {
      if (this.didReceiveVisibleOutput || this.didReceiveStderr) {
        this.emitTerminal({ type: "finished" });
      } else {
        this.emitTerminal({ type: "failed", message: `${title} 没有输出任何对话内容。请检查认证配置或模型设置。` });
      }
      return;
    }
    this.emitTerminal({ type: "failed", message: `${title} 退出码：${result.code ?? "unknown"}` });
  }

  private claudeArguments(options: ChatRunOptions, session: { externalSessionID?: string | null } | null): string[] {
    const args: string[] = [];
    const resumeID = options.resumeSessionID?.trim() || session?.externalSessionID?.trim() || "";
    if (options.sessionMode === "continueLast") {
      args.push("--continue");
    } else if (options.sessionMode === "resume" && resumeID) {
      args.push("--resume", resumeID);
    }

    if (options.supportsStreamJSONInput) {
      args.push("-p");
    } else {
      args.push("-p", promptWithAttachments(this.request.prompt, this.request.attachments));
    }
    args.push("--output-format", "stream-json");
    if (options.supportsStreamJSONInput) {
      args.push("--input-format", "stream-json", "--replay-user-messages");
    }
    args.push("--verbose", "--include-partial-messages", "--permission-mode", claudePermissionMode(options.permissionMode), "--effort", options.reasoningEffort);
    if (options.modelID.toLowerCase().startsWith("claude-")) {
      args.push("--model", options.modelID);
    }
    return args;
  }

  private writeClaudeUserMessage(
    text: string,
    parentToolUseID: string | null,
    toolUseResult: JSONRecord | null,
    attachments: ChatMessageAttachment[] = []
  ): boolean {
    const trimmed = promptWithAttachments(text, attachments).trim();
    if (!trimmed) {
      return false;
    }
    const object: JSONRecord = {
      type: "user",
      uuid: randomUUID(),
      message: {
        role: "user",
        content: trimmed
      },
      shouldQuery: true
    };
    const sessionID = this.request.session?.externalSessionID?.trim();
    if (sessionID) {
      object.session_id = sessionID;
    }
    if (parentToolUseID) {
      object.parent_tool_use_id = parentToolUseID;
    }
    if (toolUseResult) {
      object.tool_use_result = toolUseResult;
    }
    return this.writeJSONObject(object);
  }

  private eventsFromClaudeLine(line: string): ChatBackendEvent[] {
    const object = parseJSONObject(line);
    if (!object) {
      return [{ type: "appendMessage", kind: "rawOutput", title: "raw", subtitle: "Claude Code", text: line, status: "stream" }];
    }

    const events: ChatBackendEvent[] = [];
    const sessionID = stringValue(object.session_id) ?? stringValue(object.sessionId);
    if (sessionID) {
      events.push({ type: "sessionID", externalSessionID: sessionID });
    }
    const usage = tokenUsageEvent(object);
    if (usage) {
      events.push(usage);
    }

    const type = stringValue(object.type) ?? stringValue(object.event) ?? "raw";
    if (type === "user") {
      return events;
    }
    const lowerType = type.toLowerCase();
    const requestID = stringValue(object.request_id) ?? stringValue(object.id);
    if (lowerType.includes("error") || lowerType.includes("fail")) {
      events.push({
        type: "appendMessage",
        kind: "error",
        title: "Claude Code",
        subtitle: type,
        text: compactText(object),
        status: "failed",
        requestID
      });
      return events;
    }
    if (type === "system") {
      const subtype = stringValue(object.subtype);
      if (subtype === "init") {
        const tools = Array.isArray(object.tools) ? object.tools.length : 0;
        events.push({ type: "appendMessage", kind: "system", title: "Claude Code", subtitle: "init", text: tools ? `tools: ${tools}` : "initialized", status: "done" });
      }
      return events;
    }
    if (type === "assistant") {
      const message = recordValue(object.message) ?? object;
      events.push(...assistantEventsFromContent(message, requestID));
      return events;
    }
    if (type === "stream_event") {
      events.push(...claudeStreamEvents(object, requestID));
      return events;
    }
    if (type === "result") {
      const resultText = stringValue(object.result) ?? stringValue(object.message);
      if (resultText && stringValue(object.subtype) !== "success") {
        events.push({ type: "appendMessage", kind: "error", title: "result", subtitle: stringValue(object.subtype) ?? "", text: resultText, status: "done" });
      }
      return events;
    }
    if (isPermissionRequestType(type)) {
      events.push({ type: "permissionRequest", id: requestID ?? randomUUID(), title: type, text: compactText(object) });
      return events;
    }
    if (lowerType.includes("tool")) {
      events.push({
        type: "appendMessage",
        kind: lowerType.includes("result") ? "toolResult" : "toolCall",
        title: type,
        subtitle: stringValue(object.name) ?? "",
        text: compactText(object),
        status: "done",
        requestID
      });
    }
    return events;
  }

  private eventsFromCodexLine(line: string): ChatBackendEvent[] {
    const object = parseJSONObject(line);
    if (!object) {
      return [];
    }
    if (recordValue(object.error)) {
      return this.eventsFromCodexError(recordValue(object.error) ?? {}, object);
    }

    const id = object.id;
    const idKey = requestKey(id);
    const pending = idKey ? this.pendingCodexRequests.get(idKey) : undefined;
    if (pending && idKey) {
      this.pendingCodexRequests.delete(idKey);
      return this.eventsFromCodexResponse(object, pending);
    }

    const method = stringValue(object.method);
    if (!method) {
      return [];
    }
    if (id !== undefined && id !== null) {
      if (isCodexApprovalRequest(method)) {
        return this.eventsFromCodexApprovalRequest(object, id, method);
      }
      if (isCodexInteractiveRequest(method, object)) {
        return this.eventsFromCodexInteractiveRequest(object, id, method);
      }
      this.sendCodexErrorResponse(id, -32601, `Acode Windows 暂不支持 Codex server request: ${method}`);
      return [{ type: "appendMessage", kind: "rawOutput", title: method, subtitle: "unsupported request", text: compactText(object), status: "unsupported", requestID: requestKey(id) ?? null }];
    }
    return this.eventsFromCodexNotification(object, method);
  }

  private eventsFromCodexResponse(object: JSONRecord, pending: PendingCodexRequest): ChatBackendEvent[] {
    if (pending === "initialize") {
      this.sendCodexNotification("initialized");
      this.requestCodexThread();
      return [{ type: "updateStreamingStatus", status: "initialized" }];
    }
    if (pending === "openThread") {
      const result = recordValue(object.result);
      const threadID = result ? threadIDFrom(result) : null;
      if (!threadID) {
        this.emitTerminal({ type: "failed", message: "Codex thread/start 未返回 thread id。" });
        this.stopProcess();
        return [];
      }
      this.activeThreadID = threadID;
      this.requestCodexTurnStart(threadID);
      return [
        { type: "sessionID", externalSessionID: threadID },
        { type: "updateStreamingStatus", status: "thread ready" }
      ];
    }
    if (pending === "startTurn") {
      const result = recordValue(object.result);
      const turnID = result ? turnIDFrom(result) : null;
      if (turnID) {
        this.activeTurnID = turnID;
      }
      return [{ type: "updateStreamingStatus", status: "turn started" }];
    }
    if (pending === "interrupt") {
      this.emitTerminal({ type: "finished" });
      return [];
    }
    return [];
  }

  private eventsFromCodexNotification(object: JSONRecord, method: string): ChatBackendEvent[] {
    const params = recordValue(object.params) ?? {};
    switch (method) {
      case "thread/started": {
        const threadID = threadIDFrom(params);
        if (!threadID) {
          return [];
        }
        this.activeThreadID = threadID;
        return [{ type: "sessionID", externalSessionID: threadID }];
      }
      case "turn/started": {
        const turnID = turnIDFrom(params);
        if (turnID) {
          this.activeTurnID = turnID;
        }
        return [{ type: "updateStreamingStatus", status: "streaming" }];
      }
      case "item/agentMessage/delta":
        return [{ type: "appendDelta", kind: "assistant", title: "assistant", subtitle: "Codex", text: deltaText(params), status: "streaming", requestID: itemIDFrom(params) }];
      case "item/reasoning/textDelta":
      case "item/reasoning/summaryTextDelta":
        return nonEmptyDelta("reasoning", "reasoning", params, this.outputRequestID(method, params));
      case "item/plan/delta":
        return nonEmptyDelta("toolCall", "plan", params, this.outputRequestID(method, params));
      case "command/exec/outputDelta":
      case "item/commandExecution/outputDelta":
        return nonEmptyDelta("commandOutput", itemTitle(params, "command output"), params, this.outputRequestID(method, params));
      case "item/fileChange/outputDelta":
      case "turn/diff/updated":
        return nonEmptyDelta("diff", itemTitle(params, "file change"), params, this.outputRequestID(method, params));
      case "item/started":
      case "item/completed": {
        const itemType = itemTypeFrom(params).toLowerCase();
        if (shouldSuppressCodexItemType(itemType)) {
          return [];
        }
        const completed = method === "item/completed";
        return [{
          type: "appendMessage",
          kind: kindForCodexItem(params, completed),
          title: itemTitle(params, completed ? "item completed" : "item started"),
          subtitle: "Codex",
          text: compactText(params),
          status: completed ? "done" : "streaming",
          requestID: itemIDFrom(params)
        }];
      }
      case "thread/tokenUsage/updated": {
        const usage = recordValue(params.usage);
        return [{
          type: "tokenUsage",
          used: intValue(params.used) ?? intValue(usage?.used) ?? 0,
          total: intValue(params.total) ?? intValue(usage?.total) ?? 0,
          output: intValue(params.output) ?? intValue(usage?.output) ?? null
        }];
      }
      case "turn/completed": {
        const turn = recordValue(params.turn);
        const error = turn?.error;
        if (error !== undefined && error !== null) {
          this.emitTerminal({ type: "failed", message: codexErrorText(error) });
        } else {
          this.emitTerminal({ type: "finished" });
        }
        this.stopProcess();
        return [];
      }
      case "error":
        return this.eventsFromCodexError(params, object);
      default:
        return [];
    }
  }

  private eventsFromCodexApprovalRequest(object: JSONRecord, id: unknown, method: string): ChatBackendEvent[] {
    const requestID = requestKey(id) ?? randomUUID();
    const params = recordValue(object.params) ?? {};
    this.pendingApprovals.set(requestID, {
      id,
      method,
      requestedPermissions: recordValue(params.permissions)
    });
    return [{ type: "permissionRequest", id: requestID, title: titleForApprovalMethod(method), text: approvalText(method, params) }];
  }

  private eventsFromCodexInteractiveRequest(object: JSONRecord, id: unknown, method: string): ChatBackendEvent[] {
    const requestID = requestKey(id) ?? randomUUID();
    const params = recordValue(object.params) ?? {};
    this.pendingInteractiveRequests.set(requestID, { id, method });
    return [{
      type: "interactiveRequest",
      request: {
        id: requestID,
        title: stringValue(params.title) ?? "需要选择",
        prompt: stringValue(params.prompt) ?? stringValue(params.question) ?? stringValue(params.message) ?? stringValue(params.text) ?? "请选择后继续。",
        mode: Array.isArray(params.options) || Array.isArray(params.choices) ? "singleChoice" : "text",
        options: interactiveOptions(params),
        allowCustomInput: boolValue(params.allowCustomInput) ?? boolValue(params.allow_custom_input) ?? false,
        placeholder: stringValue(params.placeholder) ?? "输入回复",
        status: "waiting"
      }
    }];
  }

  private eventsFromCodexError(error: JSONRecord, envelope: JSONRecord): ChatBackendEvent[] {
    const message = codexErrorText(error);
    if (boolValue(envelope.willRetry) === true) {
      return [
        { type: "updateStreamingStatus", status: stringValue(error.message) ?? "reconnecting" },
        { type: "appendMessage", kind: "commandOutput", title: "codex", subtitle: "retrying", text: message, status: "retry" }
      ];
    }
    this.emitTerminal({ type: "failed", message });
    this.stopProcess();
    return [];
  }

  private requestCodexThread(): void {
    const options = this.request.options;
    const resumeID = options.resumeSessionID?.trim() || this.request.session?.externalSessionID?.trim() || "";
    const params: JSONRecord = {
      cwd: options.projectPath,
      approvalPolicy: codexApprovalPolicy(options.permissionMode),
      sandbox: codexSandbox(options.permissionMode),
      serviceName: "Acode"
    };
    if (isExplicitModelID(options.modelID)) {
      params.model = options.modelID;
    }
    const method = options.sessionMode === "resume" && resumeID ? "thread/resume" : "thread/start";
    if (method === "thread/resume") {
      params.threadId = resumeID;
    }
    const id = this.sendCodexRequest(method, params);
    this.pendingCodexRequests.set(String(id), "openThread");
  }

  private requestCodexTurnStart(threadID: string): void {
    const options = this.request.options;
    const params: JSONRecord = {
      threadId: threadID,
      input: [{
        type: "text",
        text: promptWithAttachments(this.request.prompt, this.request.attachments),
        text_elements: []
      }],
      cwd: options.projectPath,
      approvalPolicy: codexApprovalPolicy(options.permissionMode)
    };
    if (isExplicitModelID(options.modelID)) {
      params.model = options.modelID;
    }
    const id = this.sendCodexRequest("turn/start", params);
    this.pendingCodexRequests.set(String(id), "startTurn");
  }

  private codexApprovalResult(approval: PendingApproval, decision: ChatPermissionDecision): JSONRecord {
    if (approval.method === "item/permissions/requestApproval") {
      return {
        permissions: decision === "deny" ? {} : approval.requestedPermissions ?? {},
        scope: decision === "allowForSession" ? "session" : "turn"
      };
    }
    if (approval.method === "applyPatchApproval" || approval.method === "execCommandApproval") {
      return { decision: decision === "deny" ? "denied" : "approved" };
    }
    return { decision: codexApprovalDecision(decision) };
  }

  private outputRequestID(method: string, params: JSONRecord): string {
    return outputIDFrom(params) ?? `${this.activeTurnID ?? this.activeThreadID ?? "turn"}-${method}`;
  }

  private sendCodexRequest(method: string, params: unknown): number {
    const id = this.nextCodexID;
    this.nextCodexID += 1;
    this.writeJSONObject({ id, method, params });
    return id;
  }

  private sendCodexNotification(method: string, params?: unknown): boolean {
    return this.writeJSONObject(params === undefined ? { method } : { method, params });
  }

  private sendCodexResponse(id: unknown, result: JSONRecord): boolean {
    return this.writeJSONObject({ id, result });
  }

  private sendCodexErrorResponse(id: unknown, code: number, message: string): boolean {
    return this.writeJSONObject({ id, error: { code, message } });
  }

  private writeJSONObject(object: JSONRecord): boolean {
    if (!this.child?.stdin.writable) {
      return false;
    }
    this.child.stdin.write(`${JSON.stringify(object)}\n`);
    return true;
  }

  private closeStdin(): void {
    if (this.child?.stdin.writable) {
      this.child.stdin.end();
    }
  }

  private stopProcess(): void {
    const child = this.child;
    if (!child || child.exitCode !== null || child.signalCode !== null) {
      return;
    }
    this.closeStdin();
    if (process.platform === "win32") {
      this.stopWindowsProcessTree(child);
      return;
    }
    child.kill("SIGINT");
    setTimeout(() => {
      if (child.exitCode === null && child.signalCode === null) {
        child.kill("SIGTERM");
      }
    }, 800);
    setTimeout(() => {
      if (child.exitCode === null && child.signalCode === null) {
        child.kill("SIGKILL");
      }
    }, 2200);
  }

  private stopWindowsProcessTree(child: ChildProcessWithoutNullStreams): void {
    const pid = child.pid;
    if (!pid) {
      child.kill();
      return;
    }
    setTimeout(() => {
      if (child.exitCode === null && child.signalCode === null) {
        execFile("taskkill", ["/PID", String(pid), "/T"], { windowsHide: true }, () => {});
      }
    }, 500);
    setTimeout(() => {
      if (child.exitCode === null && child.signalCode === null) {
        execFile("taskkill", ["/PID", String(pid), "/T", "/F"], { windowsHide: true }, () => {});
      }
    }, 1800);
  }

  private emitAndMark(event: ChatBackendEvent): void {
    if (isVisibleOutput(event)) {
      this.didReceiveVisibleOutput = true;
    }
    if (event.type === "finished" || event.type === "failed") {
      this.emitTerminal(event);
      return;
    }
    this.emit(event);
  }

  private emitTerminal(event: Extract<ChatBackendEvent, { type: "finished" | "failed" }>): void {
    if (this.didEmitTerminalEvent) {
      return;
    }
    this.didEmitTerminalEvent = true;
    this.emit(event);
  }

  private processEnvironment(): NodeJS.ProcessEnv {
    const env: NodeJS.ProcessEnv = { ...process.env, ...this.request.options.environment };
    for (const key of ["CODEX_CI", "CODEX_SANDBOX", "CODEX_THREAD_ID", "CODEX_INTERNAL_ORIGINATOR_OVERRIDE", "CODEX_SHELL"]) {
      delete env[key];
    }
    return env;
  }
}

function claudePermissionMode(mode: ChatRunOptions["permissionMode"]): string {
  if (mode === "ask") {
    return "default";
  }
  return mode === "fullAccess" ? "bypassPermissions" : "acceptEdits";
}

function codexApprovalPolicy(mode: ChatRunOptions["permissionMode"]): string {
  if (mode === "ask") {
    return "on-request";
  }
  return mode === "fullAccess" ? "never" : "on-failure";
}

function codexSandbox(mode: ChatRunOptions["permissionMode"]): string {
  return mode === "fullAccess" ? "danger-full-access" : "workspace-write";
}

function isExplicitModelID(modelID: string): boolean {
  const normalized = modelID.trim().toLowerCase();
  return normalized.length > 0 && normalized !== "default";
}

function codexApprovalDecision(decision: ChatPermissionDecision): string {
  if (decision === "deny") {
    return "decline";
  }
  return decision === "allowForSession" ? "acceptForSession" : "accept";
}

function parseJSONObject(line: string): JSONRecord | null {
  try {
    const value = JSON.parse(line) as unknown;
    return recordValue(value);
  } catch {
    return null;
  }
}

function recordValue(value: unknown): JSONRecord | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JSONRecord : null;
}

function stringValue(value: unknown): string | null {
  if (typeof value === "string") {
    return value;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return null;
}

function intValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string" && value.trim()) {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function boolValue(value: unknown): boolean | null {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "string") {
    if (["true", "1", "yes"].includes(value.toLowerCase())) {
      return true;
    }
    if (["false", "0", "no"].includes(value.toLowerCase())) {
      return false;
    }
  }
  return null;
}

function compactText(value: unknown): string {
  if (typeof value === "string") {
    return value;
  }
  const object = recordValue(value);
  if (!object) {
    return "";
  }
  const direct = stringValue(object.text) ?? stringValue(object.message) ?? stringValue(object.delta) ?? stringValue(object.content);
  if (direct) {
    return direct;
  }
  const item = recordValue(object.item);
  if (item) {
    const itemText = stringValue(item.text) ?? stringValue(item.message) ?? stringValue(item.delta) ?? stringValue(item.content);
    if (itemText) {
      return itemText;
    }
  }
  return JSON.stringify(object);
}

const fileChangeToolNames = new Set(["edit", "write", "multiedit", "create", "create_file", "new_file", "notebookedit"]);

// File-change tools need their structured input (file_path + old/new_string or content) preserved
// so the renderer can draw a proper diff card — compactText would flatten Write down to bare
// content and drop the path. Everything else stays on compactText to keep tool noise short.
function toolCallText(name: string | null | undefined, input: unknown): string {
  if (name && fileChangeToolNames.has(name.toLowerCase())) {
    const record = recordValue(input);
    if (record) {
      return JSON.stringify(record);
    }
  }
  return compactText(input);
}

function assistantEventsFromContent(message: JSONRecord, requestID: string | null | undefined): ChatBackendEvent[] {
  const content = message.content;
  if (typeof content === "string" && content) {
    return [{ type: "appendDelta", kind: "assistant", title: "assistant", subtitle: "Claude Code", text: content, status: "streaming", requestID }];
  }
  if (!Array.isArray(content)) {
    return [];
  }
  const events: ChatBackendEvent[] = [];
  for (const block of content) {
    const item = recordValue(block);
    if (!item) {
      continue;
    }
    const type = stringValue(item.type) ?? "";
    const id = stringValue(item.id) ?? requestID ?? null;
    if (type === "text") {
      const text = stringValue(item.text);
      if (text) {
        events.push({ type: "appendDelta", kind: "assistant", title: "assistant", subtitle: "Claude Code", text, status: "streaming", requestID: id });
      }
    } else if (type === "tool_use") {
      events.push({ type: "appendMessage", kind: "toolCall", title: stringValue(item.name) ?? "tool", subtitle: "Claude Code", text: toolCallText(stringValue(item.name), item.input), status: "done", requestID: id });
    } else if (type === "tool_result") {
      events.push({ type: "appendMessage", kind: "toolResult", title: "tool result", subtitle: "Claude Code", text: compactText(item.content), status: "done", requestID: id });
    }
  }
  return events;
}

function claudeStreamEvents(object: JSONRecord, fallbackID: string | null | undefined): ChatBackendEvent[] {
  const event = recordValue(object.event) ?? object;
  const eventType = stringValue(event.type) ?? stringValue(object.event) ?? "";
  const delta = recordValue(event.delta) ?? recordValue(object.delta);
  const text = stringValue(delta?.text) ?? stringValue(delta?.partial_json) ?? stringValue(event.text) ?? stringValue(object.text);
  if (text) {
    const kind = eventType.toLowerCase().includes("thinking") ? "reasoning" : "assistant";
    return [{ type: "appendDelta", kind, title: kind, subtitle: "Claude Code", text, status: "streaming", requestID: stringValue(event.index) ?? fallbackID }];
  }
  const contentBlock = recordValue(event.content_block) ?? recordValue(object.content_block);
  if (contentBlock && stringValue(contentBlock.type) === "tool_use") {
    return [{
      type: "appendMessage",
      kind: "toolCall",
      title: stringValue(contentBlock.name) ?? "tool",
      subtitle: "Claude Code",
      text: toolCallText(stringValue(contentBlock.name), contentBlock.input),
      status: "streaming",
      requestID: stringValue(contentBlock.id) ?? fallbackID
    }];
  }
  if (eventType === "content_block_stop") {
    return [{ type: "finishStreamingMessage", kind: "assistant", requestID: fallbackID, status: "done" }];
  }
  return [];
}

function tokenUsageEvent(object: JSONRecord): ChatBackendEvent | null {
  const usage = recordValue(object.usage) ?? recordValue(recordValue(object.message)?.usage);
  if (!usage) {
    return null;
  }
  const input = intValue(usage.input_tokens) ?? intValue(usage.input) ?? 0;
  const output = intValue(usage.output_tokens) ?? intValue(usage.output) ?? 0;
  const total = input + output;
  return total > 0 ? { type: "tokenUsage", used: total, total: 200_000, output } : null;
}

function isPermissionRequestType(type: string): boolean {
  const normalized = type.toLowerCase();
  return normalized.includes("permission") || normalized.includes("approval");
}

function isCodexApprovalRequest(method: string): boolean {
  return [
    "item/commandExecution/requestApproval",
    "item/fileChange/requestApproval",
    "item/permissions/requestApproval",
    "applyPatchApproval",
    "execCommandApproval"
  ].includes(method);
}

function isCodexInteractiveRequest(method: string, object: JSONRecord): boolean {
  const params = recordValue(object.params) ?? {};
  const normalized = method.toLowerCase().replace(/_/g, "");
  return !normalized.includes("approval")
    && !normalized.includes("permission")
    && (normalized.includes("ask")
      || normalized.includes("question")
      || normalized.includes("choice")
      || normalized.includes("input")
      || Array.isArray(params.options)
      || Array.isArray(params.choices));
}

function requestKey(value: unknown): string | null {
  if (typeof value === "string") {
    return value;
  }
  if (typeof value === "number") {
    return String(value);
  }
  return null;
}

function threadIDFrom(object: JSONRecord): string | null {
  const thread = recordValue(object.thread);
  return stringValue(object.threadId) ?? stringValue(object.thread_id) ?? stringValue(thread?.id) ?? stringValue(thread?.threadId);
}

function turnIDFrom(object: JSONRecord): string | null {
  const turn = recordValue(object.turn);
  return stringValue(object.turnId) ?? stringValue(object.turn_id) ?? stringValue(turn?.id) ?? stringValue(turn?.turnId);
}

function itemIDFrom(object: JSONRecord): string | null {
  const item = recordValue(object.item);
  return stringValue(object.itemId) ?? stringValue(object.item_id) ?? stringValue(object.id) ?? stringValue(item?.id) ?? stringValue(item?.itemId);
}

function outputIDFrom(object: JSONRecord): string | null {
  const item = recordValue(object.item);
  return stringValue(object.itemId)
    ?? stringValue(object.item_id)
    ?? stringValue(object.callId)
    ?? stringValue(object.call_id)
    ?? stringValue(object.commandId)
    ?? stringValue(object.command_id)
    ?? stringValue(object.outputId)
    ?? stringValue(object.output_id)
    ?? stringValue(object.id)
    ?? (item ? outputIDFrom(item) : null);
}

function itemTitle(object: JSONRecord, fallback: string): string {
  const item = recordValue(object.item);
  return stringValue(object.title) ?? stringValue(object.name) ?? stringValue(object.type) ?? stringValue(item?.title) ?? stringValue(item?.name) ?? stringValue(item?.type) ?? fallback;
}

function itemTypeFrom(object: JSONRecord): string {
  const item = recordValue(object.item);
  return stringValue(object.type) ?? stringValue(object.itemType) ?? stringValue(object.item_type) ?? stringValue(item?.type) ?? stringValue(item?.itemType) ?? stringValue(item?.item_type) ?? "";
}

function deltaText(object: JSONRecord): string {
  return stringValue(object.delta) ?? stringValue(object.text) ?? stringValue(object.content) ?? compactText(object);
}

function nonEmptyDelta(kind: ChatMessageKind, title: string, params: JSONRecord, requestID: string): ChatBackendEvent[] {
  const text = deltaText(params);
  if (!text) {
    return [];
  }
  return [{ type: "appendDelta", kind, title, subtitle: "Codex", text, status: "streaming", requestID }];
}

function shouldSuppressCodexItemType(itemType: string): boolean {
  const normalized = itemType.replace(/[_\-\s]/g, "");
  return normalized.includes("usermessage")
    || normalized === "userinput"
    || normalized === "stderr"
    || normalized.includes("reasoning")
    || normalized.includes("plan");
}

function kindForCodexItem(object: JSONRecord, completed: boolean): ChatMessageKind {
  const item = recordValue(object.item);
  const haystack = [
    stringValue(object.type),
    stringValue(object.name),
    stringValue(item?.type),
    stringValue(item?.name)
  ].filter((value): value is string => Boolean(value)).join(" ").toLowerCase();
  const normalized = haystack.replace(/_/g, "");
  if (normalized.includes("agentmessage") || normalized.includes("assistantmessage")) {
    return "assistant";
  }
  if (haystack.includes("diff") || haystack.includes("patch") || haystack.includes("filechange") || haystack.includes("file_change")) {
    return "diff";
  }
  if (haystack.includes("command") || haystack.includes("exec") || haystack.includes("shell")) {
    return completed ? "commandOutput" : "command";
  }
  return completed ? "toolResult" : "toolCall";
}

function titleForApprovalMethod(method: string): string {
  if (method === "item/commandExecution/requestApproval" || method === "execCommandApproval") {
    return "命令执行权限";
  }
  if (method === "item/fileChange/requestApproval" || method === "applyPatchApproval") {
    return "文件修改权限";
  }
  if (method === "item/permissions/requestApproval") {
    return "额外权限请求";
  }
  return method;
}

function approvalText(method: string, params: JSONRecord): string {
  if (method === "item/commandExecution/requestApproval") {
    return [stringValue(params.command) ?? "未知命令", stringValue(params.cwd) ? `cwd: ${stringValue(params.cwd)}` : null, stringValue(params.reason)]
      .filter((value): value is string => Boolean(value))
      .join("\n");
  }
  if (method === "item/fileChange/requestApproval") {
    return [stringValue(params.grantRoot) ? `root: ${stringValue(params.grantRoot)}` : "文件修改", stringValue(params.reason)]
      .filter((value): value is string => Boolean(value))
      .join("\n");
  }
  return compactText(params);
}

function interactiveOptions(params: JSONRecord): Array<{ id: string; label: string; detail: string }> {
  const rawOptions = Array.isArray(params.options) ? params.options : Array.isArray(params.choices) ? params.choices : [];
  return rawOptions.map((option, index) => {
    const text = stringValue(option);
    if (text) {
      return { id: text, label: text, detail: "" };
    }
    const object = recordValue(option) ?? {};
    const id = stringValue(object.id) ?? stringValue(object.value) ?? stringValue(object.label) ?? `option-${index + 1}`;
    return {
      id,
      label: stringValue(object.label) ?? stringValue(object.title) ?? stringValue(object.text) ?? id,
      detail: stringValue(object.detail) ?? stringValue(object.description) ?? ""
    };
  });
}

function codexErrorText(error: unknown): string {
  if (typeof error === "string" && error.trim()) {
    return friendlyCodexErrorText(error);
  }
  const object = recordValue(error);
  if (!object) {
    return "Codex 运行失败。";
  }
  const text = [stringValue(object.message), stringValue(object.additionalDetails), stringValue(object.codexErrorInfo)]
    .filter((value): value is string => Boolean(value?.trim()))
    .join("\n");
  return friendlyCodexErrorText(text || compactText(object));
}

function friendlyCodexErrorText(raw: string): string {
  const lower = raw.toLowerCase();
  if (lower.includes("unauthorized") || lower.includes("access token could not be refreshed") || lower.includes("please sign in again")) {
    return "Codex 中转站认证失败。请检查 Codex base_url、OPENAI_API_KEY 和 model。";
  }
  if (lower.includes("failed to lookup address information") || lower.includes("timeout waiting for child process")) {
    return "Codex 网络连接失败。请确认代理和 Codex base_url 后重试。";
  }
  return raw || "Codex 运行失败。";
}

function promptWithAttachments(prompt: string, attachments: ChatMessageAttachment[] = []): string {
  const text = prompt.trim();
  if (attachments.length === 0) {
    return text;
  }

  const attachmentLines = attachments.map((attachment) => `- ${attachment.filename}: ${attachment.path}`);
  const lead = text || "请根据以下附件继续处理。";
  return `${lead}\n\n附件:\n${attachmentLines.join("\n")}`;
}

function isVisibleOutput(event: ChatBackendEvent): boolean {
  if (event.type === "appendDelta" || event.type === "permissionRequest" || event.type === "interactiveRequest" || event.type === "failed") {
    return true;
  }
  return event.type === "appendMessage" && event.kind !== "system" && event.text.length > 0;
}
