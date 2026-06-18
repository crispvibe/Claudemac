import {
  ArrowUp,
  Bot,
  Check,
  ChevronDown,
  ChevronRight,
  Copy,
  FileText,
  Loader2,
  Paperclip,
  Square,
  Terminal,
  X
} from "lucide-react";
import { FormEvent, memo, useEffect, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";
import type {
  ChatMessage,
  ChatMessageAttachment,
  InteractiveRequest,
  PermissionDecision,
  ProjectSnapshot,
  QueuedChatRequest
} from "@shared/chat";
import { isChatRunStatusRunning } from "@shared/chat";
import type { CLIKind, PermissionMode, ReasoningEffort } from "@shared/settings";
import { createIpcChatBackend, useChatStore } from "@renderer/src/stores/chatStore";
import { useEditorStore } from "@renderer/src/stores/editorStore";
import { useProjectStore } from "@renderer/src/stores/projectStore";
import { useSettingsStore } from "@renderer/src/stores/settingsStore";

type ComposerPicker = "cli" | "permission" | "model" | "reasoning";

const permissionOptions: Array<{ value: PermissionMode; label: string; detail: string }> = [
  { value: "default", label: "询问", detail: "按 CLI 默认策略请求确认" },
  { value: "plan", label: "计划", detail: "先产出计划再执行" },
  { value: "acceptEdits", label: "自动编辑", detail: "允许安全编辑自动通过" },
  { value: "bypassPermissions", label: "全权限", detail: "跳过权限确认" }
];

const reasoningOptions: Array<{ value: ReasoningEffort; label: string; detail: string }> = [
  { value: "minimal", label: "Minimal", detail: "快速轻量" },
  { value: "low", label: "Low", detail: "低推理" },
  { value: "medium", label: "Medium", detail: "默认平衡" },
  { value: "high", label: "High", detail: "更强推理" }
];

function basename(path: string): string {
  const normalized = path.replaceAll("\\", "/").replace(/\/+$/u, "");
  return normalized.split("/").filter(Boolean).at(-1) ?? "文件";
}

function useCurrentProject(): ProjectSnapshot | null {
  const projects = useProjectStore((state) => state.projects);
  const selectedProjectId = useProjectStore((state) => state.selectedProjectId);

  return useMemo(() => {
    const project = projects.find((item) => item.id === selectedProjectId) ?? null;
    return project
      ? {
          id: project.id,
          name: project.name,
          path: project.path
        }
      : null;
  }, [projects, selectedProjectId]);
}

function kindLabel(kind: ChatMessage["kind"]): string {
  switch (kind) {
    case "toolCall":
      return "tool";
    case "toolResult":
      return "result";
    case "command":
      return "command";
    case "commandOutput":
      return "output";
    case "diff":
      return "diff";
    case "error":
      return "error";
    default:
      return kind;
  }
}

type MessageTextBlock =
  | { kind: "text"; text: string }
  | { kind: "code"; language: string; text: string };

const hiddenTranscriptKinds = new Set<ChatMessage["kind"]>(["system", "result", "rawOutput"]);

const foldableToolNames = new Set(["read", "grep", "glob"]);

function toolName(message: ChatMessage): string {
  return (message.title || message.subtitle || kindLabel(message.kind)).trim();
}

function isFoldableReadTool(message: ChatMessage): boolean {
  return message.kind === "toolCall" && foldableToolNames.has(toolName(message).toLowerCase());
}

const toolPathKeys = ["file_path", "filePath", "filepath", "path", "filename", "notebook_path"];

function extractToolFilePath(text: string): string | null {
  const trimmed = text.trim();
  if (!trimmed) {
    return null;
  }
  if (trimmed.startsWith("{")) {
    try {
      const parsed = JSON.parse(trimmed) as Record<string, unknown>;
      for (const key of toolPathKeys) {
        const value = parsed[key];
        if (typeof value === "string" && value.trim()) {
          return value.trim();
        }
      }
    } catch {
      // fall through to regex below
    }
  }
  for (const key of toolPathKeys) {
    const match = new RegExp(`"${key}"\\s*:\\s*"([^"]+)"`, "u").exec(trimmed);
    if (match?.[1]) {
      return match[1];
    }
  }
  return null;
}

function toolHeaderSummary(message: ChatMessage): string | null {
  const path = extractToolFilePath(message.text);
  if (path) {
    return basename(path);
  }
  const firstLine = message.text.split("\n").map((line) => line.trim()).find(Boolean);
  if (!firstLine) {
    return null;
  }
  return firstLine.length > 80 ? `${firstLine.slice(0, 80)}…` : firstLine;
}

const fileChangeToolNames = new Set(["edit", "write", "multiedit", "create", "create_file", "new_file", "notebookedit"]);

function isFileChangeMessage(message: ChatMessage): boolean {
  return message.kind === "diff" || (message.kind === "toolCall" && fileChangeToolNames.has(toolName(message).toLowerCase()));
}

type DiffLine = { marker: "+" | "-" | " "; text: string };

const maxDiffPreviewLines = 300;

function capDiffLines(lines: DiffLine[]): DiffLine[] {
  return lines.length > maxDiffPreviewLines ? lines.slice(0, maxDiffPreviewLines) : lines;
}

// Turns a file-change tool payload into red/green diff lines, mirroring the Mac code-preview card:
// Edit → old_string(-)/new_string(+); MultiEdit → each edit; Write → content(+); diff kind → +/- prefixes.
function buildDiffLines(message: ChatMessage): DiffLine[] {
  const text = message.text.trim();
  const pushBlock = (lines: DiffLine[], value: unknown, marker: DiffLine["marker"]) => {
    String(value)
      .split("\n")
      .forEach((line) => lines.push({ marker, text: line }));
  };

  if (text.startsWith("{")) {
    try {
      const parsed = JSON.parse(text) as Record<string, unknown>;
      const lines: DiffLine[] = [];
      if (Array.isArray(parsed.edits)) {
        for (const entry of parsed.edits) {
          const edit = entry as Record<string, unknown>;
          if (typeof edit.old_string === "string" && edit.old_string) pushBlock(lines, edit.old_string, "-");
          if (typeof edit.new_string === "string" && edit.new_string) pushBlock(lines, edit.new_string, "+");
        }
        if (lines.length > 0) return capDiffLines(lines);
      }
      if (typeof parsed.old_string === "string" || typeof parsed.new_string === "string") {
        if (typeof parsed.old_string === "string" && parsed.old_string) pushBlock(lines, parsed.old_string, "-");
        if (typeof parsed.new_string === "string" && parsed.new_string) pushBlock(lines, parsed.new_string, "+");
        if (lines.length > 0) return capDiffLines(lines);
      }
      if (typeof parsed.content === "string") {
        pushBlock(lines, parsed.content, "+");
        return capDiffLines(lines);
      }
    } catch {
      // fall through to raw handling
    }
  }

  const raw = text.split("\n");
  if (message.kind === "diff") {
    const lines = raw
      .filter(
        (line) =>
          !line.startsWith("diff --git") && !line.startsWith("+++") && !line.startsWith("---") && !line.startsWith("@@")
      )
      .map<DiffLine>((line) => {
        if (line.startsWith("+")) return { marker: "+", text: line.slice(1) };
        if (line.startsWith("-")) return { marker: "-", text: line.slice(1) };
        return { marker: " ", text: line.startsWith(" ") ? line.slice(1) : line };
      });
    return capDiffLines(lines);
  }
  return capDiffLines(raw.map<DiffLine>((line) => ({ marker: " ", text: line })));
}

type RenderItem =
  | { type: "message"; message: ChatMessage }
  | { type: "toolBatch"; id: string; messages: ChatMessage[] };

// Mirrors the Mac transcript: collapse runs of consecutive Read/Grep/Glob tool calls (and the
// tool results interleaved with them) into a single foldable batch so the transcript stays clean.
function buildRenderItems(messages: ChatMessage[]): RenderItem[] {
  const items: RenderItem[] = [];
  let run: ChatMessage[] = [];

  const flush = () => {
    if (run.length === 0) {
      return;
    }
    const foldableCount = run.filter(isFoldableReadTool).length;
    if (foldableCount >= 2) {
      items.push({ type: "toolBatch", id: `tool-batch-${run[0].id}`, messages: run });
    } else {
      for (const message of run) {
        items.push({ type: "message", message });
      }
    }
    run = [];
  };

  for (const message of messages) {
    if (isFoldableReadTool(message) || (message.kind === "toolResult" && run.length > 0)) {
      run.push(message);
    } else {
      flush();
      items.push({ type: "message", message });
    }
  }
  flush();
  return items;
}

function parseMessageText(text: string): MessageTextBlock[] {
  const blocks: MessageTextBlock[] = [];
  const fencePattern = /```([^\n`]*)\n?([\s\S]*?)(?:```|$)/g;
  let cursor = 0;
  let match: RegExpExecArray | null;

  while ((match = fencePattern.exec(text)) !== null) {
    if (match.index > cursor) {
      blocks.push({ kind: "text", text: text.slice(cursor, match.index) });
    }
    blocks.push({ kind: "code", language: match[1]?.trim() ?? "", text: match[2] ?? "" });
    cursor = fencePattern.lastIndex;
  }

  if (cursor < text.length) {
    blocks.push({ kind: "text", text: text.slice(cursor) });
  }

  return blocks.length > 0 ? blocks : [{ kind: "text", text }];
}

function isNearScrollBottom(element: HTMLElement): boolean {
  return element.scrollHeight - element.scrollTop - element.clientHeight < 72;
}

export function ChatRuntimePanel() {
  const [input, setInput] = useState("");
  const [attachments, setAttachments] = useState<ChatMessageAttachment[]>([]);
  const [activePicker, setActivePicker] = useState<ComposerPicker | null>(null);
  const [customModel, setCustomModel] = useState("");
  const [expandedReasoningIds, setExpandedReasoningIds] = useState<Set<string>>(() => new Set());
  const [isNearBottom, setIsNearBottom] = useState(true);
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const shouldStickToBottomRef = useRef(true);
  const programmaticScrollRef = useRef(false);
  const composerComposingRef = useRef(false);
  const project = useCurrentProject();
  const settings = useSettingsStore((state) => state.settings);
  const settingsLoading = useSettingsStore((state) => state.loading);
  const loadSettings = useSettingsStore((state) => state.load);
  const savePatch = useSettingsStore((state) => state.savePatch);
  const updateProfile = useSettingsStore((state) => state.updateProfile);
  const messages = useChatStore((state) => state.messages);
  const queuedRequests = useChatStore((state) => state.queuedRequests);
  const status = useChatStore((state) => state.status);
  const statusText = useChatStore((state) => state.statusText);
  const tokensUsed = useChatStore((state) => state.tokensUsed);
  const tokensTotal = useChatStore((state) => state.tokensTotal);
  const isAwaitingFirstModelOutput = useChatStore((state) => state.isAwaitingFirstModelOutput);
  const setBackend = useChatStore((state) => state.setBackend);
  const hydrateSessions = useChatStore((state) => state.hydrateSessions);
  const send = useChatStore((state) => state.send);
  const stop = useChatStore((state) => state.stop);
  const cancelQueuedRequest = useChatStore((state) => state.cancelQueuedRequest);
  const activateProject = useChatStore((state) => state.activateProject);
  const respondToInteractiveRequest = useChatStore((state) => state.respondToInteractiveRequest);
  const openFile = useEditorStore((state) => state.openFile);
  const isRunning = isChatRunStatusRunning(status);
  const waitingInteractive = useMemo(
    () =>
      messages.find(
        (message) => message.kind === "interactiveRequest" && message.interactiveRequest?.status === "waiting"
      )?.interactiveRequest ?? null,
    [messages]
  );
  const renderItems = useMemo(() => buildRenderItems(messages), [messages]);
  const activeCLI = settings?.defaultCLI ?? "claude";
  const activeProfile = useMemo(() => {
    const profiles = settings?.profiles.filter((profile) => profile.kind === activeCLI && profile.enabled) ?? [];
    return profiles.find((profile) => profile.isDefault) ?? profiles[0] ?? null;
  }, [activeCLI, settings?.profiles]);
  const activePermission = activeProfile?.permissionMode ?? settings?.permissionMode ?? "default";
  const activeReasoning = activeProfile?.reasoningEffort ?? settings?.reasoningEffort ?? "medium";
  const activeModelLabel = activeProfile?.model?.trim() || settings?.model?.trim() || "默认模型";
  const knownModelOptions = useMemo(() => {
    const values = [
      settings?.model,
      activeProfile?.model,
      ...(settings?.profiles.filter((profile) => profile.kind === activeCLI).map((profile) => profile.model) ?? [])
    ]
      .map((value) => value?.trim())
      .filter((value): value is string => Boolean(value));
    return Array.from(new Set(values));
  }, [activeCLI, activeProfile?.model, settings?.model, settings?.profiles]);
  const appendRuleText = settings?.appendRule.enabled ? settings.appendRule.content.trim() : "";
  const messageScrollSignature = useMemo(
    () =>
      messages
        .map((message) => `${message.id}:${message.text.length}:${message.status ?? ""}:${message.isStreaming ? "1" : "0"}`)
        .join("|"),
    [messages]
  );
  const canSend = Boolean(project?.path && (input.trim() || attachments.length > 0));

  useEffect(() => {
    const chat = window.codevoke?.chat;
    setBackend(chat ? createIpcChatBackend(chat) : null);
    if (chat) {
      void chat.loadSessions().then(hydrateSessions).catch((error: unknown) => {
        console.error("[chat] failed to load session snapshot", error);
      });
    }
    return () => {
      setBackend(null);
    };
  }, [hydrateSessions, setBackend]);

  useEffect(() => {
    if (!settings && !settingsLoading) {
      void loadSettings();
    }
  }, [loadSettings, settings, settingsLoading]);

  useEffect(() => {
    activateProject(project);
  }, [activateProject, project?.id, project?.path]);

  useEffect(() => {
    const streamingReasoning = messages.filter((message) => message.kind === "reasoning" && message.isStreaming);
    if (streamingReasoning.length === 0) {
      return;
    }
    setExpandedReasoningIds((current) => {
      const next = new Set(current);
      for (const message of streamingReasoning) {
        next.add(message.id);
      }
      return next;
    });
  }, [messageScrollSignature, messages]);

  useEffect(() => {
    if (!shouldStickToBottomRef.current) {
      return;
    }
    const frame = window.requestAnimationFrame(() => {
      const viewport = viewportRef.current;
      if (!viewport) {
        return;
      }
      // Mark this as a programmatic scroll so the resulting scroll event doesn't bounce back
      // through updateScrollPosition and fight the rAF (which can thrash with tall, variable-height
      // cards like a pending choice question).
      programmaticScrollRef.current = true;
      viewport.scrollTo({ top: viewport.scrollHeight, behavior: "auto" });
      setIsNearBottom(true);
      window.requestAnimationFrame(() => {
        programmaticScrollRef.current = false;
      });
    });
    return () => window.cancelAnimationFrame(frame);
  }, [messageScrollSignature, queuedRequests.length, statusText]);

  function updateScrollPosition() {
    if (programmaticScrollRef.current) {
      return;
    }
    const viewport = viewportRef.current;
    if (!viewport) {
      return;
    }
    const nearBottom = isNearScrollBottom(viewport);
    shouldStickToBottomRef.current = nearBottom;
    setIsNearBottom(nearBottom);
  }

  function jumpToLatest() {
    const viewport = viewportRef.current;
    if (!viewport) {
      return;
    }
    shouldStickToBottomRef.current = true;
    setIsNearBottom(true);
    viewport.scrollTo({ top: viewport.scrollHeight, behavior: "smooth" });
  }

  function togglePicker(picker: ComposerPicker) {
    setActivePicker((current) => (current === picker ? null : picker));
  }

  async function selectCLI(cli: CLIKind) {
    setActivePicker(null);
    await savePatch({ defaultCLI: cli });
  }

  async function selectPermission(permissionMode: PermissionMode) {
    setActivePicker(null);
    if (activeProfile) {
      await updateProfile(activeProfile.id, { permissionMode });
      return;
    }
    await savePatch({ permissionMode });
  }

  async function selectReasoning(reasoningEffort: ReasoningEffort) {
    setActivePicker(null);
    if (activeProfile) {
      await updateProfile(activeProfile.id, { reasoningEffort });
      return;
    }
    await savePatch({ reasoningEffort });
  }

  async function selectModel(model: string) {
    const normalizedModel = model.trim();
    setActivePicker(null);
    if (activeProfile) {
      await updateProfile(activeProfile.id, { model: normalizedModel });
      return;
    }
    await savePatch({ model: normalizedModel });
  }

  async function handleCustomModelSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const model = customModel.trim();
    if (!model) {
      return;
    }
    setCustomModel("");
    await selectModel(model);
  }

  async function handleAttachFile() {
    const selection = await window.codevoke?.selectEditorFile();
    if (!selection?.path) {
      return;
    }
    const filePath = selection.path;
    setAttachments((current) => {
      if (current.some((attachment) => attachment.path === filePath)) {
        return current;
      }
      return [
        ...current,
        {
          id: `attachment-${crypto.randomUUID()}`,
          kind: "file",
          filename: basename(filePath),
          path: filePath
        }
      ];
    });
  }

  function removeAttachment(id: string) {
    setAttachments((current) => current.filter((attachment) => attachment.id !== id));
  }

  function handleEditQueuedRequest(request: QueuedChatRequest) {
    setInput(request.displayText);
    setAttachments(request.attachments);
    cancelQueuedRequest(request.id);
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const text = input.trim();
    // Answer a pending choice/text question straight from the main composer (parity with Mac),
    // instead of forcing the user down into the inline card.
    if (
      text &&
      waitingInteractive &&
      (waitingInteractive.allowCustomInput || waitingInteractive.mode === "text")
    ) {
      const didRespond = respondToInteractiveRequest({
        requestID: waitingInteractive.id,
        selectedOptionIDs: [],
        customText: text
      });
      if (didRespond) {
        setInput("");
        setActivePicker(null);
        return;
      }
    }
    if ((!text && attachments.length === 0) || !project?.path) {
      return;
    }
    const backendText = `${text}${appendRuleText ? `\n\n${appendRuleText}` : ""}`;
    const didSend = send({
      text,
      backendText,
      appendRuleText: appendRuleText || null,
      attachments,
      project,
      cli: activeCLI,
      sessionMode: "continueLast"
    });
    if (didSend) {
      shouldStickToBottomRef.current = true;
      setIsNearBottom(true);
      setInput("");
      setAttachments([]);
      setActivePicker(null);
    }
  }

  return (
    <>
      <div className="conversation" ref={viewportRef} onScroll={updateScrollPosition}>
        {messages.length === 0 ? (
          <div className="chat-empty-state">
            <b>{project ? "新对话" : "选择一个项目"}</b>
            <span>{project ? "输入需求后会在这里显示 Windows 端对话流。" : "添加或选择项目后才能开始会话。"}</span>
          </div>
        ) : (
          renderItems.map((item) =>
            item.type === "toolBatch" ? (
              <ToolBatchCard key={item.id} messages={item.messages} onOpenFile={openFile} />
            ) : (
              <ChatMessageRow
                key={item.message.id}
                message={item.message}
                onOpenFile={openFile}
                reasoningExpanded={expandedReasoningIds.has(item.message.id)}
                onToggleReasoning={() => {
                  setExpandedReasoningIds((current) => {
                    const next = new Set(current);
                    if (next.has(item.message.id)) {
                      next.delete(item.message.id);
                    } else {
                      next.add(item.message.id);
                    }
                    return next;
                  });
                }}
              />
            )
          )
        )}
        {isAwaitingFirstModelOutput ? (
          <div className="chat-loading-row">
            <Loader2 size={14} />
            <span>等待模型输出</span>
          </div>
        ) : null}
        {!isNearBottom ? (
          <button type="button" className="jump-latest-button" onClick={jumpToLatest}>
            回到底部
          </button>
        ) : null}
      </div>

      {queuedRequests.length > 0 ? (
        <QueuedRequestsPanel
          requests={queuedRequests}
          onCancel={cancelQueuedRequest}
          onEdit={handleEditQueuedRequest}
        />
      ) : null}

      <form className="composer-card" onSubmit={handleSubmit}>
        <textarea
          placeholder={
            !project
              ? "先选择项目"
              : waitingInteractive && (waitingInteractive.allowCustomInput || waitingInteractive.mode === "text")
                ? "输入你的选择或回复"
                : "输入你的需求"
          }
          rows={3}
          value={input}
          disabled={!project}
          onChange={(event) => setInput(event.target.value)}
          onCompositionStart={() => {
            composerComposingRef.current = true;
          }}
          onCompositionEnd={() => {
            composerComposingRef.current = false;
          }}
          onKeyDown={(event) => {
            if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing && !composerComposingRef.current) {
              event.preventDefault();
              event.currentTarget.form?.requestSubmit();
            }
          }}
        />
        <ComposerAttachments attachments={attachments} onRemove={removeAttachment} />
        <div className="composer-toolbar">
          <button type="button" className="plain-icon attach-button" onClick={() => void handleAttachFile()} aria-label="添加附件">
            <Paperclip size={18} />
          </button>
          <button type="button" className="composer-select" onClick={() => togglePicker("cli")}>
            <Terminal size={14} />
            <span>{cliLabel(activeCLI)}</span>
            <ChevronDown size={14} />
          </button>
          <button type="button" className="composer-select" onClick={() => togglePicker("permission")}>
            <span>{permissionLabel(activePermission)}</span>
            <ChevronDown size={14} />
          </button>
          <button type="button" className="composer-select model" onClick={() => togglePicker("model")} title={activeModelLabel}>
            <span>{activeModelLabel}</span>
            <ChevronDown size={14} />
          </button>
          <button type="button" className="composer-select compact" onClick={() => togglePicker("reasoning")}>
            <span>{reasoningLabel(activeReasoning)}</span>
            <ChevronDown size={14} />
          </button>
          <span className="chat-runtime-status" title={statusText}>
            {statusText}
            {tokensUsed > 0 ? ` · ${tokensUsed}/${tokensTotal}` : ""}
          </span>
          {isRunning ? (
            <button className="stop-button" type="button" onClick={stop} aria-label="停止当前运行">
              <Square size={13} />
            </button>
          ) : null}
          <button className="send-button" type="submit" disabled={!canSend} aria-label={isRunning ? "加入队列" : "发送"}>
            <ArrowUp size={18} />
          </button>
        </div>
        {activePicker ? (
          <div className="composer-picker-layer">
            {activePicker === "cli" ? (
              <PickerGroup>
                {(["claude", "codex"] as CLIKind[]).map((cli) => (
                  <PickerOption key={cli} active={activeCLI === cli} label={cliLabel(cli)} onClick={() => void selectCLI(cli)} />
                ))}
              </PickerGroup>
            ) : null}
            {activePicker === "permission" ? (
              <PickerGroup>
                {permissionOptions.map((option) => (
                  <PickerOption
                    key={option.value}
                    active={activePermission === option.value}
                    label={option.label}
                    detail={option.detail}
                    onClick={() => void selectPermission(option.value)}
                  />
                ))}
              </PickerGroup>
            ) : null}
            {activePicker === "reasoning" ? (
              <PickerGroup>
                {reasoningOptions.map((option) => (
                  <PickerOption
                    key={option.value}
                    active={activeReasoning === option.value}
                    label={option.label}
                    detail={option.detail}
                    onClick={() => void selectReasoning(option.value)}
                  />
                ))}
              </PickerGroup>
            ) : null}
            {activePicker === "model" ? (
              <PickerGroup>
                <PickerOption active={activeModelLabel === "默认模型"} label="默认模型" onClick={() => void selectModel("")} />
                {knownModelOptions.map((model) => (
                  <PickerOption key={model} active={activeModelLabel === model} label={model} onClick={() => void selectModel(model)} />
                ))}
                <form className="picker-custom-model" onSubmit={(event) => void handleCustomModelSubmit(event)}>
                  <input
                    value={customModel}
                    onChange={(event) => setCustomModel(event.target.value)}
                    placeholder="输入模型名称"
                  />
                  <button type="submit">使用</button>
                </form>
              </PickerGroup>
            ) : null}
          </div>
        ) : null}
      </form>
    </>
  );
}

function cliLabel(cli: CLIKind): string {
  return cli === "codex" ? "Codex" : "Claude Code";
}

function permissionLabel(mode: PermissionMode): string {
  return permissionOptions.find((option) => option.value === mode)?.label ?? "询问";
}

function reasoningLabel(effort: ReasoningEffort): string {
  return reasoningOptions.find((option) => option.value === effort)?.label ?? "Medium";
}

function PickerGroup({ children }: { children: ReactNode }) {
  return <div className="composer-picker-group">{children}</div>;
}

function PickerOption({
  active,
  detail,
  label,
  onClick
}: {
  active: boolean;
  detail?: string;
  label: string;
  onClick: () => void;
}) {
  return (
    <button type="button" className={`composer-picker-option ${active ? "active" : ""}`} onClick={onClick} title={label}>
      <span>
        <b>{label}</b>
        {detail ? <small>{detail}</small> : null}
      </span>
      {active ? <Check size={14} /> : null}
    </button>
  );
}

function QueuedRequestsPanel({
  requests,
  onCancel,
  onEdit
}: {
  requests: QueuedChatRequest[];
  onCancel: (id: string) => void;
  onEdit: (request: QueuedChatRequest) => void;
}) {
  return (
    <div className="queued-requests-panel">
      <div className="queued-requests-header">
        <span>{requests.length} 条请求排队中</span>
      </div>
      {requests.map((request) => (
        <div className="queued-request-row" key={request.id}>
          <div>
            <b>{request.displayText}</b>
            <span>
              {cliLabel(request.cli)} · {request.modelID}
            </span>
          </div>
          <button type="button" onClick={() => onEdit(request)}>
            编辑
          </button>
          <button type="button" aria-label="取消排队请求" onClick={() => onCancel(request.id)}>
            <X size={13} />
          </button>
        </div>
      ))}
    </div>
  );
}

function ComposerAttachments({
  attachments,
  onRemove
}: {
  attachments: ChatMessageAttachment[];
  onRemove: (id: string) => void;
}) {
  if (attachments.length === 0) {
    return null;
  }
  return (
    <div className="composer-attachments">
      {attachments.map((attachment) => (
        <span className="composer-attachment-pill" key={attachment.id} title={attachment.path}>
          <FileText size={12} />
          {attachment.filename}
          <button type="button" aria-label={`移除 ${attachment.filename}`} onClick={() => onRemove(attachment.id)}>
            <X size={11} />
          </button>
        </span>
      ))}
    </div>
  );
}

const ChatMessageRow = memo(function ChatMessageRow({
  message,
  onOpenFile,
  onToggleReasoning,
  reasoningExpanded
}: {
  message: ChatMessage;
  onOpenFile: (path: string) => void | Promise<void>;
  onToggleReasoning: () => void;
  reasoningExpanded: boolean;
}) {
  if (message.kind === "permissionRequest") {
    return <PermissionRequestCard message={message} />;
  }

  if (message.kind === "interactiveRequest" && message.interactiveRequest) {
    return <InteractiveRequestCard request={message.interactiveRequest} />;
  }

  if (message.kind === "user") {
    return (
      <div className="user-message">
        <span>{message.text}</span>
        <MessageAttachmentStrip attachments={message.attachments ?? []} />
        <time>{formatMessageTime(message.createdAt)}</time>
        <div className="bubble-tools">
          <Copy size={14} />
        </div>
      </div>
    );
  }

  if (message.kind === "reasoning") {
    return (
      <div className="assistant-message reasoning-message">
        <div className="assistant-avatar" aria-hidden="true">
          <Bot size={16} />
        </div>
        <div className="assistant-bubble">
          <button type="button" className="thinking-row" onClick={onToggleReasoning}>
            {reasoningExpanded ? <ChevronDown size={13} /> : <ChevronRight size={13} />}
            <b>thinking</b>
            {message.isStreaming ? <span>streaming</span> : null}
          </button>
          {reasoningExpanded ? <MessageText text={message.text || "正在整理推理..."} /> : null}
        </div>
      </div>
    );
  }

  if (message.kind === "assistant") {
    return <AssistantMessageCard message={message} />;
  }

  if (hiddenTranscriptKinds.has(message.kind)) {
    return <DiagnosticEventCard message={message} />;
  }

  if (isFileChangeMessage(message)) {
    return <FileChangeCard message={message} onOpenFile={onOpenFile} />;
  }

  return <ToolCard message={message} onOpenFile={onOpenFile} />;
});

function AssistantMessageCard({ message }: { message: ChatMessage }) {
  return (
    <div className="assistant-message">
      <div className="assistant-avatar" aria-hidden="true">
        <Bot size={16} />
      </div>
      <div>
        <div className="assistant-bubble">
          <MessageText text={message.text} />
        </div>
        <time>{formatMessageTime(message.createdAt)}</time>
        <Copy className="copy-below" size={14} />
      </div>
    </div>
  );
}

function MessageText({ text }: { text: string }) {
  return (
    <div className="message-text-blocks">
      {parseMessageText(text).map((block, index) => {
        if (block.kind === "code") {
          return (
            <pre className="chat-code-block" key={`${block.kind}-${index}`}>
              {block.language ? <span>{block.language}</span> : null}
              <code>{block.text}</code>
            </pre>
          );
        }
        return block.text.split(/\n{2,}/u).filter(Boolean).map((paragraph, paragraphIndex) => (
          <p key={`${block.kind}-${index}-${paragraphIndex}`}>{paragraph}</p>
        ));
      })}
    </div>
  );
}

function FileChangeCard({
  message,
  onOpenFile
}: {
  message: ChatMessage;
  onOpenFile: (path: string) => void | Promise<void>;
}) {
  const filePath = extractToolFilePath(message.text);
  const fileName = filePath ? basename(filePath) : message.title || "文件变更";
  const lines = useMemo(() => buildDiffLines(message), [message.text, message.kind]);
  const added = lines.filter((line) => line.marker === "+").length;
  const removed = lines.filter((line) => line.marker === "-").length;

  return (
    <div className="chat-event-row transcript-event-card file-change-card kind-diff">
      <div className="file-change-header">
        <button
          type="button"
          className="file-change-name"
          disabled={!filePath}
          title={filePath ?? fileName}
          onClick={() => {
            if (filePath) {
              void onOpenFile(filePath);
            }
          }}
        >
          <FileText size={12} />
          <span>{fileName}</span>
        </button>
        <span className="file-change-stats">
          {added > 0 ? <em className="add">+{added}</em> : null}
          {removed > 0 ? <em className="del">-{removed}</em> : null}
        </span>
      </div>
      {lines.length > 0 ? (
        <div className="file-change-body">
          {lines.map((line, index) => (
            <div
              key={index}
              className={`diff-line ${line.marker === "+" ? "add" : line.marker === "-" ? "del" : ""}`}
            >
              <span className="diff-ln">{index + 1}</span>
              <span className="diff-mk">{line.marker}</span>
              <span className="diff-tx">{line.text || " "}</span>
            </div>
          ))}
        </div>
      ) : (
        <p className="file-change-empty">{message.isStreaming ? "正在写入…" : "暂无变更预览。"}</p>
      )}
    </div>
  );
}

function ToolCard({
  message,
  defaultExpanded = false,
  onOpenFile
}: {
  message: ChatMessage;
  defaultExpanded?: boolean;
  onOpenFile: (path: string) => void | Promise<void>;
}) {
  // File-change tools and failures stay expanded by default; read-ish noise folds to one line.
  const isError = message.kind === "error" || message.status === "failed";
  const isFileChange =
    message.kind === "diff" || ["edit", "write", "multiedit", "create", "create_file"].includes(toolName(message).toLowerCase());
  const [expanded, setExpanded] = useState(defaultExpanded || isError || isFileChange);
  const filePath = extractToolFilePath(message.text);
  const summary = toolHeaderSummary(message);
  const className = ["chat-event-row", "transcript-event-card", `kind-${message.kind}`, isError ? "error" : ""]
    .filter(Boolean)
    .join(" ");

  return (
    <div className={className}>
      <button type="button" className="event-card-header tool-card-header" onClick={() => setExpanded((value) => !value)}>
        {expanded ? <ChevronDown size={13} /> : <ChevronRight size={13} />}
        <span className="tool-card-name">{toolName(message)}</span>
        {summary ? (
          filePath ? (
            <span
              className="tool-card-summary tool-card-file"
              role="link"
              tabIndex={0}
              title={filePath}
              onClick={(event) => {
                event.stopPropagation();
                void onOpenFile(filePath);
              }}
              onKeyDown={(event) => {
                if (event.key === "Enter") {
                  event.stopPropagation();
                  void onOpenFile(filePath);
                }
              }}
            >
              {summary}
            </span>
          ) : (
            <span className="tool-card-summary">{summary}</span>
          )
        ) : null}
        {message.status ? <small>{message.status}</small> : null}
      </button>
      {expanded ? (
        <div className="tool-card-body">
          {message.subtitle ? <small className="event-card-subtitle">{message.subtitle}</small> : null}
          {message.text ? <pre>{message.text}</pre> : <p>暂无输出。</p>}
        </div>
      ) : null}
    </div>
  );
}

function ToolBatchCard({
  messages,
  onOpenFile
}: {
  messages: ChatMessage[];
  onOpenFile: (path: string) => void | Promise<void>;
}) {
  const [expanded, setExpanded] = useState(false);
  const readCount = messages.filter((message) => toolName(message).toLowerCase() === "read").length;
  const grepCount = messages.filter((message) => toolName(message).toLowerCase() === "grep").length;
  const globCount = messages.filter((message) => toolName(message).toLowerCase() === "glob").length;
  const callCount = messages.filter(isFoldableReadTool).length;
  const parts = [
    readCount > 0 ? `读取 ${readCount}` : null,
    grepCount > 0 ? `搜索 ${grepCount}` : null,
    globCount > 0 ? `匹配 ${globCount}` : null
  ].filter(Boolean);
  const summary = `${parts.length > 0 ? parts.join(" · ") : "工具"} · 共 ${callCount} 步`;

  return (
    <div className="chat-event-row transcript-event-card tool-batch-card">
      <button type="button" className="event-card-header tool-card-header" onClick={() => setExpanded((value) => !value)}>
        {expanded ? <ChevronDown size={13} /> : <ChevronRight size={13} />}
        <span className="tool-card-name">{summary}</span>
      </button>
      {expanded ? (
        <div className="tool-batch-body">
          {messages.map((message) => (
            <ToolCard key={message.id} message={message} onOpenFile={onOpenFile} />
          ))}
        </div>
      ) : null}
    </div>
  );
}

function DiagnosticEventCard({ message }: { message: ChatMessage }) {
  return (
    <div className="chat-event-row transcript-event-card diagnostic-card">
      <div className="event-card-header">
        <span>{kindLabel(message.kind)}</span>
        {message.status ? <small>{message.status}</small> : null}
      </div>
      <p>内部事件已隐藏，避免把原始协议内容直接显示在主对话中。</p>
    </div>
  );
}

function PermissionRequestCard({ message }: { message: ChatMessage }) {
  const respondToPermission = useChatStore((state) => state.respondToPermission);
  const waiting = message.status === "waiting";

  function respond(decision: PermissionDecision) {
    if (message.requestID) {
      respondToPermission(message.requestID, decision);
    }
  }

  return (
    <div className="chat-event-row permission-card">
      <span>{message.title || "permission"}</span>
      <p>{message.text}</p>
      <div className="permission-actions">
        <button type="button" disabled={!waiting} onClick={() => respond("deny")}>
          拒绝
        </button>
        <button type="button" disabled={!waiting} onClick={() => respond("allow")}>
          允许一次
        </button>
        <button type="button" disabled={!waiting} onClick={() => respond("allowForSession")}>
          本会话允许
        </button>
      </div>
    </div>
  );
}

function InteractiveRequestCard({ request }: { request: InteractiveRequest }) {
  const [selectedOptionIDs, setSelectedOptionIDs] = useState<string[]>([]);
  const [customText, setCustomText] = useState("");
  const respondToInteractiveRequest = useChatStore((state) => state.respondToInteractiveRequest);
  const waiting = request.status === "waiting";
  const canSubmit = waiting && (selectedOptionIDs.length > 0 || customText.trim().length > 0 || request.mode === "text");

  function toggleOption(optionID: string) {
    setSelectedOptionIDs((current) => {
      if (request.mode === "singleChoice") {
        return [optionID];
      }
      return current.includes(optionID) ? current.filter((id) => id !== optionID) : [...current, optionID];
    });
  }

  function submit(optionID?: string) {
    if (!waiting) {
      return;
    }
    const optionIDs = optionID ? [optionID] : selectedOptionIDs;
    respondToInteractiveRequest({
      requestID: request.id,
      selectedOptionIDs: optionIDs,
      customText: customText.trim() || null
    });
  }

  return (
    <div className="chat-event-row interactive-card">
      <span>{request.title}</span>
      <p>{request.prompt}</p>
      {request.options.length > 0 ? (
        <div className="interactive-options">
          {request.options.map((option) => {
            const active = selectedOptionIDs.includes(option.id);
            return (
              <button
                key={option.id}
                type="button"
                className={active ? "active" : ""}
                disabled={!waiting}
                onClick={() => {
                  toggleOption(option.id);
                  if (request.mode === "singleChoice" && !request.allowCustomInput) {
                    submit(option.id);
                  }
                }}
              >
                <b>{option.label}</b>
                {option.detail ? <small>{option.detail}</small> : null}
              </button>
            );
          })}
        </div>
      ) : null}
      {request.allowCustomInput || request.mode === "text" ? (
        <textarea
          value={customText}
          disabled={!waiting}
          placeholder={request.placeholder || "输入回复"}
          onChange={(event) => setCustomText(event.target.value)}
        />
      ) : null}
      <div className="permission-actions">
        <button type="button" disabled={!canSubmit} onClick={() => submit()}>
          提交
        </button>
      </div>
    </div>
  );
}

function MessageAttachmentStrip({ attachments }: { attachments: ChatMessageAttachment[] }) {
  const openFile = useEditorStore((state) => state.openFile);
  if (attachments.length === 0) {
    return null;
  }
  return (
    <div className="message-attachments">
      {attachments.map((attachment) => (
        <button key={attachment.id} type="button" onClick={() => void openFile(attachment.path)} title={attachment.path}>
          <FileText size={12} />
          {attachment.filename}
        </button>
      ))}
    </div>
  );
}

function formatMessageTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "";
  }
  return new Intl.DateTimeFormat("zh-CN", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false
  }).format(date);
}
