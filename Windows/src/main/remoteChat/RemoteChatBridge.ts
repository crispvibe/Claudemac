import { EventEmitter } from "node:events";
import { randomUUID } from "node:crypto";
import {
  commandAckSchema,
  commandSchema,
  makeResumeRequest,
  panelStateEnvelopeSchema,
  remoteVNCFrameType,
  type CommandAck,
  type CommandArgs,
  type CommandOp,
  type PanelStateEnvelope,
  type RemoteCommand
} from "../../shared/remoteProtocol.js";

export type RemoteChatBridgeStatus = "idle" | "connecting" | "resuming" | "connected" | "suspended" | "closed" | "error";

type MinimalWebSocket = {
  readyState: number;
  send(data: string): void;
  close(code?: number, reason?: string): void;
  addEventListener(type: "open" | "message" | "close" | "error", listener: (event: unknown) => void): void;
};

type WebSocketFactory = (url: string) => MinimalWebSocket;

type PendingCommand = {
  command: RemoteCommand;
  resolve: (ack: CommandAck) => void;
  reject: (error: Error) => void;
  timeout: NodeJS.Timeout;
};

export interface RemoteChatBridgeConnectOptions {
  endpoint: string;
  bearerToken?: string;
  sessionId?: string | null;
  lastRevision?: number | null;
}

export class RemoteChatBridge extends EventEmitter {
  private socket: MinimalWebSocket | null = null;
  private pending = new Map<string, PendingCommand>();
  private _status: RemoteChatBridgeStatus = "idle";
  private focusedSessionId: string | null = null;
  private lastRevision: number | null = null;
  private epoch = 0;

  constructor(
    private readonly webSocketFactory: WebSocketFactory = defaultWebSocketFactory,
    private readonly commandTimeoutMs = 15_000
  ) {
    super();
  }

  get status(): RemoteChatBridgeStatus {
    return this._status;
  }

  connect(options: RemoteChatBridgeConnectOptions): void {
    this.close("reconnect");
    this.epoch += 1;
    const epoch = this.epoch;
    this.focusedSessionId = options.sessionId ?? null;
    this.lastRevision = options.lastRevision ?? null;
    this.setStatus("connecting");

    const socket = this.webSocketFactory(remoteChatURL(options.endpoint, options.bearerToken));
    this.socket = socket;
    socket.addEventListener("open", () => {
      if (epoch !== this.epoch) {
        return;
      }
      this.setStatus("resuming");
      this.sendFrame(makeResumeRequest(this.focusedSessionId, this.lastRevision));
    });
    socket.addEventListener("message", (event: unknown) => {
      if (epoch === this.epoch) {
        this.handleMessage(event);
      }
    });
    socket.addEventListener("close", () => {
      if (epoch === this.epoch && this._status !== "closed") {
        this.rejectAll("Remote chat socket closed.");
        this.setStatus("suspended");
      }
    });
    socket.addEventListener("error", () => {
      if (epoch === this.epoch) {
        this.rejectAll("Remote chat socket error.");
        this.setStatus("error");
      }
    });
  }

  close(reason = "closed"): void {
    this.epoch += 1;
    this.rejectAll("Remote chat bridge closed.");
    this.socket?.close(1000, reason);
    this.socket = null;
    this.setStatus("closed");
  }

  async dispatch(op: CommandOp, args: CommandArgs = {}, sessionId = this.focusedSessionId): Promise<CommandAck> {
    const command = commandSchema.parse({
      type: remoteVNCFrameType.command,
      commandId: randomUUID(),
      op,
      sessionId,
      args
    });
    return this.dispatchCommand(command);
  }

  async dispatchCommand(command: RemoteCommand): Promise<CommandAck> {
    const parsed = commandSchema.parse(command);
    if (!this.socket || this.socket.readyState > 1) {
      throw new Error("Remote chat bridge is not connected.");
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(parsed.commandId);
        reject(new Error(`Remote command ${parsed.op} timed out.`));
      }, this.commandTimeoutMs);
      this.pending.set(parsed.commandId, { command: parsed, resolve, reject, timeout });
      this.sendFrame(parsed);
    });
  }

  requestSnapshot(): Promise<CommandAck> {
    return this.dispatch("requestSnapshot");
  }

  resume(sessionId = this.focusedSessionId, lastRevision = this.lastRevision): void {
    this.focusedSessionId = sessionId;
    this.lastRevision = lastRevision;
    this.setStatus("resuming");
    this.sendFrame(makeResumeRequest(sessionId, lastRevision));
  }

  private handleMessage(event: unknown): void {
    const rawData = event && typeof event === "object" && "data" in event ? (event as { data: unknown }).data : event;
    const text = typeof rawData === "string" ? rawData : Buffer.isBuffer(rawData) ? rawData.toString("utf8") : "";
    if (!text) {
      return;
    }
    const raw = JSON.parse(text) as unknown;
    const frameType = frameTypeOf(raw);
    if (frameType === remoteVNCFrameType.commandAck) {
      this.handleAck(commandAckSchema.parse(raw));
      return;
    }
    if (frameType === remoteVNCFrameType.panelState) {
      this.handlePanelState(panelStateEnvelopeSchema.parse(raw));
    }
  }

  private handleAck(ack: CommandAck): void {
    const pending = this.pending.get(ack.commandId);
    if (!pending) {
      this.emit("ack", ack);
      return;
    }
    clearTimeout(pending.timeout);
    this.pending.delete(ack.commandId);
    pending.resolve(ack);
    this.emit("ack", ack);
  }

  private handlePanelState(envelope: PanelStateEnvelope): void {
    this.focusedSessionId = envelope.sessionId ?? null;
    this.lastRevision = envelope.revision;
    if (this._status === "resuming") {
      this.setStatus("connected");
    }
    this.emit("panelState", envelope);
  }

  private sendFrame(frame: unknown): void {
    this.socket?.send(JSON.stringify(frame));
  }

  private rejectAll(message: string): void {
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timeout);
      pending.reject(new Error(message));
    }
    this.pending.clear();
  }

  private setStatus(status: RemoteChatBridgeStatus): void {
    this._status = status;
    this.emit("status", status);
  }
}

function frameTypeOf(value: unknown): string | null {
  if (!value || typeof value !== "object" || !("type" in value)) {
    return null;
  }
  const type = (value as { type: unknown }).type;
  return typeof type === "string" ? type : null;
}

function remoteChatURL(endpoint: string, bearerToken?: string): string {
  const url = new URL(endpoint);
  if (bearerToken) {
    url.searchParams.set("token", bearerToken);
  }
  return url.toString();
}

function defaultWebSocketFactory(url: string): MinimalWebSocket {
  const ctor = (globalThis as { WebSocket?: new (url: string) => MinimalWebSocket }).WebSocket;
  if (!ctor) {
    throw new Error("WebSocket is not available in this Electron runtime.");
  }
  return new ctor(url);
}
