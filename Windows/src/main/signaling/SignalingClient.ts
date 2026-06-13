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
