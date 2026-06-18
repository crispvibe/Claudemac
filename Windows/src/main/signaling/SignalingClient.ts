import { EventEmitter } from "node:events";
import { z } from "zod";

const signalingPayloadSchema = z.object({
  type: z.enum(["offer", "answer", "candidate", "failed", "bye"]),
  sdp: z.string().optional(),
  sdpMid: z.string().nullable().optional(),
  sdpMLineIndex: z.number().int().optional(),
  candidate: z.unknown().optional()
}).passthrough();

export type SignalingPayload = z.infer<typeof signalingPayloadSchema>;

export const signalingEventSchema = z.object({
  type: z.string(),
  deviceId: z.number().int().positive().optional(),
  fromDeviceId: z.number().int().positive().optional(),
  toDeviceId: z.number().int().positive().optional(),
  connectionId: z.number().int().positive().optional(),
  status: z.string().optional(),
  reason: z.string().optional(),
  payload: signalingPayloadSchema.optional(),
  connection: z.unknown().optional(),
  online: z.boolean().optional(),
  message: z.string().optional()
}).passthrough();

export type SignalingEvent = z.infer<typeof signalingEventSchema>;

export type SignalingStatus = "idle" | "connecting" | "connected" | "reconnecting" | "closed" | "error";

export type TunnelHandlerEvent = {
  type: string;
  connectionId: number;
  frame?: string;
  reason?: string;
};

/** 入站隧道开启事件（别人打进来，本机是 toDeviceId / host 角色）。 */
export type InboundTunnelOpenEvent = {
  connectionId: number;
  fromDeviceId: number | null;
  toDeviceId: number | null;
};

/** 入站信令 relay 事件（WebRTC 协商：手机 offer/candidate 打到本机，host 作为 answerer）。 */
export type InboundRelayEvent = {
  connectionId: number;
  fromDeviceId: number | null;
  status: string | null;
  payload: SignalingPayload;
};

type MinimalWebSocket = {
  readyState: number;
  send(data: string): void;
  close(code?: number, reason?: string): void;
  addEventListener(type: "open" | "message" | "close" | "error", listener: (event: unknown) => void): void;
};

type WebSocketFactory = (url: string) => MinimalWebSocket;

export class SignalingClient extends EventEmitter {
  private socket: MinimalWebSocket | null = null;
  private reconnectTimer: NodeJS.Timeout | null = null;
  private reconnectDelayMs = 1_000;
  private shouldReconnect = false;
  private accessToken = "";
  private deviceId: number | null = null;
  private epoch = 0;
  private _status: SignalingStatus = "idle";
  private _lastConnectedAt: string | null = null;
  private _lastError: string | null = null;
  private tunnelHandlers = new Map<number, (event: TunnelHandlerEvent) => void>();
  private inboundTunnelOpenHandler: ((event: InboundTunnelOpenEvent) => void) | null = null;
  private inboundRelayHandler: ((event: InboundRelayEvent) => void) | null = null;

  constructor(
    private readonly baseURL = "https://acode.anna.vin",
    private readonly webSocketFactory: WebSocketFactory = defaultWebSocketFactory
  ) {
    super();
  }

  get status(): SignalingStatus {
    return this._status;
  }

  summary(): { status: SignalingStatus; lastConnectedAt: string | null; lastError: string | null } {
    return {
      status: this._status,
      lastConnectedAt: this._lastConnectedAt,
      lastError: this._lastError
    };
  }

  start(accessToken: string, deviceId: number): void {
    this.stop("restart");
    this.accessToken = accessToken;
    this.deviceId = deviceId;
    this.shouldReconnect = true;
    this.reconnectDelayMs = 1_000;
    this.connect();
  }

  stop(reason = "closed"): void {
    this.shouldReconnect = false;
    this.epoch += 1;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.socket?.close(1000, reason);
    this.socket = null;
    this.setStatus("closed");
  }

  relay(connectionId: number, toDeviceId: number, payload: SignalingPayload): boolean {
    return this.send({
      type: "relay",
      connectionId,
      toDeviceId,
      payload: signalingPayloadSchema.parse(payload)
    });
  }

  openTunnel(connectionId: number, toDeviceId: number): boolean {
    return this.send({ type: "tunnel_open", connectionId, toDeviceId });
  }

  sendTunnelFrame(connectionId: number, seq: number, frame: string): boolean {
    return this.send({ type: "tunnel_frame", connectionId, seq, frame });
  }

  sendTunnelClose(connectionId: number, reason: string): boolean {
    return this.send({ type: "tunnel_close", connectionId, reason });
  }

  setTunnelHandler(connectionId: number, handler: (event: TunnelHandlerEvent) => void): void {
    this.tunnelHandlers.set(connectionId, handler);
  }

  removeTunnelHandler(connectionId: number): void {
    this.tunnelHandlers.delete(connectionId);
  }

  /**
   * 注册入站隧道处理器（host 角色）：当别人对本机发起 `tunnel_open` 且尚未有对应
   * 的 per-connection handler 时回调。处理器应在内部用 `setTunnelHandler` 接管该
   * connectionId 后续的 `tunnel_frame` / `tunnel_close` / `tunnel_error`。
   */
  setInboundTunnelOpenHandler(handler: (event: InboundTunnelOpenEvent) => void): void {
    this.inboundTunnelOpenHandler = handler;
  }

  clearInboundTunnelOpenHandler(): void {
    this.inboundTunnelOpenHandler = null;
  }

  /**
   * 注册入站 relay 处理器（host 角色 WebRTC answerer）：收到手机经信令中转的
   * `offer` / `candidate` relay 帧时回调。出站方向（本机发起）不会用到此回调。
   */
  setInboundRelayHandler(handler: (event: InboundRelayEvent) => void): void {
    this.inboundRelayHandler = handler;
  }

  clearInboundRelayHandler(): void {
    this.inboundRelayHandler = null;
  }

  private connect(): void {
    if (!this.shouldReconnect || !this.deviceId) {
      return;
    }
    this.epoch += 1;
    const epoch = this.epoch;
    this.setStatus(this._status === "idle" ? "connecting" : "reconnecting");
    const socket = this.webSocketFactory(this.signalingURL());
    this.socket = socket;

    socket.addEventListener("open", () => {
      if (epoch !== this.epoch) {
        return;
      }
      this.send({ type: "hello", deviceId: this.deviceId });
    });
    socket.addEventListener("message", (event: unknown) => {
      if (epoch !== this.epoch) {
        return;
      }
      this.handleMessage(event);
    });
    socket.addEventListener("close", () => {
      if (epoch === this.epoch) {
        this.scheduleReconnect();
      }
    });
    socket.addEventListener("error", () => {
      if (epoch === this.epoch) {
        this._lastError = "Signaling socket error.";
        this.setStatus("error");
        this.scheduleReconnect();
      }
    });
  }

  private handleMessage(event: unknown): void {
    const rawData = event && typeof event === "object" && "data" in event ? (event as { data: unknown }).data : event;
    const text = typeof rawData === "string" ? rawData : Buffer.isBuffer(rawData) ? rawData.toString("utf8") : "";
    if (!text) {
      return;
    }
    const parsed = signalingEventSchema.parse(JSON.parse(text));
    if (parsed.type === "ping") {
      this.send({ type: "pong" });
      return;
    }
    if (parsed.type === "hello_ack") {
      this.reconnectDelayMs = 1_000;
      this._lastConnectedAt = new Date().toISOString();
      this._lastError = null;
      this.setStatus("connected");
    }
    if (parsed.type === "tunnel_open") {
      const connectionId = parsed.connectionId;
      // 只有不是某条出站隧道的 ack 路径时，才当作入站（host 角色）开启。
      if (connectionId && !this.tunnelHandlers.has(connectionId)) {
        this.inboundTunnelOpenHandler?.({
          connectionId,
          fromDeviceId: parsed.fromDeviceId ?? null,
          toDeviceId: parsed.toDeviceId ?? null
        });
      }
    }
    if (
      parsed.type === "tunnel_open_ack"
      || parsed.type === "tunnel_frame"
      || parsed.type === "tunnel_close"
      || parsed.type === "tunnel_error"
    ) {
      const connectionId = parsed.connectionId;
      if (connectionId) {
        const handler = this.tunnelHandlers.get(connectionId);
        handler?.({
          type: parsed.type,
          connectionId,
          frame: typeof parsed.frame === "string" ? parsed.frame : undefined,
          reason: parsed.reason ?? parsed.message
        });
      }
    }
    if (parsed.type === "relay" && this.inboundRelayHandler) {
      const connectionId = parsed.connectionId;
      if (connectionId && parsed.payload) {
        this.inboundRelayHandler({
          connectionId,
          fromDeviceId: parsed.fromDeviceId ?? null,
          status: parsed.status ?? null,
          payload: parsed.payload
        });
      }
    }
    this.emit("event", parsed);
  }

  private send(object: unknown): boolean {
    const socket = this.socket;
    if (!socket || socket.readyState > 1) {
      return false;
    }
    socket.send(JSON.stringify(object));
    return true;
  }

  private scheduleReconnect(): void {
    if (!this.shouldReconnect) {
      return;
    }
    this.setStatus("reconnecting");
    this.socket?.close();
    this.socket = null;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
    }
    const delay = this.reconnectDelayMs;
    this.reconnectDelayMs = Math.min(this.reconnectDelayMs * 2, 30_000);
    this.reconnectTimer = setTimeout(() => this.connect(), delay);
  }

  private signalingURL(): string {
    const url = new URL(this.baseURL);
    url.protocol = url.protocol === "http:" ? "ws:" : "wss:";
    url.pathname = "/remote/signaling/ws";
    url.searchParams.set("token", this.accessToken);
    return url.toString();
  }

  private setStatus(status: SignalingStatus): void {
    this._status = status;
    this.emit("status", this.summary());
  }
}

function defaultWebSocketFactory(url: string): MinimalWebSocket {
  const ctor = (globalThis as { WebSocket?: new (url: string) => MinimalWebSocket }).WebSocket;
  if (!ctor) {
    throw new Error("WebSocket is not available in this Electron runtime.");
  }
  return new ctor(url);
}
